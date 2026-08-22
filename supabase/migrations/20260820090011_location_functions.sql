-- =============================================================================
-- 곁에(Gyeote) Phase 1: 위치 공유 RPC 함수
-- -----------------------------------------------------------------------------
-- user_locations / location_share_settings / location_history 테이블에는 직접
-- INSERT/UPDATE/DELETE grant를 주지 않는다(20260820090008~090010 참고).
-- 아래 SECURITY DEFINER 함수를 통해서만 쓰기를 허용하며, 각 함수는 내부에서
-- auth.uid() 기반으로 권한/불변식을 재검증한다.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0) 헬퍼: 특정 관계 그룹에 대한 상대의 공유 모드 조회 (근사 좌표 반올림 판단용)
--    - location_share_settings는 본인 행만 SELECT 가능하므로, get_peer_locations
--      (invoker 권한으로 실행되어 RLS가 그대로 적용됨)가 상대방의 모드를 알기
--      위해 이 security definer 헬퍼를 거친다.
--    - 정보 최소 노출: 호출자가 이미 그 위치를 볼 권한이 있는 경우
--      (can_view_location) 또는 본인 자신의 모드를 물어보는 경우에만 값을
--      반환한다. 그 외에는 null을 반환해 "임의 사용자의 공유 여부"를 알아내는
--      경로로 악용되지 않도록 한다.
-- -----------------------------------------------------------------------------
create or replace function public.get_share_mode(p_owner_id uuid, p_relationship_group_id uuid)
returns public.location_share_mode
language sql
security definer
stable
set search_path = public
as $$
  select s.mode
  from public.location_share_settings s
  where s.user_id = p_owner_id
    and s.relationship_group_id = p_relationship_group_id
    and (
      p_owner_id = auth.uid()
      or public.can_view_location(p_owner_id, auth.uid())
    );
$$;

revoke all on function public.get_share_mode(uuid, uuid) from public;
grant execute on function public.get_share_mode(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 1) 위치 핑 업서트: 본인의 user_locations 최신 행을 갱신 + location_history에
--    적재. "공유가 완전히 OFF"인 상태에서는 위치 저장 자체를 거부한다(프라이버시
--    원칙 — 서버가 불필요하게 위치를 보관하지 않음).
-- -----------------------------------------------------------------------------
create or replace function public.upsert_location_ping(
  p_location extensions.geography,
  p_accuracy_m numeric default null,
  p_battery_level smallint default null,
  p_is_charging boolean default null,
  p_movement_state text default null,
  p_captured_at timestamptz default now()
)
returns public.user_locations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.user_locations;
  v_result public.user_locations;
  v_has_active_share boolean;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  if extensions.geometrytype(p_location::extensions.geometry) <> 'POINT' then
    raise exception 'location must be a Point geography';
  end if;

  if p_movement_state is not null and p_movement_state not in ('stationary', 'walking', 'moving') then
    raise exception 'invalid movement_state: %', p_movement_state;
  end if;

  if p_captured_at is null then
    raise exception 'captured_at is required';
  end if;

  -- 프라이버시 게이트: mode가 off가 아닌 그룹이 하나도 없으면(=모든 그룹에서
  -- 완전히 꺼둔 경우) 위치 저장 자체를 거부한다. 일시중지(paused_until)는
  -- "누구에게 보일지"만 제어하는 가시성 문제이며 저장 허용 여부와는 무관하게
  -- 둔다 — 그래야 일시중지가 끝나는 즉시(새 GPS fix를 기다릴 필요 없이) 마지막
  -- 위치가 다시 노출될 수 있다. 완전 삭제는 mode가 실제로 'off'로 바뀔 때만
  -- set_location_share_mode()에서 수행한다.
  select exists (
    select 1
    from public.location_share_settings s
    where s.user_id = v_uid
      and s.mode <> 'off'
  ) into v_has_active_share;

  if not v_has_active_share then
    raise exception 'location sharing is off for all groups; enable sharing before sending a location ping';
  end if;

  select * into v_existing from public.user_locations where user_id = v_uid for update;

  -- 오프라인 큐 플러시 등으로 과거 시각의 좌표가 뒤늦게 도착한 경우, 이미 저장된
  -- 더 최신 captured_at 값보다 과거라면 역행을 방지하기 위해 무시하고 기존
  -- 최신 행을 그대로 반환한다.
  if found and v_existing.captured_at > p_captured_at then
    return v_existing;
  end if;

  insert into public.user_locations (
    user_id, location, accuracy_m, battery_level, is_charging, movement_state, captured_at, received_at
  ) values (
    v_uid, p_location, p_accuracy_m, p_battery_level, p_is_charging, p_movement_state, p_captured_at, now()
  )
  on conflict (user_id) do update set
    location = excluded.location,
    accuracy_m = excluded.accuracy_m,
    battery_level = excluded.battery_level,
    is_charging = excluded.is_charging,
    movement_state = excluded.movement_state,
    captured_at = excluded.captured_at,
    received_at = excluded.received_at
  returning * into v_result;

  insert into public.location_history (user_id, location, captured_at)
  values (v_uid, p_location, p_captured_at);

  -- Realtime 브로드캐스트 (실제 Supabase 환경에서만 존재하는 realtime 스키마가
  -- 있을 때만 동작; 20260820090012 참고).
  perform public.notify_location_ping(v_result);

  return v_result;
end;
$$;

revoke all on function public.upsert_location_ping(
  extensions.geography, numeric, smallint, boolean, text, timestamptz
) from public;
grant execute on function public.upsert_location_ping(
  extensions.geography, numeric, smallint, boolean, text, timestamptz
) to authenticated;

-- -----------------------------------------------------------------------------
-- 2) 그룹별 공유 모드 설정
--    OFF로 전환하더라도 다른 그룹에는 여전히 공유 중일 수 있으므로 무조건
--    user_locations 행을 지우지 않는다. "모든 그룹에서 OFF(또는 비활성 상태)"
--    인 경우에만 저장된 최신 위치를 즉시 삭제한다.
-- -----------------------------------------------------------------------------
create or replace function public.set_location_share_mode(
  p_relationship_group_id uuid,
  p_mode text,
  p_pause_minutes int default null
)
returns public.location_share_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_mode public.location_share_mode;
  v_paused_until timestamptz;
  v_result public.location_share_settings;
  v_any_active boolean;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  if not public.is_group_member(p_relationship_group_id, v_uid) then
    raise exception 'not a member of this group';
  end if;

  begin
    v_mode := p_mode::public.location_share_mode;
  exception when invalid_text_representation then
    raise exception 'invalid mode: % (expected off|precise|approx)', p_mode;
  end;

  if p_pause_minutes is not null then
    if p_pause_minutes <= 0 then
      raise exception 'pause_minutes must be a positive integer';
    end if;
    v_paused_until := now() + make_interval(mins => p_pause_minutes);
  else
    v_paused_until := null;
  end if;

  insert into public.location_share_settings (user_id, relationship_group_id, mode, paused_until)
  values (v_uid, p_relationship_group_id, v_mode, v_paused_until)
  on conflict (user_id, relationship_group_id) do update set
    mode = excluded.mode,
    paused_until = excluded.paused_until,
    updated_at = now()
  returning * into v_result;

  -- 이 사용자의 모든 그룹 설정이 실제로 'off'인지 확인한다(일시중지는 저장
  -- 삭제 트리거가 아니다 — upsert_location_ping()의 저장 게이트와 동일한 기준).
  select exists (
    select 1
    from public.location_share_settings s
    where s.user_id = v_uid
      and s.mode <> 'off'
  ) into v_any_active;

  if not v_any_active then
    delete from public.user_locations where user_id = v_uid;
  end if;

  return v_result;
end;
$$;

revoke all on function public.set_location_share_mode(uuid, text, int) from public;
grant execute on function public.set_location_share_mode(uuid, text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- 3) 그룹 내 상대들의 최신 위치 스냅샷 조회
--    SECURITY DEFINER가 아닌 일반(INVOKER) 함수로 정의한다: 호출자의 RLS가
--    user_locations / relationship_members / profiles에 그대로 적용되므로,
--    "누구의 위치가 보이는지"에 대한 단일 진실 공급원(RLS)을 이 함수에서
--    중복 구현하지 않는다. 다만 mode = 'approx'인 상대의 좌표는 약 100m
--    격자(0.001도 ≈ 111m)로 서버가 강제 반올림해서 반환한다.
-- -----------------------------------------------------------------------------
create or replace function public.get_peer_locations(p_relationship_group_id uuid)
returns table (
  user_id uuid,
  nickname text,
  location extensions.geography,
  accuracy_m numeric,
  battery_level smallint,
  is_charging boolean,
  movement_state text,
  captured_at timestamptz,
  received_at timestamptz,
  mode public.location_share_mode
)
language sql
stable
set search_path = public
as $$
  select
    ul.user_id,
    p.nickname,
    case
      when public.get_share_mode(ul.user_id, p_relationship_group_id) = 'approx' then
        extensions.st_setsrid(
          extensions.st_snaptogrid(ul.location::extensions.geometry, 0.001, 0.001),
          4326
        )::extensions.geography
      else ul.location
    end as location,
    case
      when public.get_share_mode(ul.user_id, p_relationship_group_id) = 'approx' then null
      else ul.accuracy_m
    end as accuracy_m,
    ul.battery_level,
    ul.is_charging,
    ul.movement_state,
    ul.captured_at,
    ul.received_at,
    public.get_share_mode(ul.user_id, p_relationship_group_id) as mode
  from public.user_locations ul
  join public.profiles p on p.id = ul.user_id
  join public.relationship_members rm
    on rm.user_id = ul.user_id
   and rm.group_id = p_relationship_group_id
  where ul.user_id <> auth.uid();
$$;

comment on function public.get_peer_locations(uuid) is
  '해당 관계 그룹에서 RLS상 조회 가능한 상대들의 최신 위치. mode=approx인 상대는 좌표를 약 100m 격자로 반올림해서 반환(서버 강제).';

revoke all on function public.get_peer_locations(uuid) from public;
grant execute on function public.get_peer_locations(uuid) to authenticated;
