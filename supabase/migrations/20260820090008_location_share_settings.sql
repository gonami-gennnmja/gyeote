-- =============================================================================
-- 곁에(Gyeote) Phase 1: 위치 공유 설정(location_share_settings)
-- -----------------------------------------------------------------------------
-- 사용자가 "어느 관계 그룹에게 위치를 얼마나 정밀하게 공유할지"를 그룹 단위로
-- 설정한다.
--   mode = 'off'     : 해당 그룹에는 위치를 전혀 공유하지 않음
--   mode = 'precise'  : 정밀 좌표 그대로 공유
--   mode = 'approx'   : 약 100m 격자로 반올림한 좌표만 공유 (get_peer_locations
--                       RPC에서 서버가 강제로 하향 처리)
--   paused_until      : "N분만 임시로 끄기" 등 일시중지 만료 시각. null이면
--                       일시중지 아님. 값이 있고 now() 이전으로 지나면 다시
--                       mode에 따라 공유 재개된 것으로 취급한다.
--
-- 쓰기는 set_location_share_mode() RPC(20260820090011)를 통해서만 허용한다
-- (관계 컨벤션과 동일: 그룹 멤버십 검증 + "모든 그룹에서 OFF일 때 저장된 위치
-- 삭제" 같은 부수 효과를 원자적으로 처리해야 하므로).
-- =============================================================================

create type public.location_share_mode as enum ('off', 'precise', 'approx');

create table public.location_share_settings (
  user_id uuid not null references public.profiles (id) on delete cascade,
  relationship_group_id uuid not null references public.relationship_groups (id) on delete cascade,
  mode public.location_share_mode not null default 'off',
  paused_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, relationship_group_id)
);

comment on table public.location_share_settings is '사용자별/관계 그룹별 위치 공유 모드 설정.';
comment on column public.location_share_settings.mode is 'off: 공유 안함 / precise: 정밀 좌표 / approx: 약 100m 격자로 반올림';
comment on column public.location_share_settings.paused_until is '임시 일시중지 만료 시각(null이면 일시중지 아님). 지난 값은 만료로 취급.';

create index idx_location_share_settings_group on public.location_share_settings (relationship_group_id);

alter table public.location_share_settings enable row level security;

-- 본인 설정만 조회 가능 (다른 사람이 나의 공유 on/off 여부를 직접 조회할 수는
-- 없다 — "공유를 껐다"는 사실 자체도 최소한으로 노출한다는 원칙).
create policy "location_share_settings_select_own"
  on public.location_share_settings
  for select
  to authenticated
  using (user_id = auth.uid());

grant select on public.location_share_settings to authenticated;

create trigger trg_location_share_settings_set_updated_at
  before update on public.location_share_settings
  for each row
  execute function public.set_updated_at();

-- INSERT/UPDATE/DELETE는 직접 허용하지 않는다. set_location_share_mode() RPC
-- (SECURITY DEFINER)를 통해서만 그룹 멤버십 검증과 함께 쓰기가 이뤄진다.
