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
--   pg_cron은 Supabase 대시보드 Database > Extensions에서 활성화하는 걸
--   권장 경로로 유지한다. 활성화 안 된 상태에서 이 마이그레이션을 먼저
--   돌리면 무슨 일이 나는지는 **미확인**이다 — 가능성 (가) pg_available_
--   extensions에 pg_cron이 없어 아래 가드가 조용히 NOTICE만 남기고 통과,
--   (나) available은 하지만 shared_preload_libraries에 없어서
--   `create extension`이 하드 에러로 실패(db push 자체가 실패로 드러남).
--   가드-true 경로(SQL 레벨 동작)는 로컬 재현으로 검증됐지만, 그 재현은
--   "대시보드 토글을 이미 켠 뒤"의 상태를 재현한 것이지 "토글 전" 상태를
--   재현한 게 아니다(아래 실측 노트 참고) — 검증 범위를 넘겨짚지 않는다.
--   (가)든 (나)든 배포 완료 여부는 `db push` 성공 여부가 아니라 배포 후
--   `cron.job`을 직접 조회해서 판단한다(DEPLOYMENT.md의 "잡 등록 확인" 게이트
--   — (가)는 그 쿼리에서 0행으로, (나)는 db push 자체의 실패로 드러난다).
--
-- 가드-true 경로 로컬 재현 검증됨 (2026-09-05, Tom) — 검증 범위 명확히:
--   로컬 PG14에 `postgresql-14-cron` 패키지를 설치하고
--   `shared_preload_libraries = 'pg_cron'`을 **먼저 설정한 뒤 재시작한** 상태
--   (=대시보드 토글을 이미 켠 상태에 해당)에서 이 마이그레이션을 실행해,
--   `create extension` 성공+재실행 멱등, `cron.schedule` 3-인자 등록+`cron.job`
--   실제 행, `postgres` 역할 실행 성공, grant 없는 역할의 `permission denied`
--   재현까지 SQL 레벨 동작을 전부 실제 실행으로 확인했다(상세: Tom scratchpad
--   `pg_cron_guard_true_verification_2026-09-05.md`). **이 재현이 검증하지
--   않은 것**: 대시보드 토글을 아직 안 켠 운영 프로젝트에 `db push`를 처음
--   돌렸을 때의 실제 동작(위 (가)/(나) 중 어느 쪽인지, 혹은 Supabase가 모든
--   프로젝트에 이미 preload해둬서 이 분기 자체가 없는지) — 이건 실제 운영
--   첫 배포 때 확인된다. 가드-false 경로(패키지 자체가 없어 NOTICE만 남기고
--   통과)는 패키지 설치 전 상태로 별도 확인됨.
--
-- 재실행 안전성:
--   pg_cron 1.4+는 `cron.schedule(job_name, ...)`이 동일 job_name에 대해
--   upsert로 동작한다(중복 잡이 생기지 않음). Supabase는 1.4+를 제공한다.
--
-- 실행 권한:
--   pg_cron 잡은 잡을 등록한 역할(Supabase에서 `supabase db push`는 `postgres`)
--   로 실행된다. delete_expired_location_history()의 원본 grant는 `service_role`
--   에만 있으므로(20260820090010), `postgres`에도 명시적으로 execute를 부여한다.
--   이게 없으면 db push가 다른 역할로 도는 경우 잡이 매일 밤 `permission denied`
--   로 조용히 실패하고 흔적은 `cron.job_run_details`에만 남는다("성공처럼 보이는
--   실패"). 싼 보험이라 명시해 둔다.
-- =============================================================================

grant execute on function public.delete_expired_location_history(int) to postgres;

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

  -- 매일 17:17 UTC = 02:17 KST(한국시간)에 보존기간(기본 14일) 경과 이력을
  -- 정리한다. 곁에는 한국 타겟 앱이므로 UTC 새벽이 아니라 KST 새벽 기준으로
  -- 잡는다(03:17 UTC는 12:17 KST로 점심 피크에 걸린다). 정확한 분은 중요하지 않다.
  perform cron.schedule(
    'gyeote-location-history-retention',
    '17 17 * * *',
    'select public.delete_expired_location_history();'
  );

  raise notice 'Scheduled pg_cron job "gyeote-location-history-retention" (daily 17:17 UTC / 02:17 KST).';
end;
$outer$;
