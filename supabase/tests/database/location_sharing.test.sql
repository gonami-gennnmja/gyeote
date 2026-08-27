-- =============================================================================
-- 곁에(Gyeote) 위치 공유 RPC/RLS 회귀 테스트 (pgTAP 미사용, 순수 SQL 단언)
-- -----------------------------------------------------------------------------
-- 관계(그룹/초대) 생성부터 위치 공유 모드 전환(off/precise/approx), 일시중지,
-- 초대 만료/이메일 검증까지 이어지는 기본 흐름을 다룬다. 원래 pgTAP으로
-- 작성됐던 초안이며, 초대 이메일 검증 누락 버그(20260823100001로 수정됨)를
-- 처음 발견한 테스트가 이 파일의 마지막 케이스다.
--
-- 이 환경에는 Docker/Supabase CLI/pgTAP 확장이 없어 pgTAP 문법(`plan()`,
-- `throws_matching()` 등)을 쓸 수 없다. location_sharing_security.test.sql/
-- invitation_email_check.test.sql과 동일한 패턴으로, 각 케이스를 DO 블록으로
-- 감싸 기대와 다르면 그 블록 안에서 RAISE NOTICE 'FAIL: ...'을 출력한다
-- (예외를 트랜잭션 밖으로 던지지 않으므로 뒤 케이스들도 계속 실행된다).
-- 성공한 케이스는 RAISE NOTICE 'PASS: ...'를 출력한다. 실행 후 출력에서
-- 'FAIL:'을 grep하면 실패한 항목만 바로 확인할 수 있다.
--
-- 로컬 실행 방법은 location_sharing_security.test.sql 헤더와 동일
-- (auth.uid() 스텁 + 전체 마이그레이션 적용 후 psql로 이 파일 실행).
-- `supabase test db`(Docker/Supabase CLI 있는 환경)로도 그대로 실행된다.
--
-- 실행 결과(2026-08-27, 20260823100001~100003 적용 상태 기준): 9개 케이스
-- 전부 실제 PASS. 각 케이스가 이름 그대로의 것을 검증하는지 하나씩 대조했다
-- — 주의할 점 하나: 이 파일의 픽스처는 민지/현우가 그룹을 "하나만" 공유하는
-- 상황이라, 6/7번(일시중지) 케이스는 "일시중지 중엔 안 보인다"는 단일 그룹
-- 시나리오만 검증한다. "다른 그룹에서는 활성 공유 중이라 RLS는 통과하는데
-- 이 그룹에서만 일시중지"인 크로스 그룹 케이스(Rena 재검토 지적, 20260823100002의
-- [C] 수정 대상)는 이 파일이 아니라 location_sharing_security.test.sql의
-- [F #13/#14]에서 별도로 다룬다 — 이름만 보면 같은 걸 검증하는 것처럼 보일 수
-- 있어 명시해둔다.
-- =============================================================================

begin;

do $$ begin raise notice '=== 픽스처 구성 시작 ==='; end $$;

-- ---------------------------------------------------------------------------
-- 픽스처: 세 사용자(민지/현우/지안)와 프로필. 민지+현우만 같은 커플 그룹의
-- 멤버로 만든다 — 지안은 테스트 8/9(초대 경계 상황)에서 "아직 멤버가 아닌
-- 사람"으로 남겨두기 위해 일부러 그룹에 넣지 않는다.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000201', 'minji4@example.com'),
  ('00000000-0000-0000-0000-000000000202', 'hyunwoo4@example.com'),
  ('00000000-0000-0000-0000-000000000203', 'jian4@example.com');

insert into public.profiles (id, nickname) values
  ('00000000-0000-0000-0000-000000000201', '민지'),
  ('00000000-0000-0000-0000-000000000202', '현우'),
  ('00000000-0000-0000-0000-000000000203', '지안')
on conflict (id) do update set nickname = excluded.nickname;

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000201';
set local role authenticated;
select public.create_relationship_group('couple', '민지♥현우 (기본 흐름)');

reset role;
select id as group_id from public.relationship_groups
 where name = '민지♥현우 (기본 흐름)' \gset
select set_config('qa.group_id', :'group_id', false);

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000201';
set local role authenticated;
select public.create_relationship_invitation(current_setting('qa.group_id')::uuid);

reset role;
select invite_code from public.relationship_invitations
 where group_id = current_setting('qa.group_id')::uuid \gset

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000202';
set local role authenticated;
select public.accept_relationship_invitation(:'invite_code');

do $$ begin raise notice '=== 픽스처 구성 끝 / 검증 시작 ==='; end $$;

-- ---------------------------------------------------------------------------
-- 1) 모든 그룹에서 공유 OFF인 상태로 upsert_location_ping 호출 -> 거부되어야 함
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000201';
set local role authenticated;
do $$
begin
  perform public.upsert_location_ping('SRID=4326;POINT(127.0 37.5)'::extensions.geography);
  raise notice 'FAIL: [1] mode=off 상태에서 upsert_location_ping이 예외 없이 성공함';
exception
  when others then
    if sqlerrm like '%location sharing is off for all groups%' then
      raise notice 'PASS: [1] mode=off 상태에서 upsert_location_ping은 거부됨';
    else
      raise notice 'FAIL: [1] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2) precise로 켠 뒤에는 저장이 성공해야 한다
-- ---------------------------------------------------------------------------
select public.set_location_share_mode(current_setting('qa.group_id')::uuid, 'precise');

do $$
begin
  perform public.upsert_location_ping('SRID=4326;POINT(127.0 37.5)'::extensions.geography);
  raise notice 'PASS: [2] mode=precise이면 upsert_location_ping이 성공함';
exception
  when others then
    raise notice 'FAIL: [2] mode=precise인데 upsert_location_ping이 실패함: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- 3) 상대(현우) 관점에서 get_peer_locations에 민지의 "정밀" 좌표가 그대로 보여야 함
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000202';
set local role authenticated;
do $$
declare
  v_lng numeric;
begin
  select round(extensions.st_x(location::extensions.geometry)::numeric, 4)
    into v_lng
    from public.get_peer_locations(current_setting('qa.group_id')::uuid);
  if v_lng = 127.0 then
    raise notice 'PASS: [3] precise 모드에서는 반올림 없이 원본 경도가 그대로 보임';
  else
    raise notice 'FAIL: [3] precise 모드 경도가 다름(actual=%, expected=127.0)', v_lng;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4) 민지가 approx로 전환하면 좌표가 ~100m 격자로 반올림되어 보여야 함
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000201';
set local role authenticated;
select public.set_location_share_mode(current_setting('qa.group_id')::uuid, 'approx');

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000202';
set local role authenticated;
do $$
declare
  v_accuracy_is_null boolean;
begin
  select accuracy_m is null into v_accuracy_is_null
    from public.get_peer_locations(current_setting('qa.group_id')::uuid);
  if v_accuracy_is_null then
    raise notice 'PASS: [4] approx 모드에서는 accuracy_m이 null로 마스킹됨';
  else
    raise notice 'FAIL: [4] approx 모드인데 accuracy_m이 null이 아님';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5) get_peer_locations가 approx 모드를 그대로 보고해야 한다
-- ---------------------------------------------------------------------------
do $$
declare
  v_mode public.location_share_mode;
begin
  select mode into v_mode from public.get_peer_locations(current_setting('qa.group_id')::uuid);
  if v_mode = 'approx' then
    raise notice 'PASS: [5] get_peer_locations가 mode=approx를 그대로 보고함';
  else
    raise notice 'FAIL: [5] mode가 approx가 아님(actual=%)', v_mode;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6) 민지가 60분 일시중지하면, 그 시간 동안 현우에게는 민지 위치가 전혀 보이면
--    안 된다 (단일 그룹 시나리오 — 크로스 그룹 케이스는 이 파일 범위 밖).
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000201';
set local role authenticated;
select public.set_location_share_mode(current_setting('qa.group_id')::uuid, 'approx', 60);

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000202';
set local role authenticated;
do $$
declare
  v_count int;
begin
  select count(*)::int into v_count from public.get_peer_locations(current_setting('qa.group_id')::uuid);
  if v_count = 0 then
    raise notice 'PASS: [6] 일시중지(paused_until 미래) 중에는 상대 위치가 전혀 보이지 않음';
  else
    raise notice 'FAIL: [6] 일시중지 중인데 %건이 보임', v_count;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 7) 즉시 재개(pause_minutes 없이 재호출)하면 다시 보여야 함
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000201';
set local role authenticated;
select public.set_location_share_mode(current_setting('qa.group_id')::uuid, 'approx');

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000202';
set local role authenticated;
do $$
declare
  v_count int;
begin
  select count(*)::int into v_count from public.get_peer_locations(current_setting('qa.group_id')::uuid);
  if v_count = 1 then
    raise notice 'PASS: [7] 즉시 재개 후에는 상대 위치가 다시 보임';
  else
    raise notice 'FAIL: [7] 재개 후에도 %건임(기대: 1)', v_count;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 8) 만료된 초대는 수락 실패해야 한다 (경계 상황)
--    지안(user 3, 아직 무소속)으로 테스트한다 — 현우(user 2)는 이미 이
--    그룹의 멤버라 accept_relationship_invitation()의 "이미 멤버" 체크에
--    걸려버려 만료 체크를 제대로 단독 검증할 수 없다.
-- ---------------------------------------------------------------------------
reset role;
insert into public.relationship_invitations (group_id, invited_by, expires_at)
values (current_setting('qa.group_id')::uuid, '00000000-0000-0000-0000-000000000201', now() - interval '1 minute')
returning invite_code as expired_code \gset
select set_config('qa.expired_code', :'expired_code', false);

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000203';
set local role authenticated;
do $$
begin
  perform public.accept_relationship_invitation(current_setting('qa.expired_code'));
  raise notice 'FAIL: [8] 만료된 초대가 예외 없이 수락됨';
exception
  when others then
    if sqlerrm like '%invitation has expired%' then
      raise notice 'PASS: [8] 만료된 초대는 수락 시 거부됨';
    else
      raise notice 'FAIL: [8] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

-- ---------------------------------------------------------------------------
-- 9) [20260823100001로 수정 완료] invited_email을 지정한 초대는 그 이메일
--    소유자가 아닌 사용자(지안)가 코드만 알아도 수락에 실패해야 한다.
--    (더 폭넓은 3케이스는 invitation_email_check.test.sql에서 별도로 다룬다
--    — 이 케이스는 원래 이 버그를 처음 발견한 자리라 그대로 남겨둔다.)
-- ---------------------------------------------------------------------------
reset role;
insert into public.relationship_invitations (group_id, invited_by, invited_email)
values (current_setting('qa.group_id')::uuid, '00000000-0000-0000-0000-000000000201', 'only-this-email@example.com')
returning invite_code as email_scoped_code \gset
select set_config('qa.email_scoped_code', :'email_scoped_code', false);

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000203';
set local role authenticated;
do $$
begin
  perform public.accept_relationship_invitation(current_setting('qa.email_scoped_code'));
  raise notice 'FAIL: [9] invited_email과 무관한 지안이 이메일 지정 초대를 예외 없이 수락함';
exception
  when others then
    if sqlerrm like '%invitation is scoped to a different email address%' then
      raise notice 'PASS: [9] invited_email(jian4@example.com 아님)과 무관한 지안은 이메일 지정 초대를 수락할 수 없음';
    else
      raise notice 'FAIL: [9] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

do $$ begin raise notice '=== 검증 끝 ==='; end $$;

rollback;
