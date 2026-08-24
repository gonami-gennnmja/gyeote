-- =============================================================================
-- 곁에(Gyeote) 위치 공유 보안 회귀 테스트 (pgTAP 미사용, 순수 SQL 단언)
-- -----------------------------------------------------------------------------
-- 대상: supabase/migrations/20260823100002_fix_location_spoofing_and_scope_bypass.sql,
-- 20260823100003_fix_location_ping_input_validation.sql. Rena 재검토
-- (docs/review/location-sharing-security-rereview.md)에서 지적된 항목 포함
-- 총 6개 취약점의 회귀 테스트:
--   [HIGH-1] notify_location_ping() 위치 스푸핑
--   [HIGH-2] get_peer_locations() 접근범위(그룹 경계) 우회
--   [C = 100002의 A] get_share_mode()의 동일한 종류의 그룹 경계 우회 (섹션 3)
--   [D = 100002의 B] get_peer_locations()가 mode='off'/설정 없음일 때도 정밀 좌표를 반환 (섹션 2-확장)
--   [F = 100002의 C] 일시중지(paused_until)가 get_peer_locations에서 그룹별로 적용되지 않음
--   [E = 100003] upsert_location_ping()의 accuracy_m/battery_level 범위 검증 누락으로 인한
--       원시 제약조건 위반 메시지 노출 (P0-4)
-- 이 6건 모두 100002/100003이 적용된 최신 마이그레이션 상태에서는 PASS여야
-- 한다(실제 실행 결과는 보고 참고 — 100002/100003 적용 전 버전으로 돌리면
-- C/D/F/E가 FAIL로 나오므로, FAIL이 보이면 먼저 테스트 DB에 적용된 마이그레이션
-- 버전부터 확인할 것).
--
-- 이 환경에는 Docker/Supabase CLI/pgTAP 확장이 없어 pgTAP 문법(`plan()`,
-- `throws_matching()` 등)을 쓸 수 없다. 대신 각 케이스를 DO 블록으로 감싸
-- 기대와 다르면 그 블록 안에서 RAISE NOTICE 'FAIL: ...'을 출력하도록 했다
-- (예외를 트랜잭션 밖으로 던지지 않으므로 뒤 케이스들도 계속 실행된다).
-- 성공한 케이스는 RAISE NOTICE 'PASS: ...'를 출력한다. 실행 후 출력에서
-- 'FAIL:'을 grep하면 실패한 항목만 바로 확인할 수 있다.
--
-- 로컬 실행 방법 (Docker/Supabase CLI 없는 이 샌드박스에서 실제 검증한 방법):
--   1) 로컬 Postgres 14 + PostGIS가 떠 있어야 한다(이 샌드박스에는 이미 떠 있음).
--   2) auth.uid()를 흉내내는 최소 스텁이 필요하다 — 이 리포에는 정식 스텁이
--      없어서, 아래와 동일한 내용을 임시로 만들어 적용했다(`auth`/`extensions`
--      스키마 생성 + `auth.users` 최소 테이블 + `auth.uid()` 함수 +
--      `authenticated`/`anon` 롤 + 두 스키마에 대한 `usage` grant):
--        create schema if not exists auth;
--        create schema if not exists extensions;
--        create table auth.users (id uuid primary key default gen_random_uuid(),
--          email text unique, raw_user_meta_data jsonb not null default '{}'::jsonb,
--          created_at timestamptz not null default now());
--        create function auth.uid() returns uuid language sql stable as
--          $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid; $$;
--        create role authenticated nologin; create role anon nologin;
--        grant usage on schema auth, extensions to authenticated, anon;
--      실제 Supabase 프로젝트에는 이 스텁이 필요 없다 — `auth` 스키마와
--      `extensions` 스키마 usage grant는 플랫폼이 모든 프로젝트에 기본
--      제공한다. 즉 위 스텁은 "로컬 순수 Postgres 검증 전용"이며 앱 마이그레이션
--      에는 포함하지 않는다(supabase/migrations 어디에도 없음, 있어서도 안 됨).
--   3) 이 파일을 포함해 supabase/migrations/*.sql을 파일명 순서대로 그 DB에
--      적용한 뒤, 이 테스트 파일을 psql로 실행한다.
--   실행 결과는 이 QA 라운드에서 실제로 위 절차대로 실행해 얻었다(보고 참고).
-- =============================================================================

begin;

do $$ begin raise notice '=== 픽스처 구성 시작 ==='; end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000101', 'minji2@example.com'),
  ('00000000-0000-0000-0000-000000000102', 'hyunwoo2@example.com'),
  ('00000000-0000-0000-0000-000000000103', 'jian2@example.com');

insert into public.profiles (id, nickname) values
  ('00000000-0000-0000-0000-000000000101', '민지'),
  ('00000000-0000-0000-0000-000000000102', '현우'),
  ('00000000-0000-0000-0000-000000000103', '지안')
on conflict (id) do update set nickname = excluded.nickname;

-- group1: 민지(A)+현우(B). HIGH-1/HIGH-2 및 [D] off-모드 유출 테스트에 사용.
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.create_relationship_group('couple', '민지♥현우 group1 (보안 회귀)');

reset role;
select id as group1_id from public.relationship_groups
 where name = '민지♥현우 group1 (보안 회귀)' \gset
-- do $$ ... $$ 블록 안에서는 psql의 :'var' 치환이 적용되지 않으므로(별도
-- 렉서 컨텍스트), 커스텀 GUC에 담아 블록 내부에서 current_setting()으로
-- 읽는다. is_local=false로 세션 전체에 유지한다(그래야 이후 여러 DO 블록에서
-- 계속 읽을 수 있음 — set local request.jwt.claim.sub와는 별개 GUC라 서로
-- 간섭하지 않는다).
select set_config('qa.group1_id', :'group1_id', false);

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.create_relationship_invitation(current_setting('qa.group1_id')::uuid);

reset role;
select invite_code as group1_invite from public.relationship_invitations
 where group_id = current_setting('qa.group1_id')::uuid \gset

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
select public.accept_relationship_invitation(:'group1_invite');

-- group2: 지안(C) 혼자. [HIGH-2] 비멤버 대조군.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000103';
set local role authenticated;
select public.create_relationship_group('couple', '지안 혼자 group2 (보안 회귀)');

reset role;
select id as group2_id from public.relationship_groups
 where name = '지안 혼자 group2 (보안 회귀)' \gset

-- group3: 민지(A) 혼자, 현우(B)는 멤버 아님. [C] get_share_mode 그룹경계 우회 테스트용.
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.create_relationship_group('couple', '민지 혼자 group3 (보안 회귀)');

reset role;
select id as group3_id from public.relationship_groups
 where name = '민지 혼자 group3 (보안 회귀)' \gset
select set_config('qa.group3_id', :'group3_id', false);

-- group4: 민지(A)+현우(B), 항상 active로 유지. can_view_location이 "어떤
-- 그룹에서든 활성 공유면 통과"이므로, group1을 off로 꺼도 RLS 자체는 계속
-- 통과하게 만들어 [D] 테스트가 "RLS가 막아서 우연히 0건"이 아니라 진짜
-- get_peer_locations의 CASE 분기 문제를 재현하도록 한다.
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.create_relationship_group('couple', '민지♥현우 group4 (보안 회귀)');

reset role;
select id as group4_id from public.relationship_groups
 where name = '민지♥현우 group4 (보안 회귀)' \gset
select set_config('qa.group4_id', :'group4_id', false);

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.create_relationship_invitation(current_setting('qa.group4_id')::uuid);

reset role;
select invite_code as group4_invite from public.relationship_invitations
 where group_id = current_setting('qa.group4_id')::uuid \gset

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
select public.accept_relationship_invitation(:'group4_invite');

-- 초기 모드: group1=precise, group3=approx, group4=precise(항상 유지).
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.set_location_share_mode(current_setting('qa.group1_id')::uuid, 'precise');
select public.set_location_share_mode(current_setting('qa.group3_id')::uuid, 'approx');
select public.set_location_share_mode(current_setting('qa.group4_id')::uuid, 'precise');

do $$ begin raise notice '=== 픽스처 구성 끝 / 검증 시작 ==='; end $$;

-- =============================================================================
-- [HIGH-1] 위치 스푸핑 — notify_location_ping()
-- =============================================================================

-- 1) authenticated 롤은 notify_location_ping()을 직접 RPC로 호출할 수 없어야
--    한다(revoke execute ... from authenticated).
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
do $$
begin
  perform public.notify_location_ping(
    row(
      '00000000-0000-0000-0000-000000000101'::uuid,
      'SRID=4326;POINT(127.055512 37.512345)'::extensions.geography,
      null, null, null, null, now(), now()
    )::public.user_locations
  );
  raise notice 'FAIL: [HIGH-1 #1] authenticated가 notify_location_ping을 직접 호출했는데 예외 없이 성공함';
exception
  when others then
    if sqlerrm like '%permission denied for function notify_location_ping%' then
      raise notice 'PASS: [HIGH-1 #1] authenticated 직접 호출은 permission denied로 거부됨';
    else
      raise notice 'FAIL: [HIGH-1 #1] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

-- 2) 방어적 재검증: grant가 실수로 다시 열리는 상황을 시뮬레이션하기 위해
--    ACL 검사를 우회하는 세션 권한(superuser)으로 호출하되, p_location.user_id를
--    현재 세션의 auth.uid()(현우)와 다른 사람(민지) 명의로 지정한다.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
do $$
begin
  perform public.notify_location_ping(
    row(
      '00000000-0000-0000-0000-000000000101'::uuid,
      'SRID=4326;POINT(127.055512 37.512345)'::extensions.geography,
      null, null, null, null, now(), now()
    )::public.user_locations
  );
  raise notice 'FAIL: [HIGH-1 #2] user_id != auth.uid()인데 예외 없이 성공함(grant 우회 시 내부 검증 없음)';
exception
  when others then
    if sqlerrm like '%cannot broadcast a location ping on behalf of another user%' then
      raise notice 'PASS: [HIGH-1 #2] 내부 auth.uid() 재검증이 grant와 무관하게 스푸핑을 차단함';
    else
      raise notice 'FAIL: [HIGH-1 #2] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

-- 3) 회귀 확인: revoke가 정상 경로(upsert_location_ping)까지 막지는 않아야 한다.
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
do $$
begin
  perform public.upsert_location_ping('SRID=4326;POINT(127.055512 37.512345)'::extensions.geography);
  raise notice 'PASS: [HIGH-1 #3] revoke 이후에도 upsert_location_ping()을 통한 정상 위치 업데이트는 성공함';
exception
  when others then
    raise notice 'FAIL: [HIGH-1 #3] 정상 경로인 upsert_location_ping()이 실패함: %', sqlerrm;
end $$;

-- =============================================================================
-- [HIGH-2] get_peer_locations() 접근범위(그룹 경계) 우회
-- =============================================================================

-- 4) 그룹1 비멤버(지안)가 group1_id로 조회하면 예외 없이 빈 결과여야 한다.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000103';
set local role authenticated;
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  if v_count = 0 then
    raise notice 'PASS: [HIGH-2 #4] 그룹1 비멤버(지안)의 조회는 빈 결과(0건)임';
  else
    raise notice 'FAIL: [HIGH-2 #4] 그룹1 비멤버(지안)가 %건을 조회함(접근범위 우회)', v_count;
  end if;
end $$;

-- 5) 대조군: 실제 멤버(현우)가 조회하면 1건 보여야 한다.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  if v_count = 1 then
    raise notice 'PASS: [HIGH-2 #5] 실제 멤버(현우)의 조회는 1건임(민지가 보임)';
  else
    raise notice 'FAIL: [HIGH-2 #5] 실제 멤버 조회 결과가 %건임(기대: 1)', v_count;
  end if;
end $$;

-- 6) precise 모드에서는 반올림 없이 원본 경도가 그대로 보여야 한다.
do $$
declare
  v_lng numeric;
begin
  select round(extensions.st_x(location::extensions.geometry)::numeric, 6)
    into v_lng
    from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  if v_lng = 127.055512 then
    raise notice 'PASS: [HIGH-2 #6] precise 모드에서 원본 경도(127.055512)가 그대로 반환됨';
  else
    raise notice 'FAIL: [HIGH-2 #6] precise 모드 경도가 다름(actual=%, expected=127.055512)', v_lng;
  end if;
end $$;

-- approx로 전환.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.set_location_share_mode(:'group1_id'::uuid, 'approx');

-- 7) approx 모드에서는 accuracy_m이 null로 마스킹되어야 한다.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
do $$
declare
  v_accuracy numeric;
  v_found boolean;
begin
  select accuracy_m, true into v_accuracy, v_found
    from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  if v_found and v_accuracy is null then
    raise notice 'PASS: [HIGH-2 #7] approx 모드에서 accuracy_m이 null로 마스킹됨';
  else
    raise notice 'FAIL: [HIGH-2 #7] approx 모드 accuracy_m이 null이 아님(actual=%)', v_accuracy;
  end if;
end $$;

-- 8) approx 모드 좌표는 0.001도 격자 스냅과 정확히 일치해야 한다.
do $$
declare
  v_actual text;
  v_expected text;
begin
  select extensions.st_asewkt(location::extensions.geometry)
    into v_actual
    from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  select extensions.st_asewkt(
    extensions.st_setsrid(
      extensions.st_snaptogrid(
        'SRID=4326;POINT(127.055512 37.512345)'::extensions.geometry, 0.001, 0.001
      ),
      4326
    )
  ) into v_expected;
  if v_actual = v_expected then
    raise notice 'PASS: [HIGH-2 #8] approx 모드 좌표가 0.001도 격자 스냅과 정확히 일치함(%)', v_actual;
  else
    raise notice 'FAIL: [HIGH-2 #8] approx 좌표 불일치(actual=%, expected=%)', v_actual, v_expected;
  end if;
end $$;

-- =============================================================================
-- [C] get_share_mode() 그룹경계 우회 — 20260823100002의 [A] 수정 대상
-- (docs/review/location-sharing-security-rereview.md 섹션 3)
-- 현우는 민지와 group1/group4에서는 공유 중이지만 group3의 멤버는 아니다.
-- 수정 전에는 get_share_mode(민지, group3)가 can_view_location(민지, 현우)이
-- (group4가 active라서) true라는 이유만으로 group3의 실제 모드('approx')를
-- 그대로 반환해버렸다 — group3 멤버십과 무관하게. 수정 후에는 NULL이어야 한다.
-- =============================================================================
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
do $$
declare
  v_mode public.location_share_mode;
begin
  select public.get_share_mode('00000000-0000-0000-0000-000000000101'::uuid, current_setting('qa.group3_id')::uuid)
    into v_mode;
  if v_mode is null then
    raise notice 'PASS: [C #9] get_share_mode: group3 비멤버(현우)의 조회는 NULL임(그룹경계 지켜짐)';
  else
    raise notice 'FAIL: [C #9] get_share_mode: group3 비멤버(현우)가 모드 "%"를 알아냄(그룹경계 우회)', v_mode;
  end if;
end $$;

-- =============================================================================
-- [D] get_peer_locations()가 mode='off'일 때도 정밀 좌표를 반환하는 CASE 분기
-- 잔여 버그 — 20260823100002의 [B] 수정 대상
-- (docs/review/location-sharing-security-rereview.md 섹션 "2-확장")
-- 민지는 group1에서는 off로 껐지만 group4에서는 여전히 precise로 공유 중이라
-- RLS(can_view_location)는 통과한다. get_peer_locations(group1)이 "이
-- 그룹에서는 껐다"를 존중해 0건을 반환해야 하는데, 수정 전에는 CASE의 else
-- 분기가 정밀 좌표를 그대로 반환했다.
-- =============================================================================
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.set_location_share_mode(:'group1_id'::uuid, 'off');

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  if v_count = 0 then
    raise notice 'PASS: [D #10] group1을 off로 꺼두면 get_peer_locations(group1)이 0건을 반환함';
  else
    raise notice 'FAIL: [D #10] group1이 off인데도 %건이 반환됨(정밀 좌표 유출)', v_count;
  end if;
end $$;

-- =============================================================================
-- [F] 일시중지(paused_until)가 그룹별로 적용되는지 — 20260823100002의 [C] 수정
-- 대상, is_location_paused() 신설
-- 민지는 group1에서는 지금 일시중지 중(paused_until 미래)이고 group4에서는
-- 정상 공유 중(precise, active)이다. 현우는 두 그룹 모두의 멤버다.
-- can_view_location은 "어떤 그룹에서든 활성 공유 중이면" true이므로 RLS 자체는
-- group4 덕분에 통과한다 — get_peer_locations(group1)이 이 크로스-그룹
-- 통과를 오라클 삼아 group1에서 일시중지해둔 위치를 새어나가게 하면 안 된다.
-- =============================================================================
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.set_location_share_mode(:'group1_id'::uuid, 'precise', 60);

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  if v_count = 0 then
    raise notice 'PASS: [F #13] group1에서 일시중지 중(paused_until 미래)이면 get_peer_locations(group1)이 0건을 반환함';
  else
    raise notice 'FAIL: [F #13] group1에서 일시중지 중인데도 %건이 반환됨(일시중지가 그룹별로 적용되지 않음)', v_count;
  end if;
end $$;

-- 대조군: 일시중지가 끝난 뒤에는 다시 1건 보여야 한다. location_share_settings는
-- RPC로만 쓸 수 있으므로(직접 UPDATE는 grant 없음), pause_minutes 없이
-- set_location_share_mode를 재호출해 즉시 재개한다(paused_until -> null,
-- location_sharing.test.sql의 "즉시 재개" 케이스와 동일한 패턴).
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;
select public.set_location_share_mode(:'group1_id'::uuid, 'precise');

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000102';
set local role authenticated;
do $$
declare
  v_count int;
begin
  select count(*) into v_count from public.get_peer_locations(current_setting('qa.group1_id')::uuid);
  if v_count = 1 then
    raise notice 'PASS: [F #14] 일시중지가 끝난 뒤에는 get_peer_locations(group1)이 다시 1건을 반환함';
  else
    raise notice 'FAIL: [F #14] 일시중지 종료 후에도 %건임(기대: 1)', v_count;
  end if;
end $$;

-- =============================================================================
-- [E] upsert_location_ping()의 accuracy_m/battery_level 범위 검증 누락 →
-- 원시 Postgres 제약조건 위반 메시지 노출 (P0-4) — 20260823100003 수정 대상
-- =============================================================================
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000101';
set local role authenticated;

do $$
begin
  perform public.upsert_location_ping(
    p_location := 'SRID=4326;POINT(127.055512 37.512345)'::extensions.geography,
    p_accuracy_m := -5::numeric
  );
  raise notice 'FAIL: [E #11] accuracy_m=-5가 예외 없이 저장됨(범위 검증 자체가 없음)';
exception
  when others then
    if sqlerrm like '%does not exist%' then
      raise notice 'FAIL: [E #11] 테스트 자체가 함수 오버로드 해석에 실패함(타입 캐스팅 확인 필요): %', sqlerrm;
    elsif sqlerrm like '%violates check constraint%' then
      raise notice 'FAIL: [E #11] accuracy_m=-5가 원시 제약조건 위반 메시지를 그대로 노출함: %', sqlerrm;
    elsif sqlerrm like '%accuracy_m%' then
      raise notice 'PASS: [E #11] accuracy_m=-5가 애플리케이션 레벨의 깔끔한 예외로 거부됨: %', sqlerrm;
    else
      raise notice 'FAIL: [E #11] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

do $$
begin
  perform public.upsert_location_ping(
    p_location := 'SRID=4326;POINT(127.055512 37.512345)'::extensions.geography,
    p_battery_level := 150::smallint
  );
  raise notice 'FAIL: [E #12] battery_level=150이 예외 없이 저장됨(범위 검증 자체가 없음)';
exception
  when others then
    if sqlerrm like '%does not exist%' then
      raise notice 'FAIL: [E #12] 테스트 자체가 함수 오버로드 해석에 실패함(타입 캐스팅 확인 필요): %', sqlerrm;
    elsif sqlerrm like '%violates check constraint%' then
      raise notice 'FAIL: [E #12] battery_level=150이 원시 제약조건 위반 메시지를 그대로 노출함: %', sqlerrm;
    elsif sqlerrm like '%battery_level%' then
      raise notice 'PASS: [E #12] battery_level=150이 애플리케이션 레벨의 깔끔한 예외로 거부됨: %', sqlerrm;
    else
      raise notice 'FAIL: [E #12] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

do $$ begin raise notice '=== 검증 끝 ==='; end $$;

rollback;
