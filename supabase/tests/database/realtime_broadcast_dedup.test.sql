-- =============================================================================
-- 곁에(Gyeote) Realtime 브로드캐스트 디듀프 회귀 테스트 (pgTAP 미사용, 순수
-- SQL 단언 — location_sharing_security.test.sql과 동일한 관례)
-- -----------------------------------------------------------------------------
-- 대상: supabase/migrations/20260915090002_realtime_broadcast_dedup.sql
-- (notify_location_ping의 그룹별 send 디듀프, realtime_broadcast_tuning /
-- location_broadcast_dedup_state). Rena 지적(2026-09-15) — 비용 분석에서
-- "큰 레버"로 꼽은 로직인데 영구 회귀 테스트가 없으면 나중에 조용히
-- 깨져도(예: 임계값 비교 부호가 뒤집히거나, 스킵 분기가 항상/전혀 안 타게
-- 되는 리팩터링 실수) 못 잡고, 그게 곧 Realtime 메시지 초과 비용으로
-- 돌아온다.
--
-- 최소 4케이스(요청된 것 그대로):
--   1) 초기 전송 — (user,group) 최초 핑은 항상 브로드캐스트된다.
--   2) 인접핑 스킵 — 직전 대비 거리<min_distance_m AND 경과<min_interval_seconds
--      면 브로드캐스트를 건너뛴다.
--   3) 원거리핑 전송 — 거리 조건이 불충족이면 즉시 다시 브로드캐스트한다.
--   4) 튜닝행 없을 때 항상 전송(폴백) — realtime_broadcast_tuning이 비어
--      있으면(임계값이 NULL) 비교가 unknown이 되어 스킵 분기를 못 타고
--      fail-open으로 항상 보낸다(위치가 조용히 안 보이는 것보다, 비용을
--      더 쓰더라도 계속 보이는 쪽이 안전하다는 판단).
--
-- 음성 대조군: 위 4개가 실제로 디듀프 메커니즘에 반응하는지(우연히 통과하는
-- 게 아닌지)를, 진짜 기본값을 적용하기 전에 극단적인 임계값으로 "고장난
-- 디듀프"를 흉내 내 반대 결과가 나오는 것부터 실제로 확인한다(아래 "메커니즘
-- 감도 확인" 섹션 — 임계값 0으로 낮추면 인접핑도 스킵 안 되는 것, 임계값을
-- 비현실적으로 올리면 원거리핑도 스킵되는 것을 직접 관찰). 그 다음에야
-- 임계값을 마이그레이션의 실제 기본값(15m/20초)으로 되돌리고 1)~4)를
-- 실행한다.
--
-- realtime.send()가 실제로 호출됐는지는 _stub_realtime.sql이 만드는
-- realtime.messages 행 수로 판별한다(로컬 전용 — 실제 Supabase에서는
-- realtime.messages가 이미 있어 이 스텁 자체가 자동으로 no-op).
--
-- 역할 전환 주의: realtime_broadcast_tuning/location_broadcast_dedup_state/
-- realtime.messages는 authenticated에 grant가 전혀 없다(서버 내부 전용,
-- 디듀프 마이그레이션의 의도적 설계). 그래서 이 파일은 "authenticated로
-- upsert_location_ping 호출" ↔ "postgres로 내부 상태 조작/검증"을 계속
-- reset role / set local role authenticated로 오간다.
--
-- 로컬 실행: location_sharing_security.test.sql과 동일한 auth/extensions
-- 스텁이 선행 적용돼 있어야 한다(그 파일 헤더 참고). 이 파일 자체는
-- \ir로 _stub_realtime.sql을 불러 realtime 스텁까지 스스로 준비한다.
-- =============================================================================

begin;

\ir _stub_realtime.sql

do $$ begin raise notice '=== 픽스처 구성 시작 ==='; end $$;

insert into auth.users (id, email) values
  ('44440000-0000-4000-a000-000000000001', 'dedup-qa-a@example.com'),
  ('55550000-0000-4000-a000-000000000002', 'dedup-qa-b@example.com');
insert into public.profiles (id, nickname) values
  ('44440000-0000-4000-a000-000000000001', 'dedup-A'),
  ('55550000-0000-4000-a000-000000000002', 'dedup-B')
on conflict (id) do nothing;

set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.create_relationship_group('couple', 'dedup qa group');

reset role;
select id as gid from public.relationship_groups where name = 'dedup qa group' \gset
-- do $$ ... $$ 블록 안에서는 psql의 :'var' 치환이 적용되지 않으므로(별도
-- 렉서 컨텍스트, location_sharing_security.test.sql과 동일한 이유) 커스텀
-- GUC에 담아 블록 내부에서 current_setting()으로 읽는다.
select set_config('qa.dedup_gid', :'gid', false);

set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.create_relationship_invitation(:'gid'::uuid);

reset role;
select invite_code as inv from public.relationship_invitations where group_id = :'gid'::uuid \gset

set local request.jwt.claim.sub to '55550000-0000-4000-a000-000000000002';
set local role authenticated;
select public.accept_relationship_invitation(:'inv');

reset role;
set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.set_location_share_mode(:'gid'::uuid, 'precise');

reset role;
do $$ begin raise notice '=== 픽스처 구성 끝 / 검증 시작 ==='; end $$;

-- =============================================================================
-- 메커니즘 감도 확인 (음성 대조군)
-- =============================================================================

-- 감도 A: 임계값을 0으로 낮추면(사실상 디듀프 없음) 아주 가까운 두 핑도
-- 스킵 없이 둘 다 전송돼야 한다 — 아래 2)가 실제로 거리/시간 임계값에
-- 반응한다는 증거. (postgres로 튜닝값 조작)
update public.realtime_broadcast_tuning set min_distance_m = 0, min_interval_seconds = 0;

set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.upsert_location_ping('SRID=4326;POINT(127.100000 37.500000)'::extensions.geography);
select public.upsert_location_ping('SRID=4326;POINT(127.100001 37.500001)'::extensions.geography); -- 1m 미만 이동

reset role;
do $$
declare
  v_count int;
begin
  select count(*) into v_count from realtime.messages;
  if v_count = 2 then
    raise notice 'PASS: [디듀프 감도A] 임계값을 0으로 낮추면 인접핑도 스킵 없이 둘 다 전송됨(2건) — 2)가 실제로 임계값에 반응한다는 증거';
  else
    raise notice 'FAIL: [디듀프 감도A] 임계값 0인데도 전송이 %건임(기대 2) — 테스트 환경 자체를 먼저 의심할 것', v_count;
  end if;
end $$;

-- 감도 B: 임계값을 비현실적으로 크게 올리면(사실상 항상 스킵) 수백km
-- 이동한 두 번째 핑도 스킵돼야 한다 — 아래 3)이 실제로 거리 계산에
-- 반응한다는 증거.
truncate realtime.messages;
-- 감도A가 남긴 (user,group) 직전-위치 상태를 지운다 — 안 지우면 이 섹션의
-- "첫 핑"이 감도A의 마지막 위치를 직전 상태로 물려받아 버려서(같은 좌표라
-- 거리 0) 첫 핑부터 스킵돼 아래 기대(1건)가 깨진다.
delete from public.location_broadcast_dedup_state where user_id = '44440000-0000-4000-a000-000000000001';
update public.realtime_broadcast_tuning set min_distance_m = 100000000, min_interval_seconds = 100000000;

set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.upsert_location_ping('SRID=4326;POINT(127.100000 37.500000)'::extensions.geography);
select public.upsert_location_ping('SRID=4326;POINT(128.500000 38.500000)'::extensions.geography); -- 수백 km 이동

reset role;
do $$
declare
  v_count int;
begin
  select count(*) into v_count from realtime.messages;
  if v_count = 1 then
    raise notice 'PASS: [디듀프 감도B] 임계값을 비현실적으로 올리면 수백km 이동도 스킵됨(전송은 최초 1건뿐) — 3)이 실제로 거리 계산에 반응한다는 증거';
  else
    raise notice 'FAIL: [디듀프 감도B] 임계값을 극단적으로 올렸는데 전송이 %건임(기대 1) — 테스트 환경 자체를 먼저 의심할 것', v_count;
  end if;
end $$;

-- 임계값을 실제 기본값(마이그레이션이 넣은 값)으로 되돌리고, 픽스처를
-- 정리한 뒤에야 본 단언을 시작한다.
update public.realtime_broadcast_tuning set min_distance_m = 15, min_interval_seconds = 20;
truncate realtime.messages;
delete from public.location_broadcast_dedup_state where user_id = '44440000-0000-4000-a000-000000000001';

-- =============================================================================
-- 본 단언 (기본 임계값: min_distance_m=15, min_interval_seconds=20 — 마이그레이션 기본값)
-- =============================================================================

-- 1) 초기 전송 — 이 (user,group)의 최초 핑.
set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.upsert_location_ping('SRID=4326;POINT(127.100000 37.500000)'::extensions.geography);

reset role;
do $$
declare
  v_sent int;
begin
  select count(*) into v_sent from realtime.messages;
  if v_sent = 1 then
    raise notice 'PASS: [디듀프 #1] 초기 전송 — 최초 핑은 항상 브로드캐스트됨';
  else
    raise notice 'FAIL: [디듀프 #1] 초기 전송인데 realtime.messages가 %건임(기대 1)', v_sent;
  end if;
end $$;

-- 2) 인접핑 스킵 — 직전 대비 수 m 이동(<15m). 같은 트랜잭션 안이라
--    now()가 고정돼 경과도 항상 0초(<20초) — 거리 조건이 유일한 변수.
set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.upsert_location_ping('SRID=4326;POINT(127.100005 37.500005)'::extensions.geography);

reset role;
do $$
declare
  v_sent int;
  v_skip bigint;
begin
  select count(*) into v_sent from realtime.messages;
  select skip_count into v_skip from public.location_broadcast_dedup_state
   where user_id = '44440000-0000-4000-a000-000000000001'
     and group_id = current_setting('qa.dedup_gid')::uuid;
  if v_sent = 1 and v_skip = 1 then
    raise notice 'PASS: [디듀프 #2] 인접핑 스킵 — 거리<15m AND 경과<20초라 브로드캐스트 안 함(누적 전송 여전히 1건, skip_count=1)';
  else
    raise notice 'FAIL: [디듀프 #2] 인접핑인데 전송=%건 skip_count=%(기대 전송1/skip1)', v_sent, v_skip;
  end if;
end $$;

-- 3) 원거리핑 전송 — 수백 km 이동, 거리 조건 불충족으로 즉시 다시
--    브로드캐스트돼야 한다.
set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.upsert_location_ping('SRID=4326;POINT(128.500000 38.500000)'::extensions.geography);

reset role;
do $$
declare
  v_sent int;
begin
  select count(*) into v_sent from realtime.messages;
  if v_sent = 2 then
    raise notice 'PASS: [디듀프 #3] 원거리핑 전송 — 충분히 멀리 이동하면 즉시 다시 브로드캐스트됨(누적 2건)';
  else
    raise notice 'FAIL: [디듀프 #3] 원거리 이동인데 전송이 %건임(기대 2)', v_sent;
  end if;
end $$;

-- 4) 튜닝행 없을 때 항상 전송(폴백) — 싱글턴 행을 지우면 임계값 비교가
--    NULL이 되어(NULL과의 비교는 항상 unknown → PL/pgSQL IF는 false로
--    취급) 스킵 분기를 못 타고 항상 보낸다. #3의 좌표에서 다시 아주 조금만
--    이동한 핑으로 "튜닝행이 있었다면 스킵됐을" 상황을 만든다.
delete from public.realtime_broadcast_tuning;

set local request.jwt.claim.sub to '44440000-0000-4000-a000-000000000001';
set local role authenticated;
select public.upsert_location_ping('SRID=4326;POINT(128.500001 38.500001)'::extensions.geography); -- 1m 미만 이동

reset role;
do $$
declare
  v_sent int;
begin
  select count(*) into v_sent from realtime.messages;
  if v_sent = 3 then
    raise notice 'PASS: [디듀프 #4] 튜닝행 없음 폴백 — realtime_broadcast_tuning이 비어 있으면(임계값 NULL) 인접핑도 스킵하지 않고 항상 전송함(누적 3건, fail-open)';
  else
    raise notice 'FAIL: [디듀프 #4] 튜닝행이 없는데도 전송이 %건임(기대 3 — 폴백이 조용히 억제 쪽(fail-closed)으로 도는 회귀 위험)', v_sent;
  end if;
end $$;

-- 다음 실행을 위해 싱글턴 행 복구(이 파일은 rollback되므로 엄밀히는
-- 불필요하지만, 마이그레이션이 넣어둔 상태와 같은 모습으로 명시적으로
-- 남긴다).
insert into public.realtime_broadcast_tuning (id) values (true) on conflict (id) do nothing;

do $$ begin raise notice '=== 검증 끝 ==='; end $$;

rollback;
