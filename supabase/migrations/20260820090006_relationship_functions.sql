-- =============================================================================
-- 곁에(Gyeote) Phase 0: 관계 그룹 관련 RPC 함수
-- -----------------------------------------------------------------------------
-- relationship_groups / relationship_members / relationship_invitations 테이블은
-- 여러 행에 걸친 정합성(그룹 생성 시 owner 멤버십 동시 생성, 초대 수락 시
-- 멤버십 추가 + 초대 상태 갱신을 원자적으로 처리 등)이 필요하므로, 클라이언트의
-- 직접 INSERT/UPDATE 대신 아래 SECURITY DEFINER 함수를 통해서만 쓰기를 허용한다.
--
-- 각 함수는 내부에서 auth.uid() 기반으로 권한을 다시 검증하므로, RLS를
-- 우회하는 security definer 함수라 하더라도 임의 사용자가 남의 그룹을
-- 조작할 수 없다.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) 관계 그룹 생성: 그룹 row + 생성자 owner 멤버십을 한 트랜잭션으로 생성
-- -----------------------------------------------------------------------------
create or replace function public.create_relationship_group(
  p_type public.relationship_type,
  p_name text default null
)
returns public.relationship_groups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.relationship_groups;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  insert into public.relationship_groups (type, name, created_by)
  values (p_type, p_name, auth.uid())
  returning * into v_group;

  insert into public.relationship_members (group_id, user_id, role)
  values (v_group.id, auth.uid(), 'owner');

  return v_group;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2) 초대 생성: 그룹 멤버만 초대를 만들 수 있음
-- -----------------------------------------------------------------------------
create or replace function public.create_relationship_invitation(
  p_group_id uuid,
  p_invited_email text default null
)
returns public.relationship_invitations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitation public.relationship_invitations;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not public.is_group_member(p_group_id, auth.uid()) then
    raise exception 'only members of the group can create invitations';
  end if;

  insert into public.relationship_invitations (group_id, invited_by, invited_email)
  values (p_group_id, auth.uid(), p_invited_email)
  returning * into v_invitation;

  return v_invitation;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3) 초대 미리보기: 아직 멤버가 아닌 초대받은 사람이 코드로 그룹 정보를 확인
--    (민감하지 않은 최소 정보만 반환)
-- -----------------------------------------------------------------------------
create or replace function public.get_invitation_preview(p_invite_code text)
returns table (
  group_id uuid,
  group_type public.relationship_type,
  group_name text,
  invited_by_nickname text,
  status public.invitation_status,
  expires_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select
    g.id,
    g.type,
    g.name,
    p.nickname,
    i.status,
    i.expires_at
  from public.relationship_invitations i
  join public.relationship_groups g on g.id = i.group_id
  join public.profiles p on p.id = i.invited_by
  where i.invite_code = p_invite_code;
$$;

-- -----------------------------------------------------------------------------
-- 4) 초대 수락: 멤버십 추가 + 초대 상태 갱신을 원자적으로 처리
-- -----------------------------------------------------------------------------
create or replace function public.accept_relationship_invitation(p_invite_code text)
returns public.relationship_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitation public.relationship_invitations;
  v_member public.relationship_members;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select *
    into v_invitation
    from public.relationship_invitations
   where invite_code = p_invite_code
   for update;

  if not found then
    raise exception 'invitation not found';
  end if;

  if v_invitation.status <> 'pending' then
    raise exception 'invitation is not pending (status: %)', v_invitation.status;
  end if;

  if v_invitation.expires_at < now() then
    update public.relationship_invitations
       set status = 'expired'
     where id = v_invitation.id;
    raise exception 'invitation has expired';
  end if;

  if public.is_group_member(v_invitation.group_id, auth.uid()) then
    raise exception 'already a member of this group';
  end if;

  insert into public.relationship_members (group_id, user_id, role)
  values (v_invitation.group_id, auth.uid(), 'member')
  returning * into v_member;

  update public.relationship_invitations
     set status = 'accepted',
         accepted_by = auth.uid(),
         accepted_at = now()
   where id = v_invitation.id;

  return v_member;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5) 초대 취소: 초대자 본인 또는 그룹 owner만 가능
-- -----------------------------------------------------------------------------
create or replace function public.revoke_relationship_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitation public.relationship_invitations;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select * into v_invitation
    from public.relationship_invitations
   where id = p_invitation_id;

  if not found then
    raise exception 'invitation not found';
  end if;

  if v_invitation.invited_by <> auth.uid()
     and not public.is_group_owner(v_invitation.group_id, auth.uid()) then
    raise exception 'not authorized to revoke this invitation';
  end if;

  if v_invitation.status <> 'pending' then
    raise exception 'only pending invitations can be revoked';
  end if;

  update public.relationship_invitations
     set status = 'revoked'
   where id = p_invitation_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6) 그룹 탈퇴: 본인 멤버십 삭제. 마지막 멤버였다면 그룹 자체도 정리
--    (하위 데이터 정리 요구사항: 빈 그룹을 남기지 않음)
-- -----------------------------------------------------------------------------
create or replace function public.leave_relationship_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  delete from public.relationship_members
   where group_id = p_group_id
     and user_id = auth.uid();

  if not found then
    raise exception 'not a member of this group';
  end if;

  -- 남은 멤버가 없으면 그룹 자체를 삭제한다.
  -- (relationship_invitations는 group_id FK on delete cascade로 함께 정리됨)
  delete from public.relationship_groups g
   where g.id = p_group_id
     and not exists (
       select 1 from public.relationship_members m where m.group_id = g.id
     );
end;
$$;

-- -----------------------------------------------------------------------------
-- 7) 멤버 추방: owner만 가능. 본인 추방은 leave_relationship_group() 사용.
-- -----------------------------------------------------------------------------
create or replace function public.remove_relationship_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'use leave_relationship_group() to remove yourself';
  end if;

  if not public.is_group_owner(p_group_id, auth.uid()) then
    raise exception 'only the group owner can remove members';
  end if;

  delete from public.relationship_members
   where group_id = p_group_id
     and user_id = p_user_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 권한 부여: authenticated 역할만 실행 가능, anon/public은 차단
-- -----------------------------------------------------------------------------
revoke all on function public.create_relationship_group(public.relationship_type, text) from public;
revoke all on function public.create_relationship_invitation(uuid, text) from public;
revoke all on function public.get_invitation_preview(text) from public;
revoke all on function public.accept_relationship_invitation(text) from public;
revoke all on function public.revoke_relationship_invitation(uuid) from public;
revoke all on function public.leave_relationship_group(uuid) from public;
revoke all on function public.remove_relationship_member(uuid, uuid) from public;

grant execute on function public.create_relationship_group(public.relationship_type, text) to authenticated;
grant execute on function public.create_relationship_invitation(uuid, text) to authenticated;
grant execute on function public.get_invitation_preview(text) to authenticated;
grant execute on function public.accept_relationship_invitation(text) to authenticated;
grant execute on function public.revoke_relationship_invitation(uuid) to authenticated;
grant execute on function public.leave_relationship_group(uuid) to authenticated;
grant execute on function public.remove_relationship_member(uuid, uuid) to authenticated;
