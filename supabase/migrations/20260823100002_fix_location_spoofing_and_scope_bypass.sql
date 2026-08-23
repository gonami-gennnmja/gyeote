-- =============================================================================
-- 곁에(Gyeote) 위치 공유 보안 수정: 스푸핑(HIGH-1) + 접근범위 우회(HIGH-2)
-- -----------------------------------------------------------------------------
-- Rena(Reviewer)가 지적한 이슈를 수정한다. 최초 리뷰에서 나온 HIGH-1/HIGH-2에
-- 더해, 재리뷰에서 "HIGH-2와 같은 종류의 그룹 경계 우회"가 형제 함수
-- get_share_mode()에 남아있는 것(A), get_peer_locations() 자체의 CASE
-- 분기가 mode='off'/설정 없음일 때 정밀 좌표를 흘리는 잔여 버그(B), 그리고
-- 일시중지(paused_until)가 읽기 경로(get_peer_locations)에서는 그룹별로
-- 적용되지 않는 것(C, Plexa 재확인 지적)이 추가로 발견되어 같이 수정한다.
-- 세 건 모두 "그룹별로 다르게 설정된 상태(멤버십/모드/일시중지)를 크로스-
-- 그룹 판별(can_view_location)로 대체해버려서, 그룹 A에서만 활성 공유
-- 중이어도 그룹 B의 정보에 접근/추론 가능해지는" 동일한 결함 패턴이므로
-- 한 마이그레이션에 묶는다.
--
-- [HIGH-1] 위치 스푸핑: notify_location_ping()은 SECURITY DEFINER이면서
--   `grant execute ... to authenticated`가 걸려 있어, 클라이언트가
--   upsert_location_ping()을 거치지 않고 이 함수를 직접 RPC로 호출할 수
--   있었다. 이 함수는 인자로 받은 user_locations 행(row)의 user_id를 그대로
--   신뢰해 realtime.send()로 브로드캐스트하므로, 인증된 사용자 누구나
--   임의의 p_location.user_id를 지정해 그 사람 명의로 위조된 좌표를
--   "relationship:{group_id}:location" 토픽에 전파할 수 있었다(피해자 본인의
--   실제 그룹 목록을 순회해 그 각각에 브로드캐스트하므로, 상대방 앱에는
--   실제로 그 사람이 위조된 위치로 이동한 것처럼 보이게 된다).
--   수정: 클라이언트에는 execute 권한을 주지 않아 upsert_location_ping()
--   내부 호출로만 도달 가능하게 하고, 함수 내부에도 방어적으로
--   p_location.user_id = auth.uid() 검증을 추가한다(정책 grant 실수로
--   다시 노출되더라도 스푸핑이 불가능하도록 이중 방어).
--
-- [HIGH-2] 접근범위 우회: get_peer_locations(p_relationship_group_id)가
--   호출자가 실제로 그 그룹의 멤버인지 전혀 검증하지 않았다. 기반 RLS
--   정책(user_locations_select_shared → can_view_location)은 "호출자와
--   대상이 활성 공유 중인 그룹이 하나라도 있는지"만 판별하고 어떤
--   특정 그룹인지는 보지 않으므로, 호출자가 자신이 속하지 않은 임의의
--   group_id를 인자로 넘겨도 "그 그룹의 다른 멤버와 다른 그룹에서
--   활성 공유 중"이기만 하면 해당 멤버의 실시간 위치(및 닉네임)가
--   그대로 반환됐다 — 즉 그룹 경계를 넘어 자신이 속하지 않은 그룹의
--   위치 정보를 열람할 수 있는 접근범위 우회였다.
--   수정: 호출자가 p_relationship_group_id의 실제 멤버인지를
--   is_group_member()로 명시적으로 검증하도록 WHERE 절에 추가한다
--   (set_location_share_mode()가 이미 쓰기 경로에서 쓰는 것과 동일한
--   검증을 읽기 경로에도 적용).
--
-- [A] get_share_mode 그룹경계 우회(HIGH-2와 동일 패턴, 재리뷰 지적):
--   get_share_mode(p_owner_id, p_relationship_group_id)는 authenticated에
--   직접 EXECUTE가 걸린 RPC이면서, "호출자가 p_relationship_group_id의
--   멤버인지"를 전혀 확인하지 않고 `can_view_location(p_owner_id,
--   auth.uid())`(= "어떤 그룹에서든 활성 공유 중이면 true"인 크로스-그룹
--   판별)만 확인했다. 즉 호출자가 피해자와 그룹 A에서만 활성 공유 중이어도,
--   자신이 속하지 않은 그룹 B의 id를 직접 넘겨 get_share_mode(피해자, 그룹B)를
--   호출하면 그룹 B에 대한 피해자의 공유 모드(및 그룹 B 멤버십 여부)를
--   알아낼 수 있었다 — get_peer_locations에서 막은 것과 같은 종류의 그룹
--   경계 우회가 형제 함수로 그대로 열려 있었다.
--   수정: WHERE 절에 is_group_member(p_relationship_group_id, auth.uid())를
--   추가한다. get_peer_locations()는 INVOKER 함수라 이 함수를 "실제 호출자"
--   권한으로 호출하므로 EXECUTE grant 자체는 유지해야 한다(notify_location_ping
--   처럼 revoke로 닫을 수 없다) — 로직 안쪽에서 멤버십을 검증하는 방식으로
--   막는다. 비멤버 호출 시에는 (get_peer_locations와 일관되게) 예외가 아니라
--   NULL을 반환한다: 예외를 던지면 "이 그룹이 존재하는지" 자체가 오라클이
--   되어 버리기 때문이다.
--
-- [B] get_peer_locations CASE 분기의 잔여 유출(재리뷰 지적, 이번 수정과
--   무관하게 원래부터 있던 버그이나 이번에 다시 정의하는 함수라 같이 고침):
--   CASE 분기가 get_share_mode() = 'approx'만 반올림 처리하고 나머지는 모두
--   else(정밀 좌표 그대로)로 떨어진다. get_share_mode가 'off'를 반환하거나
--   (해당 그룹에서 명시적으로 껐음) 아예 NULL을 반환하는(해당 그룹에 대한
--   location_share_settings 행 자체가 없음) 두 경우 모두 정밀 좌표가 그대로
--   노출됐다. RLS(can_view_location)는 "어떤 그룹에서든 활성 공유 중이면
--   통과"이므로, 피해자가 그룹 G1에서는 off, 그룹 G2에서는 공유 중이면
--   get_peer_locations(G1) 호출 시(G2 덕에 RLS는 통과) G1에서 꺼둔 사람의
--   정밀 좌표가 그대로 노출됐다 — "이 그룹에서는 안 보이게 껐다"는 사용자
--   기대와 정면으로 어긋난다.
--   수정: WHERE 절에 get_share_mode(...) in ('precise', 'approx') 조건을
--   추가해, 해당 그룹에서 mode가 명시적으로 precise/approx인 경우만 결과에
--   포함시킨다(off/설정 없음/NULL은 결과에서 완전히 제외).
--
-- [C] 일시중지(paused_until)가 읽기 경로에서 그룹별로 적용되지 않음:
--   paused_until은 mode 컬럼을 바꾸지 않고 location_share_settings의 별도
--   컬럼에만 기록되므로, 일시중지 중이어도 get_share_mode()는 여전히
--   'precise'/'approx'를 반환하고 위 (B)에서 추가한
--   `get_share_mode(...) in ('precise', 'approx')` 필터를 그대로 통과한다.
--   일시중지를 실제로 반영하는 건 user_locations의 RLS(can_view_location)
--   뿐인데, 이는 HIGH-2에서 확인했듯 "어떤 그룹에서든" 판별하는 크로스-그룹
--   함수다. 그 결과: 피해자가 그룹 G1에서는 일시중지, 그룹 G2에서는 정상
--   공유 중이고 호출자가 두 그룹 모두의 멤버이면, get_peer_locations(G1)
--   호출 시 RLS는 G2 덕분에 통과하고 is_group_member(G1)/get_share_mode(G1)
--   모두 통과해 G1에서 일시중지해둔 위치가 그대로 반환된다. 이는 특히
--   notify_location_ping()의 브로드캐스트 루프가 이미 그룹별로
--   `paused_until is null or paused_until <= now()`를 검사해 일시중지된
--   그룹에는 애초에 브로드캐스트하지 않는 것과 어긋난다 — 사용자가 일시중지를
--   누르면 실시간 갱신은 멈추지만, 상대가 폴링(새로고침)으로 get_peer_locations를
--   다시 부르면 그 그룹에서 일시중지해둔 위치가 다시 보이는 모순이 있었다.
--   수정: get_share_mode와 동일한 멤버십/가시성 게이팅을 쓰는 새 헬퍼
--   is_location_paused(p_owner_id, p_relationship_group_id)를 추가하고,
--   get_peer_locations의 WHERE 절에 `not coalesce(is_location_paused(...),
--   true)` 조건을 더한다(비멤버/비가시 상태에서 NULL이 나오면 기본값을
--   "일시중지된 것으로 간주"(제외)로 두어, (A)에서 세운 "비멤버에게는 예외
--   대신 조용한 제외" 원칙을 그대로 유지하면서 실패 시 기본을 안전한 쪽으로
--   둔다). get_share_mode 자체는 건드리지 않는다 — 본인이 자기 모드를 조회할
--   때(p_owner_id = auth.uid())는 일시중지 여부와 무관하게 "설정된 모드"를
--   그대로 알 수 있어야 하므로, 그 계약을 이 수정으로 바꾸지 않는다.
-- =============================================================================

create or replace function public.notify_location_ping(p_location public.user_locations)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_realtime boolean;
  v_group record;
  v_geog extensions.geography;
  v_payload jsonb;
begin
  -- 방어적 재검증: 이 함수는 upsert_location_ping() 내부에서만 호출되어야
  -- 하며, 그 경우 p_location.user_id는 항상 auth.uid()와 일치한다. grant
  -- 실수 등으로 클라이언트가 직접 호출하더라도 타인 명의로 브로드캐스트를
  -- 위조할 수 없도록 여기서도 반드시 재확인한다.
  if p_location.user_id is distinct from auth.uid() then
    raise exception 'cannot broadcast a location ping on behalf of another user';
  end if;

  select exists (select 1 from pg_namespace where nspname = 'realtime')
    into v_has_realtime;

  if not v_has_realtime then
    -- 실제 Supabase 플랫폼이 아닌 환경(예: 순수 로컬 Postgres 검증 환경)에서는
    -- 브로드캐스트를 생략한다. 클라이언트는 이 경우 postgres_changes 구독으로
    -- 대체 가능(README 참고).
    return;
  end if;

  for v_group in
    select rm.group_id, s.mode
    from public.relationship_members rm
    join public.location_share_settings s
      on s.relationship_group_id = rm.group_id
     and s.user_id = rm.user_id
    where rm.user_id = p_location.user_id
      and s.mode <> 'off'
      and (s.paused_until is null or s.paused_until <= now())
  loop
    if v_group.mode = 'approx' then
      v_geog := extensions.st_setsrid(
        extensions.st_snaptogrid(p_location.location::extensions.geometry, 0.001, 0.001),
        4326
      )::extensions.geography;
    else
      v_geog := p_location.location;
    end if;

    v_payload := jsonb_build_object(
      'user_id', p_location.user_id,
      'longitude', extensions.st_x(v_geog::extensions.geometry),
      'latitude', extensions.st_y(v_geog::extensions.geometry),
      'accuracy_m', case when v_group.mode = 'approx' then null else p_location.accuracy_m end,
      'battery_level', p_location.battery_level,
      'is_charging', p_location.is_charging,
      'movement_state', p_location.movement_state,
      'captured_at', p_location.captured_at,
      'mode', v_group.mode
    );

    perform realtime.send(
      v_payload,
      'location_update',
      'relationship:' || v_group.group_id::text || ':location',
      true
    );
  end loop;
end;
$$;

comment on function public.notify_location_ping(public.user_locations) is
  'upsert_location_ping()에서만 호출되는 내부 헬퍼(클라이언트에 execute 권한 없음). relationship:{group_id}:location 토픽으로 위치 변경을 브로드캐스트. p_location.user_id = auth.uid() 검증으로 타인 명의 스푸핑을 차단.';

-- [HIGH-1 수정 핵심] 클라이언트(authenticated)에는 더 이상 execute 권한을
-- 주지 않는다. upsert_location_ping()은 SECURITY DEFINER로 실행되므로 이
-- revoke와 무관하게 내부에서 계속 notify_location_ping()을 호출할 수 있다.
revoke all on function public.notify_location_ping(public.user_locations) from public;
revoke execute on function public.notify_location_ping(public.user_locations) from authenticated;

-- -----------------------------------------------------------------------------
-- [A 수정] get_share_mode: 호출자가 p_relationship_group_id의 실제 멤버가
-- 아니면 NULL을 반환한다(예외 아님 — get_peer_locations와 동일한 관례로
-- "그룹 존재 여부" 오라클을 만들지 않는다).
-- -----------------------------------------------------------------------------
create or replace function public.get_share_mode(p_owner_id uuid, p_relationship_group_id uuid)
returns public.location_share_mode
language sql
security definer
stable
set search_path = public
as $$
  -- 이 is_group_member 검증은 get_peer_locations 경유 호출 관점에서는 바깥
  -- WHERE의 is_group_member와 중복처럼 보일 수 있지만, 제거하면 안 된다:
  -- get_share_mode는 authenticated에 EXECUTE가 걸린 독립 RPC라서 클라이언트가
  -- get_peer_locations를 거치지 않고 이 함수를 직접 호출하는 경로가 있고,
  -- 그 경로에서는 이 검증이 (A)에서 막은 그룹경계 우회에 대한 유일한 방어선이다
  -- — 걷어내면 (A)가 그대로 되살아난다.
  select s.mode
  from public.location_share_settings s
  where s.user_id = p_owner_id
    and s.relationship_group_id = p_relationship_group_id
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and (
      p_owner_id = auth.uid()
      or public.can_view_location(p_owner_id, auth.uid())
    );
$$;

comment on function public.get_share_mode(uuid, uuid) is
  '특정 관계 그룹에서의 공유 모드 조회. 호출자가 p_relationship_group_id의 실제 멤버가 아니면 NULL(예외 아님 — 그룹 존재 여부 오라클 방지). 멤버라도 본인 자신을 조회하는 경우이거나 can_view_location()이 true인 경우에만 값을 반환.';

-- get_peer_locations()가 INVOKER 함수로서 이 함수를 실제 호출자 권한으로
-- 호출하므로, EXECUTE grant 자체는 유지한다(notify_location_ping처럼
-- revoke로 닫을 수 없다 — 멤버십 검증은 위 로직 안쪽에서 처리).
revoke all on function public.get_share_mode(uuid, uuid) from public;
grant execute on function public.get_share_mode(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- [C 수정] is_location_paused: 특정 관계 그룹에서 대상의 위치 공유가 지금
-- 일시중지 중인지 판별한다. get_share_mode와 동일한 멤버십/가시성 게이팅을
-- 쓰되(비멤버/비가시 상태에서는 NULL 반환 — 예외로 오라클을 만들지 않는다),
-- get_peer_locations에서 이 값이 NULL이면 coalesce로 "일시중지된 것으로
-- 간주"(안전 쪽 기본값)해서 사용한다.
-- -----------------------------------------------------------------------------
create or replace function public.is_location_paused(p_owner_id uuid, p_relationship_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select s.paused_until is not null and s.paused_until > now()
  from public.location_share_settings s
  where s.user_id = p_owner_id
    and s.relationship_group_id = p_relationship_group_id
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and (
      p_owner_id = auth.uid()
      or public.can_view_location(p_owner_id, auth.uid())
    );
$$;

comment on function public.is_location_paused(uuid, uuid) is
  '특정 관계 그룹에서 대상의 위치 공유가 지금 일시중지(paused_until > now()) 중인지 판별. 호출자가 그 그룹의 멤버가 아니거나 볼 권한이 없으면 NULL(예외 아님 — get_share_mode와 동일한 관례).';

revoke all on function public.is_location_paused(uuid, uuid) from public;
grant execute on function public.is_location_paused(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- [HIGH-2 / B / C 수정] get_peer_locations:
--   - (HIGH-2) 호출자가 p_relationship_group_id의 실제 멤버일 때만 결과를
--     반환한다. 기존에는 이 검증이 없어, 기반 RLS(can_view_location)가
--     "다른 그룹에서의 활성 공유"만으로 행을 통과시키는 특성을 악용해
--     호출자가 속하지 않은 그룹의 위치를 조회할 수 있었다.
--   - (B) get_share_mode(...) in ('precise', 'approx') 조건을 WHERE에
--     추가해, 해당 그룹에서 mode가 'off'이거나 설정이 아예 없는(NULL)
--     상대는 결과에서 완전히 제외한다. 이전에는 CASE 분기가 'approx'만
--     특별 취급하고 나머지(off/NULL 포함)를 전부 정밀 좌표로 반환했다.
--   - (C) not coalesce(is_location_paused(...), true) 조건을 WHERE에 추가해,
--     해당 그룹에서 지금 일시중지 중인 상대도 결과에서 제외한다(브로드캐스트
--     경로의 paused_until 검사와 동작을 맞춘다).
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
  where ul.user_id <> auth.uid()
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and public.get_share_mode(ul.user_id, p_relationship_group_id) in ('precise', 'approx')
    and not coalesce(public.is_location_paused(ul.user_id, p_relationship_group_id), true);
$$;

comment on function public.get_peer_locations(uuid) is
  '호출자가 실제 멤버인 관계 그룹에서, RLS상 조회 가능하고 해당 그룹에서 mode가 precise/approx로 켜져 있으며 지금 일시중지 중이 아닌 상대들의 최신 위치. mode=approx인 상대는 좌표를 약 100m 격자로 반올림해서 반환(서버 강제). 호출자가 해당 그룹의 멤버가 아니거나, 상대가 해당 그룹에서 off/미설정/일시중지 중이면 그 상대는 결과에서 제외된다.';

revoke all on function public.get_peer_locations(uuid) from public;
grant execute on function public.get_peer_locations(uuid) to authenticated;
