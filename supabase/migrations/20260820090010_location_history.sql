-- =============================================================================
-- 곁에(Gyeote) Phase 1: 위치 이력(location_history) — 보존기간 제한
-- -----------------------------------------------------------------------------
-- upsert_location_ping()이 호출될 때마다(공유가 켜져 있어 저장이 허용되는
-- 경우) 최신 스냅샷(user_locations)뿐 아니라 이력(location_history)에도 한
-- 행을 추가한다(경로/이동 이력 기능을 위한 원시 데이터).
--
-- 개인정보 최소 보관 원칙에 따라 무기한 보관하지 않고, 보존기간(기본 14일)이
-- 지난 행을 정리하는 delete_expired_location_history() 함수를 정의한다.
--
-- 주의: 이 함수는 "정의"만 하며 스케줄 등록은 이 마이그레이션 범위 밖이다.
-- pg_cron 확장(Supabase에서 지원) 또는 외부 스케줄러(예: Supabase의 Database
-- Webhooks/Edge Function + cron 트리거)로 주기적으로
-- `select public.delete_expired_location_history();` 를 호출하도록 별도
-- 설정이 필요하다.
-- =============================================================================

create table public.location_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  location extensions.geography(Point, 4326) not null,
  captured_at timestamptz not null,
  created_at timestamptz not null default now()
);

comment on table public.location_history is '위치 이동 이력(경로 재생 등에 사용). 보존기간 경과 후 정기 삭제 대상.';

create index idx_location_history_user_captured on public.location_history (user_id, captured_at desc);

alter table public.location_history enable row level security;

-- 본인 이력만 조회 가능. 관계 그룹 상대의 이력을 굳이 노출할 필요는 없으므로
-- (실시간 스냅샷과 달리 "과거 경로"는 더 민감할 수 있음) 본인으로 한정한다.
create policy "location_history_select_own"
  on public.location_history
  for select
  to authenticated
  using (user_id = auth.uid());

grant select on public.location_history to authenticated;

-- INSERT는 upsert_location_ping() RPC 내부에서만 수행하고, DELETE는 아래
-- 정리 함수를 통해서만 수행한다(클라이언트 직접 쓰기 금지).

-- -----------------------------------------------------------------------------
-- 보존기간 경과 이력 삭제 함수
-- -----------------------------------------------------------------------------
create or replace function public.delete_expired_location_history(p_retention_days int default 14)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted bigint;
begin
  if p_retention_days is null or p_retention_days <= 0 then
    raise exception 'p_retention_days must be a positive integer';
  end if;

  delete from public.location_history
   where captured_at < now() - make_interval(days => p_retention_days);

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.delete_expired_location_history(int) is
  '보존기간(기본 14일)이 지난 location_history 행을 삭제. pg_cron 또는 외부 스케줄러로 주기 실행 필요(이 마이그레이션은 함수 정의만 포함).';

revoke all on function public.delete_expired_location_history(int) from public;
-- 일반 사용자가 직접 호출할 이유가 없으므로 service_role(스케줄러/관리 작업)에만 부여.
grant execute on function public.delete_expired_location_history(int) to service_role;
