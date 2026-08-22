-- =============================================================================
-- 곁에(Gyeote) Phase 0: 관계 멤버십(relationship_members)
-- -----------------------------------------------------------------------------
-- 그룹-사용자 매핑 테이블. role은 owner(그룹 생성/초대/추방 권한) 또는
-- member(일반 멤버)이다.
--
-- RLS 순환 참조 방지:
--   relationship_groups / relationship_members 는 서로의 정책에서 상대
--   테이블을 조회해야 하므로, is_group_member() / is_group_owner() 를
--   security definer 함수로 만들어 함수 내부에서는 RLS를 우회하도록 한다.
--   (Supabase 표준 패턴: 함수 소유자가 postgres 이므로 BYPASSRLS 적용됨)
--
-- 쓰기(INSERT/UPDATE/DELETE) 정책은 이 테이블에는 두지 않는다. 그룹 생성,
-- 초대 수락, 탈퇴, 추방은 모두 20260820090006_relationship_functions.sql 의
-- SECURITY DEFINER RPC 함수를 통해서만 수행되도록 강제한다. 이렇게 하면
-- "멤버가 아닌 사람이 임의로 멤버 행을 조작"하는 경로를 원천 차단할 수 있다.
-- =============================================================================

create table public.relationship_members (
  group_id uuid not null references public.relationship_groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

comment on table public.relationship_members is '관계 그룹과 사용자의 멤버십 매핑.';
comment on column public.relationship_members.role is 'owner: 그룹 관리(초대/추방/삭제) 권한 보유, member: 일반 멤버';

create index idx_relationship_members_user_id on public.relationship_members (user_id);

alter table public.relationship_members enable row level security;

-- -----------------------------------------------------------------------------
-- 헬퍼 함수 (security definer: 자기 자신을 참조하는 RLS 순환을 방지)
-- -----------------------------------------------------------------------------
create or replace function public.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.relationship_members m
    where m.group_id = p_group_id
      and m.user_id = p_user_id
  );
$$;

create or replace function public.is_group_owner(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.relationship_members m
    where m.group_id = p_group_id
      and m.user_id = p_user_id
      and m.role = 'owner'
  );
$$;

revoke all on function public.is_group_member(uuid, uuid) from public;
revoke all on function public.is_group_owner(uuid, uuid) from public;
grant execute on function public.is_group_member(uuid, uuid) to authenticated;
grant execute on function public.is_group_owner(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- relationship_members RLS: 본인이 속한 그룹의 멤버 목록만 조회 가능
-- -----------------------------------------------------------------------------
create policy "relationship_members_select_own_group"
  on public.relationship_members
  for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

grant select on public.relationship_members to authenticated;

-- -----------------------------------------------------------------------------
-- relationship_groups RLS (헬퍼 함수 정의 이후로 지연)
--   - SELECT: 본인이 속한 그룹만 조회 가능
--   - UPDATE: owner만 (예: 그룹 이름 변경)
--   - DELETE: owner만. relationship_members / relationship_invitations는
--             group_id FK가 on delete cascade 이므로 그룹 삭제 시
--             하위 데이터(멤버십, 초대)가 자동으로 함께 정리된다.
--   - INSERT: 직접 INSERT는 막고, create_relationship_group() RPC를 통해서만
--             (그룹 생성 + owner 멤버십 등록을 하나의 트랜잭션으로 보장)
-- -----------------------------------------------------------------------------
create policy "relationship_groups_select_member"
  on public.relationship_groups
  for select
  to authenticated
  using (public.is_group_member(id, auth.uid()));

create policy "relationship_groups_update_owner"
  on public.relationship_groups
  for update
  to authenticated
  using (public.is_group_owner(id, auth.uid()))
  with check (public.is_group_owner(id, auth.uid()));

create policy "relationship_groups_delete_owner"
  on public.relationship_groups
  for delete
  to authenticated
  using (public.is_group_owner(id, auth.uid()));

grant update (name), delete on public.relationship_groups to authenticated;
