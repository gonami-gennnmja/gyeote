-- =============================================================================
-- 곁에(Gyeote) 심사(App/Play Review)용 데모 데이터 시드
-- -----------------------------------------------------------------------------
-- 목적: 우리 앱은 "상대"가 있어야 지도가 의미를 갖는다. 심사 리뷰어가 데모
--   계정으로 로그인해 지도를 열었을 때 아무도 없으면 "기능을 찾을 수 없음"으로
--   반려되는 전형적 케이스를 막는다.
--
-- 이 스크립트가 만드는 것 (전부 멱등 — 제출 직전에 다시 돌려도 안전):
--   1) 데모 계정 A·B 를 같은 관계 그룹에 소속시킴
--   2) 계정 B 의 위치 공유 모드를 활성(precise, 일시중지 아님)으로
--   3) 계정 B 의 최신 위치 1건 (captured_at / received_at = 실행 시점 now())
--   → 리뷰어가 A 로 로그인해 지도를 열면 B 가 지도에 보인다.
--
-- ── 사전조건 ────────────────────────────────────────────────────────────────
--   데모 계정 A·B 가 이미 auth.users 에 있어야 한다. 대시보드
--   Authentication > Users > Add user 로 **비밀번호까지 설정해서** 생성한다
--   (리뷰어가 그 비밀번호로 로그인). auth.users insert 시
--   on_auth_user_created 트리거가 public.profiles 행을 자동 생성한다.
--   이 스크립트는 auth 계정을 만들지 않는다 — 이메일로 찾아 쓸 뿐이다.
--
-- ── 실행 방법 ───────────────────────────────────────────────────────────────
--   대시보드 SQL Editor > New query > 아래 두 이메일 값을 채우고 > Run.
--
-- ── 신선도(stale) 주의 ─────────────────────────────────────────────────────
--   지도는 위치가 30분 이상 지나면 흐리게(불투명도 0.55) 표시하고 "N분 전"
--   라벨을 붙인다(PeerLocation.staleThreshold / staleOpacity). 이 판정은
--   **user_locations.received_at** 기준이다(captured_at 아님). 이 스크립트는
--   두 값을 모두 now() 로 넣으므로, 실행 직후에는 "방금 전"으로 선명하게
--   보인다. 다만 심사가 며칠 뒤에 이뤄질 수 있으므로:
--     (a) 제출 직전에 이 스크립트를 다시 Run 한다(멱등이라 안전).
--     (b) 그래도 심사 시점엔 stale 일 수 있다 — 이건 고장이 아니라 정상
--         동작이며, App/Play Review 노트에 그 취지를 적는다(문구는
--         Din 에게 전달, docs/design 참고).
--   received_at 을 미래로 넣어 "영구 신선" 처럼 보이게 하는 우회는 쓰지
--   않는다(freshnessLabel 이 음수 diff 를 "방금 전"으로 처리해 동작은 하지만,
--   심사 데이터를 실제와 다르게 보이게 만드는 셈이라 지양).
-- =============================================================================

do $$
declare
  -- ▼▼▼ 가인님이 채우기 — 실제 데모 계정 이메일 ▼▼▼
  v_email_a text := 'DEMO_ACCOUNT_A_EMAIL';   -- 리뷰어가 로그인할 계정
  v_email_b text := 'DEMO_ACCOUNT_B_EMAIL';   -- 지도에 위치가 보일 상대 계정
  -- ▲▲▲

  -- 재실행 시 같은 그룹을 재사용하기 위한 고정 id (실제 그룹 id 와 충돌 확률
  -- 사실상 0 인 명백한 플레이스홀더 값).
  v_demo_group_id constant uuid := '11111111-1111-4111-a111-111111111111';

  -- 데모 위치: 서울시청 부근 (경도 lng, 위도 lat 순서 = POINT(lng lat)).
  v_demo_lng constant double precision := 126.9779;
  v_demo_lat constant double precision := 37.5665;

  v_a uuid;
  v_b uuid;
begin
  if v_email_a = 'DEMO_ACCOUNT_A_EMAIL' or v_email_b = 'DEMO_ACCOUNT_B_EMAIL' then
    raise exception '데모 계정 이메일 두 개(v_email_a / v_email_b)를 먼저 채우세요';
  end if;

  select id into v_a from auth.users where email = v_email_a;
  select id into v_b from auth.users where email = v_email_b;

  if v_a is null then
    raise exception '데모 계정 A (%) 를 auth.users 에서 찾을 수 없습니다 — 대시보드 Auth 에서 먼저 생성하세요', v_email_a;
  end if;
  if v_b is null then
    raise exception '데모 계정 B (%) 를 auth.users 에서 찾을 수 없습니다 — 대시보드 Auth 에서 먼저 생성하세요', v_email_b;
  end if;
  if v_a = v_b then
    raise exception '데모 계정 A 와 B 가 동일합니다 — 서로 다른 계정이어야 합니다';
  end if;

  -- 1) 프로필 닉네임을 데모용으로 보기 좋게(트리거가 넣은 이메일 로컬파트 대체). 멱등.
  update public.profiles set nickname = '데모-리뷰어' where id = v_a;
  update public.profiles set nickname = '데모-상대'   where id = v_b;

  -- 2) 관계 그룹 (고정 id 로 upsert). created_by 는 A.
  insert into public.relationship_groups (id, type, name, created_by)
  values (v_demo_group_id, 'couple', '심사용 데모 그룹', v_a)
  on conflict (id) do update
    set type = excluded.type,
        name = excluded.name,
        created_by = excluded.created_by;

  -- 3) 멤버십 — A(owner), B(member). PK (group_id, user_id). 멱등.
  insert into public.relationship_members (group_id, user_id, role) values
    (v_demo_group_id, v_a, 'owner'),
    (v_demo_group_id, v_b, 'member')
  on conflict (group_id, user_id) do update set role = excluded.role;

  -- 4) B 의 공유 모드 활성 (precise, 일시중지 아님). PK (user_id, relationship_group_id). 멱등.
  insert into public.location_share_settings (user_id, relationship_group_id, mode, paused_until)
  values (v_b, v_demo_group_id, 'precise', null)
  on conflict (user_id, relationship_group_id) do update
    set mode = 'precise',
        paused_until = null;

  -- 5) B 의 최신 위치 1건. PK user_id (1인 1행). captured_at/received_at = now(). 멱등.
  --    stale 판정은 received_at 기준이므로 재실행 때마다 신선도가 갱신된다.
  insert into public.user_locations
    (user_id, location, accuracy_m, battery_level, is_charging, movement_state, captured_at, received_at)
  values (
    v_b,
    ('SRID=4326;POINT(' || v_demo_lng || ' ' || v_demo_lat || ')')::extensions.geography,
    12.0,        -- accuracy_m
    82,          -- battery_level
    false,       -- is_charging
    'stationary',-- movement_state
    now(),       -- captured_at
    now()        -- received_at
  )
  on conflict (user_id) do update
    set location       = excluded.location,
        accuracy_m     = excluded.accuracy_m,
        battery_level  = excluded.battery_level,
        is_charging    = excluded.is_charging,
        movement_state = excluded.movement_state,
        captured_at    = now(),
        received_at    = now();

  raise notice '데모 시드 적용 완료 — group=% A=% B=% / B 위치 captured_at=received_at=now()',
    v_demo_group_id, v_a, v_b;
end $$;

-- ── 확인 ────────────────────────────────────────────────────────────────────
-- SQL Editor 에서는 auth.uid() 가 없어 get_peer_locations() 를 그대로 흉내낼 수
-- 없다. 아래로 시드 결과를 눈으로 확인하고, 최종 확인은 앱에서 A 로 로그인해
-- 지도를 열어서 한다.
select
  g.name                              as group_name,
  (select nickname from public.profiles where id = m_a.user_id) as member_a,
  (select nickname from public.profiles where id = m_b.user_id) as member_b,
  s.mode                              as b_share_mode,
  s.paused_until                      as b_paused_until,
  extensions.st_y(ul.location::extensions.geometry) as b_lat,
  extensions.st_x(ul.location::extensions.geometry) as b_lng,
  ul.received_at                      as b_received_at,
  now() - ul.received_at              as b_age
from public.relationship_groups g
join public.relationship_members m_a on m_a.group_id = g.id and m_a.role = 'owner'
join public.relationship_members m_b on m_b.group_id = g.id and m_b.role = 'member'
join public.location_share_settings s on s.relationship_group_id = g.id and s.user_id = m_b.user_id
join public.user_locations ul on ul.user_id = m_b.user_id
where g.id = '11111111-1111-4111-a111-111111111111';

-- ── 정리(teardown) ─────────────────────────────────────────────────────────
-- 심사 통과 후 데모 관계 데이터를 지우고 싶으면 아래 블록의 주석을 풀어 Run.
-- (auth.users 의 데모 계정 자체는 대시보드 Auth 에서 지운다. 계정을 지우면
--  on delete cascade 로 아래 데이터도 함께 사라지므로, 보통은 이 블록이
--  필요없다.) 위치/설정만 지우고 계정·그룹은 남기려면 앞 두 delete 만.
/*
delete from public.user_locations
 where user_id in (select user_id from public.relationship_members
                    where group_id = '11111111-1111-4111-a111-111111111111');
delete from public.location_share_settings
 where relationship_group_id = '11111111-1111-4111-a111-111111111111';
delete from public.relationship_members
 where group_id = '11111111-1111-4111-a111-111111111111';
delete from public.relationship_groups
 where id = '11111111-1111-4111-a111-111111111111';
*/
