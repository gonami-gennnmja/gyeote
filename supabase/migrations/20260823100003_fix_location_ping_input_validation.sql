-- =============================================================================
-- 곁에(Gyeote) 위치 핑 입력 검증 누락 수정 (원시 제약조건 에러 노출, P0-4)
-- -----------------------------------------------------------------------------
-- Rena(Reviewer) 재리뷰 지적: upsert_location_ping()은 p_location 타입,
-- movement_state, captured_at은 명시적으로 검증하지만 accuracy_m(>= 0)과
-- battery_level(0~100)은 검증 없이 바로 INSERT한다. user_locations
-- 테이블에는 이 두 컬럼에 CHECK 제약조건이 걸려 있으므로
-- (20260820090009_user_locations.sql), 클라이언트가 음수 accuracy_m이나
-- 101 이상 battery_level을 보내면 Postgres가 다음과 같은 원시 메시지를
-- 던지고 이게 PostgrestException.message로 그대로 화면까지 도달한다:
--
--   new row for relation "user_locations" violates check constraint
--   "user_locations_battery_level_check"
--
-- 테이블명과 자동생성된 제약조건명이 사용자 화면에 노출되는 내부 구현 정보
-- 유출이다. 스푸핑/접근범위 우회(100002)와는 성격이 다른 결함(권한/격리가
-- 아니라 입력 검증 누락)이라 별도 마이그레이션으로 분리한다.
--
-- 수정: movement_state와 동일한 패턴으로, INSERT 이전에 accuracy_m/
-- battery_level 범위를 명시적으로 검증해 사람이 읽을 수 있는 예외로 먼저
-- 걸러지게 한다. 원본 CHECK 제약조건은 그대로 두어(방어 심층화) 이 검증을
-- 우회하는 다른 쓰기 경로가 생기더라도 DB가 최종 방어선 역할을 계속한다.
-- =============================================================================

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

  if p_accuracy_m is not null and p_accuracy_m < 0 then
    raise exception 'accuracy_m must be non-negative';
  end if;

  if p_battery_level is not null and p_battery_level not between 0 and 100 then
    raise exception 'battery_level must be between 0 and 100';
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

comment on function public.upsert_location_ping(
  extensions.geography, numeric, smallint, boolean, text, timestamptz
) is
  '본인 위치 핑 업서트 + location_history 적재. accuracy_m(>=0)/battery_level(0~100)/movement_state/captured_at을 INSERT 전에 명시적으로 검증해 사람이 읽을 수 있는 예외로 걸러낸다(원시 user_locations CHECK 제약조건 위반 메시지가 클라이언트까지 노출되는 것을 방지). 모든 그룹이 off면 거부.';
