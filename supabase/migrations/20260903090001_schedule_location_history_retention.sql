-- =============================================================================
-- 곁에(Gyeote) v0.1: location_history 보존기간 정리 스케줄 등록 (pg_cron)
-- -----------------------------------------------------------------------------
-- 20260820090010_location_history.sql이 정의만 해둔
-- delete_expired_location_history(p_retention_days default 14)를 매일 1회
-- 자동 실행하도록 pg_cron 잡을 등록한다.
--
-- 왜 v0.1에 넣는가(용량이 아니라 컴플라이언스):
--   개인정보처리방침에 "위치 이력은 14일간만 보관"이 기재된다. 정리 스케줄이
--   없으면 location_history가 무한정 쌓여, 출시 첫날부터 그 방침이 허위 기재가
--   된다. 정리 함수 자체는 이미 있으므로 스케줄 한 줄만 추가하면 된다.
--
-- ***배포 시 필수 확인 (supabase/DEPLOYMENT.md 참고):***
--   pg_cron은 Supabase 호스티드에서 기본 비활성이다. 운영 프로젝트 대시보드의
--   Database > Extensions에서 `pg_cron`을 먼저 활성화해야 이 마이그레이션이
--   잡을 등록한다. 활성화돼 있지 않으면 이 마이그레이션은 (아래 가드에 의해)
--   에러 없이 통과하되 잡을 등록하지 못하고 NOTICE만 남긴다 — 그 경우
--   pg_cron을 켠 뒤 `supabase db push`를 다시 돌리거나(재실행 안전),
--   pg_cron을 쓸 수 없는 환경이면 예약 Edge Function 방식(2안)으로 전환한다.
--
-- 로컬 환경 주의:
--   `npx supabase start` 로컬 스택에는 pg_cron이 available extension으로
--   포함돼 있어 이 마이그레이션이 정상 동작한다. 반면 pg_cron 패키지가 없는
--   순수 Postgres(수동 설치 검증 환경 등)에서는 `pg_available_extensions`에
--   pg_cron이 없으므로, 아래 가드가 잡 등록을 건너뛰고 NOTICE만 남긴다
--   (마이그레이션 자체는 두 환경 모두에서 항상 적용 가능해야 하므로).
--
-- 재실행 안전성:
--   pg_cron 1.4+는 `cron.schedule(job_name, ...)`이 동일 job_name에 대해
--   upsert로 동작한다(중복 잡이 생기지 않음). Supabase는 1.4+를 제공한다.
-- =============================================================================

do $outer$
begin
  if not exists (
    select 1 from pg_available_extensions where name = 'pg_cron'
  ) then
    raise notice 'pg_cron is not available in this Postgres; skipping location_history retention schedule. Enable pg_cron (Supabase dashboard > Database > Extensions) and re-run `supabase db push`, or use the scheduled Edge Function fallback. See supabase/DEPLOYMENT.md.';
    return;
  end if;

  -- pg_cron이 available이면 확장을 활성화한다(이미 활성이면 무시).
  execute 'create extension if not exists pg_cron';

  -- 매일 03:17(UTC)에 보존기간(기본 14일) 경과 이력을 정리한다.
  -- 시각은 트래픽이 낮은 새벽대이면 충분하고, 정확한 분은 중요하지 않다.
  perform cron.schedule(
    'gyeote-location-history-retention',
    '17 3 * * *',
    'select public.delete_expired_location_history();'
  );

  raise notice 'Scheduled pg_cron job "gyeote-location-history-retention" (daily 03:17 UTC).';
end;
$outer$;
