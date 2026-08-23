-- =============================================================================
-- 곁에(Gyeote) 초대 이메일 검증 누락 버그 수정
-- -----------------------------------------------------------------------------
-- QA(Tom)가 supabase/tests/database/location_sharing.test.sql 테스트 8번에서
-- 발견한 이슈: relationship_invitations.invited_email을 지정한(이메일 지정)
-- 초대라도, accept_relationship_invitation()이 초대 코드만 확인할 뿐 수락하는
-- 사용자의 이메일이 invited_email과 일치하는지 검증하지 않아 코드만 알면
-- 누구나 수락할 수 있었다.
--
-- "이메일 지정 초대는 그 이메일 계정으로 로그인한 사용자만 수락 가능"이
-- invited_email 필드를 둔 목적이므로, invited_email이 설정된 초대는
-- auth.users.email과 대소문자 무시 비교로 일치할 때만 수락을 허용하도록
-- 수정한다. 코드/링크만으로 공유하는 초대(invited_email is null)는 기존과
-- 동일하게 동작한다.
-- =============================================================================

create or replace function public.accept_relationship_invitation(p_invite_code text)
returns public.relationship_members
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitation public.relationship_invitations;
  v_member public.relationship_members;
  v_user_email text;
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

  if v_invitation.invited_email is not null then
    select email into v_user_email from auth.users where id = auth.uid();

    if v_user_email is null or lower(v_user_email) <> lower(v_invitation.invited_email) then
      raise exception 'invitation is scoped to a different email address';
    end if;
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
