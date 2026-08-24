-- =============================================================================
-- 곁에(Gyeote) 위치 공유 RPC/RLS pgTAP 테스트 (초안)
-- -----------------------------------------------------------------------------
-- 실행 방법: `supabase start`(로컬 Docker 스택)로 db를 띄운 뒤
--   supabase test db
-- 로 실행한다. pgTAP 확장이 필요하지만 Supabase CLI가 `supabase test db` 실행 시
-- 자동으로 설치/활성화하므로 config.toml에 별도 설정을 추가할 필요는 없다
-- (config.toml에는 애초에 그런 [db.pgtap] 섹션이 존재하지 않는다).
--
-- *** 중요: 이 파일은 이번 QA 라운드에서 실제로 실행/검증되지 못했다. ***
-- 이 샌드박스에는 Docker/Supabase CLI/DB 접속 권한이 없어 작성만 하고
-- 실행은 하지 못했다(보고 참고). 다음 라운드에 로컬 Supabase 스택이 있는
-- 환경에서 반드시 1회 실행해 문법/가정을 검증할 것.
--
-- auth.uid() 모킹: Supabase auth 확장 구현(auth.uid())은
--   current_setting('request.jwt.claim.sub', true)::uuid
-- 를 읽으므로, 아래에서는 `set local request.jwt.claim.sub` 로 로그인 사용자를
-- 흉내낸다.
-- =============================================================================

begin;
select plan(9);

-- ---------------------------------------------------------------------------
-- 픽스처: 세 사용자(민지/현우/지안)와 프로필. 민지+현우만 같은 커플 그룹의
-- 멤버로 만든다 — 지안은 테스트 7/8(초대 경계 상황)에서 "아직 멤버가 아닌
-- 사람"으로 남겨두기 위해 일부러 그룹에 넣지 않는다.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'minji@example.com'),
  ('00000000-0000-0000-0000-000000000002', 'hyunwoo@example.com'),
  ('00000000-0000-0000-0000-000000000003', 'jian@example.com');

-- 위 auth.users insert가 on_auth_user_created 트리거를 통해 profiles row를
-- 이미 자동 생성했으므로(ON CONFLICT DO NOTHING 방식), 여기서는 보기 좋은
-- 닉네임으로 갱신만 한다(단순 INSERT를 쓰면 PK 충돌로 실패한다).
insert into public.profiles (id, nickname) values
  ('00000000-0000-0000-0000-000000000001', '민지'),
  ('00000000-0000-0000-0000-000000000002', '현우'),
  ('00000000-0000-0000-0000-000000000003', '지안')
on conflict (id) do update set nickname = excluded.nickname;

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.create_relationship_group('couple', '민지♥현우');

reset role;
select id as group_id from public.relationship_groups limit 1 \gset

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.create_relationship_invitation(:'group_id'::uuid);

reset role;
select invite_code from public.relationship_invitations limit 1 \gset

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000002';
set local role authenticated;
select public.accept_relationship_invitation(:'invite_code');
reset role;

-- ---------------------------------------------------------------------------
-- 1) 모든 그룹에서 공유 OFF인 상태로 upsert_location_ping 호출 -> 거부되어야 함
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';
set local role authenticated;

select throws_matching(
  $$ select public.upsert_location_ping('SRID=4326;POINT(127.0 37.5)'::extensions.geography) $$,
  'location sharing is off for all groups.*',
  'mode=off 상태에서 upsert_location_ping은 거부되어야 한다'
);

-- ---------------------------------------------------------------------------
-- 2) precise로 켠 뒤에는 저장이 성공해야 한다
-- ---------------------------------------------------------------------------
select public.set_location_share_mode(:'group_id'::uuid, 'precise');

select lives_ok(
  $$ select public.upsert_location_ping('SRID=4326;POINT(127.0 37.5)'::extensions.geography) $$,
  'mode=precise이면 upsert_location_ping이 성공해야 한다'
);

-- ---------------------------------------------------------------------------
-- 3) 상대(현우) 관점에서 get_peer_locations에 민지의 "정밀" 좌표가 그대로 보여야 함
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000002';
set local role authenticated;

select results_eq(
  $$ select round(extensions.st_x(location::extensions.geometry)::numeric, 4)
     from public.get_peer_locations(:'group_id'::uuid) $$,
  $$ values (127.0::numeric) $$,
  'precise 모드에서는 반올림 없이 원본 경도가 그대로 보여야 한다'
);

-- ---------------------------------------------------------------------------
-- 4) 민지가 approx로 전환하면 좌표가 ~100m 격자로 반올림되어 보여야 함
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.set_location_share_mode(:'group_id'::uuid, 'approx');

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000002';
set local role authenticated;

select is(
  (select accuracy_m is null from public.get_peer_locations(:'group_id'::uuid)),
  true,
  'approx 모드에서는 accuracy_m이 null로 마스킹되어야 한다'
);

select is(
  (select mode from public.get_peer_locations(:'group_id'::uuid)),
  'approx',
  'get_peer_locations가 approx 모드를 그대로 보고해야 한다'
);

-- ---------------------------------------------------------------------------
-- 5) 민지가 60분 일시중지하면, 그 시간 동안 현우에게는 민지 위치가 전혀 보이면
--    안 된다 (RLS can_view_location 기준).
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.set_location_share_mode(:'group_id'::uuid, 'approx', 60);

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000002';
set local role authenticated;

select is(
  (select count(*)::int from public.get_peer_locations(:'group_id'::uuid)),
  0,
  '일시중지(paused_until 미래) 중에는 상대 위치가 전혀 보이지 않아야 한다'
);

-- ---------------------------------------------------------------------------
-- 6) 즉시 재개(pause_minutes 없이 재호출)하면 다시 보여야 함
-- ---------------------------------------------------------------------------
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select public.set_location_share_mode(:'group_id'::uuid, 'approx');

reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000002';
set local role authenticated;

select is(
  (select count(*)::int from public.get_peer_locations(:'group_id'::uuid)),
  1,
  '즉시 재개 후에는 상대 위치가 다시 보여야 한다'
);

-- ---------------------------------------------------------------------------
-- 7) 만료된 초대는 수락 실패해야 한다 (경계 상황)
--    지안(user 3, 아직 무소속)으로 테스트한다 — 현우(user 2)는 이미 이
--    그룹의 멤버라 accept_relationship_invitation()의 "이미 멤버"
--    체크에 걸려버려 만료 체크를 제대로 단독 검증할 수 없다.
-- ---------------------------------------------------------------------------
reset role;
insert into public.relationship_invitations (group_id, invited_by, expires_at)
values (:'group_id'::uuid, '00000000-0000-0000-0000-000000000001', now() - interval '1 minute')
returning invite_code as expired_code \gset

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000003';
set local role authenticated;

select throws_matching(
  $$ select public.accept_relationship_invitation(:'expired_code') $$,
  'invitation has expired',
  '만료된 초대는 수락 시 거부되어야 한다'
);

-- ---------------------------------------------------------------------------
-- 8) [수정 완료: 20260823100001_fix_invitation_email_check.sql]
--    invited_email을 지정한 초대는 그 이메일 소유자가 아닌 사용자(지안)가
--    코드만 알아도 수락에 실패해야 한다. 이전에는 accept_relationship_invitation()
--    에 이메일 일치 검증이 없어 통과하던 버그였으나, 위 마이그레이션으로
--    auth.users.email과 invited_email을 대소문자 무시 비교하도록 수정했다.
-- ---------------------------------------------------------------------------
reset role;
insert into public.relationship_invitations (group_id, invited_by, invited_email)
values (:'group_id'::uuid, '00000000-0000-0000-0000-000000000001', 'only-this-email@example.com')
returning invite_code as email_scoped_code \gset

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000003';
set local role authenticated;

select throws_matching(
  $$ select public.accept_relationship_invitation(:'email_scoped_code') $$,
  'invitation is scoped to a different email address',
  'invited_email(jian@example.com 아님)과 무관한 지안은 이메일 지정 초대를 수락할 수 없어야 한다'
);

select * from finish();
rollback;
