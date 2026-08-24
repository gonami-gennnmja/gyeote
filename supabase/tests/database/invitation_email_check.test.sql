-- =============================================================================
-- 곁에(Gyeote) 초대 이메일 검증 회귀 테스트 (pgTAP 미사용, 순수 SQL 단언)
-- -----------------------------------------------------------------------------
-- 대상: supabase/migrations/20260823100001_fix_invitation_email_check.sql
-- (accept_relationship_invitation()에 invited_email 검증을 추가한 수정).
--
-- 이전에 이 수정의 유일한 검증 근거는 location_sharing.test.sql의 pgTAP
-- 테스트 8번이었는데, 그 파일은 pgTAP 문법 그대로 한 번도 실제 DB에 실행된
-- 적이 없었다(Rena 재검토에서 지적됨). 100002/100003과 같은 기준을 100001에도
-- 적용해, invited_email 검증에 해당하는 케이스만 순수 SQL로 옮겨 실제로 돌린다.
--
-- 실행 방법은 location_sharing_security.test.sql 헤더의 로컬 실행 방법과 동일
-- (auth.uid() 스텁 + 전체 마이그레이션 적용 후 psql로 이 파일 실행).
-- =============================================================================

begin;

do $$ begin raise notice '=== 픽스처 구성 시작 ==='; end $$;

-- 초대자(민지)와 세 명의 수락 시도자: 잘못된 이메일(공격자)/정확히 일치하는
-- 이메일/대소문자만 다른 이메일.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000111', 'minji3@example.com'),
  ('00000000-0000-0000-0000-000000000112', 'attacker@example.com'),
  ('00000000-0000-0000-0000-000000000113', 'target2@example.com'),
  ('00000000-0000-0000-0000-000000000114', 'target3@example.com');

insert into public.profiles (id, nickname) values
  ('00000000-0000-0000-0000-000000000111', '민지'),
  ('00000000-0000-0000-0000-000000000112', '공격자'),
  ('00000000-0000-0000-0000-000000000113', '정확한사람'),
  ('00000000-0000-0000-0000-000000000114', '대소문자다른사람')
on conflict (id) do update set nickname = excluded.nickname;

set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000111';
set local role authenticated;
select public.create_relationship_group('couple', '민지 초대이메일 검증 (보안 회귀)');

reset role;
select id as group_id from public.relationship_groups
 where name = '민지 초대이메일 검증 (보안 회귀)' \gset
select set_config('qa.group_id', :'group_id', false);

-- invite1: onlyme@example.com 전용 초대 (공격자가 코드만 알고 수락 시도).
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000111';
set local role authenticated;
select public.create_relationship_invitation(:'group_id'::uuid, 'onlyme@example.com');

reset role;
select invite_code as invite1_code from public.relationship_invitations
 where group_id = :'group_id'::uuid and invited_email = 'onlyme@example.com' \gset
select set_config('qa.invite1_code', :'invite1_code', false);

-- invite2: target2@example.com 전용 초대 (그 이메일 계정 본인이 수락).
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000111';
set local role authenticated;
select public.create_relationship_invitation(:'group_id'::uuid, 'target2@example.com');

reset role;
select invite_code as invite2_code from public.relationship_invitations
 where group_id = :'group_id'::uuid and invited_email = 'target2@example.com' \gset
select set_config('qa.invite2_code', :'invite2_code', false);

-- invite3: Target3@Example.com(대문자 섞음) 전용 초대. 실제 계정 이메일은
-- target3@example.com(소문자)이라, 대소문자 무시 비교가 되는지 확인한다.
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000111';
set local role authenticated;
select public.create_relationship_invitation(:'group_id'::uuid, 'Target3@Example.com');

reset role;
select invite_code as invite3_code from public.relationship_invitations
 where group_id = :'group_id'::uuid and invited_email = 'Target3@Example.com' \gset
select set_config('qa.invite3_code', :'invite3_code', false);

do $$ begin raise notice '=== 픽스처 구성 끝 / 검증 시작 ==='; end $$;

-- 1) 공격자(attacker@example.com)는 onlyme@example.com 전용 초대를 코드만
--    알아도 수락할 수 없어야 한다.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000112';
set local role authenticated;
do $$
begin
  perform public.accept_relationship_invitation(current_setting('qa.invite1_code'));
  raise notice 'FAIL: [초대이메일 #1] onlyme@example.com 전용 초대를 attacker@example.com이 예외 없이 수락함';
exception
  when others then
    if sqlerrm like '%invitation is scoped to a different email address%' then
      raise notice 'PASS: [초대이메일 #1] 이메일이 다른 사용자의 수락은 거부됨';
    else
      raise notice 'FAIL: [초대이메일 #1] 예상과 다른 에러: %', sqlerrm;
    end if;
end $$;

-- 2) target2@example.com 본인은 정상적으로 수락할 수 있어야 한다.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000113';
set local role authenticated;
do $$
declare
  v_member public.relationship_members;
begin
  select * into v_member from public.accept_relationship_invitation(current_setting('qa.invite2_code'));
  if v_member.user_id = '00000000-0000-0000-0000-000000000113'::uuid
     and v_member.group_id = current_setting('qa.group_id')::uuid then
    raise notice 'PASS: [초대이메일 #2] invited_email 본인(target2@example.com)은 정상 수락됨';
  else
    raise notice 'FAIL: [초대이메일 #2] 수락은 됐지만 결과 행이 예상과 다름(user_id=%, group_id=%)', v_member.user_id, v_member.group_id;
  end if;
exception
  when others then
    raise notice 'FAIL: [초대이메일 #2] 본인 수락인데 예외 발생: %', sqlerrm;
end $$;

-- 3) 대소문자가 달라도(Target3@Example.com 초대 vs target3@example.com 계정)
--    같은 이메일로 인식되어 수락되어야 한다.
reset role;
set local request.jwt.claim.sub to '00000000-0000-0000-0000-000000000114';
set local role authenticated;
do $$
declare
  v_member public.relationship_members;
begin
  select * into v_member from public.accept_relationship_invitation(current_setting('qa.invite3_code'));
  if v_member.user_id = '00000000-0000-0000-0000-000000000114'::uuid
     and v_member.group_id = current_setting('qa.group_id')::uuid then
    raise notice 'PASS: [초대이메일 #3] 대소문자가 달라도(target3@example.com) 같은 이메일로 인식되어 수락됨';
  else
    raise notice 'FAIL: [초대이메일 #3] 수락은 됐지만 결과 행이 예상과 다름(user_id=%, group_id=%)', v_member.user_id, v_member.group_id;
  end if;
exception
  when others then
    raise notice 'FAIL: [초대이메일 #3] 대소문자만 다른데 예외 발생: %', sqlerrm;
end $$;

do $$ begin raise notice '=== 검증 끝 ==='; end $$;

rollback;
