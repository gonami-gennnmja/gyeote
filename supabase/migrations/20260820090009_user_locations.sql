-- =============================================================================
-- 곁에(Gyeote) Phase 1: 실시간 위치(user_locations) — 이 라운드의 보안 핵심
-- -----------------------------------------------------------------------------
-- 사용자별 "최신 위치 1행"만 유지한다(UPSERT 대상). 과거 이력은
-- location_history(20260820090010)에 별도로 쌓는다.
--
-- RLS SELECT 정책 (두 개의 permissive 정책이 OR로 결합됨):
--   1) 본인 행은 항상 조회 가능.
--   2) 타인의 행은 "같은 relationship_group에 속해 있고, AND 그 그룹에 대해
--      상대방의 location_share_settings.mode <> 'off' 이고, AND
--      (paused_until is null or paused_until <= now())" 인 경우에만 조회 가능.
--      즉 paused_until은 "이 시각까지 일시중지(비공개)"를 의미하며, 그 시각이
--      지나면 다시 mode에 따른 공유 상태로 복귀한다(pause_minutes 파라미터 및
--      "일시 정지" 의미와 일치시키기 위한 것 — 반대로 두면 "일시정지" 버튼을
--      누른 직후에도 상대가 계속 보이는 오류가 발생함, 로컬 검증 중 확인).
--      이 판별은 can_view_location() security definer 헬퍼로 캡슐화한다
--      (relationship_members / location_share_settings에 대한 RLS 순환/교차
--      참조를 피하기 위해 is_group_member()와 동일한 패턴을 사용).
--
-- 알려진 한계(설계상 트레이드오프, README에도 기재):
--   user_locations는 row에 group_id를 갖지 않는 "사용자당 1행" 구조이므로,
--   RLS는 "둘이 공유하는 그룹이 하나라도 활성 공유 중이면 조회 가능"으로
--   판단한다. 두 사용자가 여러 관계 그룹에 동시에 속해 있고 그 중 한 그룹만
--   OFF로 꺼둔 경우, 다른 그룹이 활성 상태라면 여전히 조회 가능하다(정상
--   동작 — 다른 그룹 맥락에서는 공유 중이므로). 동일한 두 사용자가 여러 그룹에
--   동시에 속하는 경우는 드물지만, 이 한계를 인지하고 있어야 한다.
-- =============================================================================

create table public.user_locations (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  location extensions.geography(Point, 4326) not null,
  accuracy_m numeric check (accuracy_m is null or accuracy_m >= 0),
  battery_level smallint check (battery_level is null or battery_level between 0 and 100),
  is_charging boolean,
  movement_state text check (movement_state is null or movement_state in ('stationary', 'walking', 'moving')),
  captured_at timestamptz not null,
  received_at timestamptz not null default now()
);

comment on table public.user_locations is '사용자별 최신 위치 스냅샷(1인 1행, UPSERT 대상). 쓰기는 upsert_location_ping() RPC로만 허용.';
comment on column public.user_locations.captured_at is '단말에서 위치를 측정한 시각(오프라인 큐 플러시 시 역행 방지 기준).';
comment on column public.user_locations.received_at is '서버가 이 값을 반영한 시각.';

create index idx_user_locations_location on public.user_locations using gist (location);

alter table public.user_locations enable row level security;

-- -----------------------------------------------------------------------------
-- 헬퍼 함수: p_viewer_id가 p_owner_id의 위치를 볼 수 있는지 판별
-- (security definer: relationship_members / location_share_settings에 대한
--  RLS를 우회하여 순환 참조 없이 판별. is_group_member()와 동일한 컨벤션)
-- -----------------------------------------------------------------------------
create or replace function public.can_view_location(p_owner_id uuid, p_viewer_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.relationship_members owner_m
    join public.relationship_members viewer_m
      on viewer_m.group_id = owner_m.group_id
     and viewer_m.user_id = p_viewer_id
    join public.location_share_settings s
      on s.relationship_group_id = owner_m.group_id
     and s.user_id = p_owner_id
    where owner_m.user_id = p_owner_id
      and s.mode <> 'off'
      and (s.paused_until is null or s.paused_until <= now())
  );
$$;

comment on function public.can_view_location(uuid, uuid) is
  'p_viewer_id가 p_owner_id와 같은 관계 그룹에 속해 있고, 그 그룹에 대한 owner의 공유 모드가 off가 아니며 일시중지 상태가 아닌 경우 true.';

revoke all on function public.can_view_location(uuid, uuid) from public;
grant execute on function public.can_view_location(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- RLS 정책
-- -----------------------------------------------------------------------------
create policy "user_locations_select_self"
  on public.user_locations
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "user_locations_select_shared"
  on public.user_locations
  for select
  to authenticated
  using (public.can_view_location(user_id, auth.uid()));

grant select on public.user_locations to authenticated;

-- INSERT/UPDATE/DELETE는 직접 허용하지 않는다. upsert_location_ping() /
-- set_location_share_mode() RPC(둘 다 SECURITY DEFINER, 20260820090011)를
-- 통해서만 쓰기가 이뤄진다.
