-- =============================================================================
-- 곁에(Gyeote) Phase 0: 관계 그룹(relationship_groups)
-- -----------------------------------------------------------------------------
-- 커플/가족/친구 관계를 표현하는 최상위 엔티티. 실제 멤버 목록은
-- relationship_members 테이블에서, 초대는 relationship_invitations 테이블에서
-- 관리한다.
--
-- 다음 라운드(위치 공유)에서는 이 그룹을 단위로 "관계가 있는 사람에게만
-- 위치를 노출"하는 RLS 정책을 위치 테이블에 적용할 예정이다.
-- =============================================================================

create type public.relationship_type as enum ('couple', 'family', 'friend');

create table public.relationship_groups (
  id uuid primary key default gen_random_uuid(),
  type public.relationship_type not null,
  name text check (name is null or char_length(name) between 1 and 50),
  -- 그룹을 만든 사용자. 탈퇴/삭제되어도 그룹 자체(다른 멤버들의 관계)는
  -- 유지되어야 하므로 on delete set null로 둔다.
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.relationship_groups is '커플/가족/친구 관계 그룹.';
comment on column public.relationship_groups.type is '관계 유형: couple(커플) / family(가족) / friend(친구)';

alter table public.relationship_groups enable row level security;

-- 멤버십/소유자 여부 판별 헬퍼 함수는 relationship_members 마이그레이션에서
-- 정의되며(순환 참조 방지를 위해 security definer로 RLS 우회), 아래 정책은
-- 그 함수들을 참조한다. 함수 생성 이후 정책을 추가하기 위해 이 파일 하단에서
-- relationship_members 마이그레이션 이후 정책을 건다 -> 실제로는
-- 20260820090004_relationship_members.sql 에서 정책까지 함께 정의한다.

create trigger trg_relationship_groups_set_updated_at
  before update on public.relationship_groups
  for each row
  execute function public.set_updated_at();

grant select on public.relationship_groups to authenticated;
