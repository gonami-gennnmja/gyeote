-- =============================================================================
-- 곁에(Gyeote) v0.2: location_history(captured_at) 단독 인덱스
-- -----------------------------------------------------------------------------
-- delete_expired_location_history()의 정리 DELETE는 다음처럼 user_id 조건 없이
-- captured_at만으로 전체 테이블을 스캔한다(20260820090010):
--   delete from location_history where captured_at < now() - make_interval(...)
-- 기존 idx_location_history_user_captured(user_id, captured_at desc)는 선행
-- 컬럼이 user_id라 이 쿼리에는 쓰이지 못하고 시퀀셜 스캔으로 떨어진다.
-- pg_cron이 이 DELETE를 매일 실행하므로(20260903090001), 테이블이 커질수록
-- 매일 전체 스캔 비용이 누적된다. captured_at 단독 인덱스를 추가해 인덱스
-- 스캔으로 바꾼다.
--
-- CONCURRENTLY를 쓰지 않는 이유: v0.2 초입 시점 테이블 크기가 아직 작아 짧은
-- 쓰기 잠금 비용이 무시할 만하고, 이 프로젝트의 다른 모든 마이그레이션과
-- 동일하게 트랜잭션 내에서 적용 가능해야 하기 때문이다(CREATE INDEX
-- CONCURRENTLY는 트랜잭션 블록 안에서 실행할 수 없어 db push/SQL Editor 번들
-- 방식과 충돌한다). 테이블이 커진 뒤 재인덱스가 필요해지면 그때는 별도로
-- CONCURRENTLY로 운영에서 직접 실행한다(마이그레이션 파일로 넣지 않는다).
-- =============================================================================

create index if not exists idx_location_history_captured_at
  on public.location_history (captured_at);

comment on index public.idx_location_history_captured_at is
  'delete_expired_location_history()의 보존기간 정리 DELETE(user_id 조건 없음)가 시퀀셜 스캔 대신 이 인덱스를 쓰게 한다.';
