-- =============================================================================
-- 곁에(Gyeote) Phase 0: 관계 초대(relationship_invitations)
-- -----------------------------------------------------------------------------
-- 초대 코드/링크를 통해 그룹에 사용자를 초대한다.
-- status: pending(대기) -> accepted(수락) / revoked(취소) / expired(만료)
--
-- 초대받은 사람만 수락할 수 있어야 하지만, 수락 전에는 아직 그룹 멤버가
-- 아니므로 is_group_member() 기반 SELECT 정책만으로는 "초대 코드를 가진
-- 초대받은 사람"이 초대 내용을 미리 볼 수 없다. 이를 위해
-- get_invitation_preview(), accept_relationship_invitation() 을
-- SECURITY DEFINER RPC로 제공하며(20260820090006 참고), 테이블 자체에는
-- 최소한의 SELECT 정책만 둔다 (초대자 본인 / 이미 그룹 멤버 / 수락한 본인).
-- =============================================================================

create type public.invitation_status as enum ('pending', 'accepted', 'expired', 'revoked');

create table public.relationship_invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.relationship_groups (id) on delete cascade,
  -- 12자리 hex 코드 (예: 링크 https://app.gyeote.com/invite/<code> 형태로 배포)
  invite_code text not null unique default encode(extensions.gen_random_bytes(6), 'hex'),
  invited_by uuid not null references public.profiles (id) on delete cascade,
  invited_email text,
  accepted_by uuid references public.profiles (id) on delete set null,
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

comment on table public.relationship_invitations is '관계 그룹 초대 코드/링크 및 상태.';
comment on column public.relationship_invitations.invite_code is '초대 링크에 포함되는 고유 코드. 추측 방지를 위해 무작위 hex 사용.';
comment on column public.relationship_invitations.invited_email is '이메일로 초대한 경우 대상 이메일(선택). 코드/링크 공유 초대는 null 가능.';

create index idx_relationship_invitations_group_id on public.relationship_invitations (group_id);
create index idx_relationship_invitations_status on public.relationship_invitations (status);

alter table public.relationship_invitations enable row level security;

-- 그룹 멤버(초대자 포함) 또는 이 초대를 수락한 본인만 조회 가능.
-- 아직 미가입 상태에서 초대 코드로 내용을 미리 보는 경로는
-- get_invitation_preview() RPC(SECURITY DEFINER)를 통해서만 허용한다.
create policy "relationship_invitations_select_related"
  on public.relationship_invitations
  for select
  to authenticated
  using (
    public.is_group_member(group_id, auth.uid())
    or accepted_by = auth.uid()
  );

grant select on public.relationship_invitations to authenticated;

-- INSERT/UPDATE는 직접 허용하지 않는다. 초대 생성은
-- create_relationship_invitation(), 수락/취소는 accept_relationship_invitation() /
-- revoke_relationship_invitation() RPC를 통해서만 수행한다.
