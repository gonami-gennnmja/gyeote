-- =============================================================================
-- 곁에(Gyeote) v0.1 초기 스키마 번들  (경로 B: 대시보드 SQL Editor 수동 적용)
-- -----------------------------------------------------------------------------
-- 이 파일은 supabase/bundle/build.sh 가 supabase/migrations/*.sql 16개를
-- 파일명 순서로 결합해 자동 생성한 것이다. 직접 편집하지 말 것 — 원본은
-- supabase/migrations/ 이고, 바뀌면 build.sh 를 다시 돌린다.
--
-- 적용 방법:
--   1) (선행) 대시보드 Database > Extensions 에서 pg_cron 을 활성화한다.
--      - pgcrypto / postgis 는 이 번들의 마이그레이션(20260820090001,
--        20260820090007)이 직접 create extension 한다. Supabase 호스티드는
--        두 확장이 available 기본 제공이라 보통 그대로 성공한다.
--      - pg_cron 은 20260903090001 이 create extension if not exists pg_cron 을
--        시도한다. 대시보드에서 먼저 켜두지 않으면 그 구문에서 하드 에러가
--        날 수 있고, 이 파일 전체가 하나의 트랜잭션(begin/commit)이므로
--        16개 전부 롤백된다.
--   2) 대시보드 SQL Editor > New query > 이 파일 전체 붙여넣기 > Run.
--   3) 에러 없이 끝나면 완료. 아래 원장(schema_migrations) 기록까지 한
--      트랜잭션으로 반영된다.
--
-- 실패했을 때:
--   - 실패 지점 바로 위의  "-- >>> FILE k/16: <파일명>"  주석이 어느 원본
--     마이그레이션에서 멈췄는지 알려준다.
--   - 전체가 롤백됐으므로 DB는 원상태다. 원인을 그 원본 파일에서 고치고
--     build.sh 를 다시 돌린 뒤 재실행한다.
--   - pg_cron 때문에 20260903090001 에서만 막힌다면: 그 FILE 구간과 맨 끝
--     원장 insert 의 해당 줄만 빼고 실행 → 대시보드에서 pg_cron 활성화 →
--     그 구간 + 원장 줄을 따로 실행.
--
-- ⚠️ 맨 끝의 schema_migrations INSERT 블록을 지우지 말 것.
--   SQL Editor 로 수동 적용하면 원장이 비어 있어서, 나중에 CLI 로
--   'supabase db push' 하면 16개를 처음부터 다시 적용하려 든다(사고).
--   이 블록이 16개 버전을 원장에 기록해 두므로 수동 적용 후에도 CLI 운영이
--   정상이 된다.
--
-- 생성 시각 기준 대상 마이그레이션: 16개 (파일명 순).
-- =============================================================================

begin;

-- >>> FILE 1/16: 20260820090001_extensions.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- 곁에(Gyeote) Phase 0: 확장(Extension) 활성화
-- -----------------------------------------------------------------------------
-- pgcrypto: 초대 코드 생성을 위한 gen_random_bytes() 등에 사용.
--   (gen_random_uuid()는 PostgreSQL 13+ 코어 내장 함수이므로 별도 확장 불필요)
--
-- 주의: 이번 Phase 0에서는 위치 공유 기능(PostGIS 등)을 다루지 않으므로
-- postgis 확장은 다음 라운드(위치 공유 스키마)에서 활성화한다.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- <<< END 20260820090001_extensions.sql <<<


-- >>> FILE 2/16: 20260820090002_profiles.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- 곁에(Gyeote) Phase 0: profiles 테이블 (Auth 확장)
-- -----------------------------------------------------------------------------
-- Supabase Auth(auth.users)는 이메일/비밀번호, OAuth 등 인증 정보만 관리하므로
-- 앱에서 필요한 공개 프로필 정보(닉네임, 아바타)는 별도 테이블(public.profiles)에
-- 1:1로 저장한다. auth.users row가 생성되면 트리거로 profiles row를 자동 생성한다.
--
-- RLS 정책 요약:
--   - SELECT: 로그인한 모든 사용자가 모든 프로필의 최소 정보(닉네임/아바타)를 조회 가능
--             (email 등 민감 정보는 auth.users에만 존재하며 여기 노출하지 않음)
--   - INSERT: 본인 행만 생성 가능 (일반적으로는 트리거가 대신 생성함)
--   - UPDATE: 본인 행만 수정 가능
--   - DELETE: 별도 정책 없음 (auth.users 삭제 시 on delete cascade로 자동 정리)
-- =============================================================================

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null check (char_length(nickname) between 1 and 30),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is '앱 공개 프로필 정보. auth.users와 1:1 매핑.';
comment on column public.profiles.nickname is '사용자 표시 닉네임 (최소 공개 정보)';
comment on column public.profiles.avatar_url is '프로필 이미지 URL (Storage 공개/서명 URL)';

alter table public.profiles enable row level security;

-- 로그인한 모든 사용자는 모든 프로필의 최소 정보를 조회할 수 있다.
create policy "profiles_select_authenticated"
  on public.profiles
  for select
  to authenticated
  using (true);

-- 본인 프로필만 생성 가능 (트리거를 통한 자동 생성이 기본 경로).
create policy "profiles_insert_own"
  on public.profiles
  for insert
  to authenticated
  with check (auth.uid() = id);

-- 본인 프로필만 수정 가능.
create policy "profiles_update_own"
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant insert (id, nickname, avatar_url), update (nickname, avatar_url) on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- updated_at 자동 갱신 트리거 함수 (다른 테이블에서도 재사용)
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- auth.users insert 시 profiles row 자동 생성 트리거
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nickname, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'nickname',
      split_part(new.email, '@', 1),
      '사용자'
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- <<< END 20260820090002_profiles.sql <<<


-- >>> FILE 3/16: 20260820090003_relationship_groups.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260820090003_relationship_groups.sql <<<


-- >>> FILE 4/16: 20260820090004_relationship_members.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260820090004_relationship_members.sql <<<


-- >>> FILE 5/16: 20260820090005_relationship_invitations.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260820090005_relationship_invitations.sql <<<


-- >>> FILE 6/16: 20260820090006_relationship_functions.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260820090006_relationship_functions.sql <<<


-- >>> FILE 7/16: 20260820090007_location_extensions.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- 곁에(Gyeote) Phase 1: 위치 공유 — PostGIS 확장 활성화
-- -----------------------------------------------------------------------------
-- 위치 좌표(geography(Point,4326))와 근접 계산(ST_DWithin 등), 좌표 격자 반올림
-- (ST_SnapToGrid)에 필요한 PostGIS 확장을 활성화한다. pgcrypto와 동일하게
-- extensions 스키마에 설치한다(Supabase 표준 관례).
-- =============================================================================

create extension if not exists postgis with schema extensions;

-- <<< END 20260820090007_location_extensions.sql <<<


-- >>> FILE 8/16: 20260820090008_location_share_settings.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260820090008_location_share_settings.sql <<<


-- >>> FILE 9/16: 20260820090009_user_locations.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260820090009_user_locations.sql <<<


-- >>> FILE 10/16: 20260820090010_location_history.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260820090010_location_history.sql <<<


-- >>> FILE 11/16: 20260820090011_location_functions.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- 곁에(Gyeote) Phase 1: 위치 공유 RPC 함수
-- -----------------------------------------------------------------------------
-- user_locations / location_share_settings / location_history 테이블에는 직접
-- INSERT/UPDATE/DELETE grant를 주지 않는다(20260820090008~090010 참고).
-- 아래 SECURITY DEFINER 함수를 통해서만 쓰기를 허용하며, 각 함수는 내부에서
-- auth.uid() 기반으로 권한/불변식을 재검증한다.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0) 헬퍼: 특정 관계 그룹에 대한 상대의 공유 모드 조회 (근사 좌표 반올림 판단용)
--    - location_share_settings는 본인 행만 SELECT 가능하므로, get_peer_locations
--      (invoker 권한으로 실행되어 RLS가 그대로 적용됨)가 상대방의 모드를 알기
--      위해 이 security definer 헬퍼를 거친다.
--    - 정보 최소 노출: 호출자가 이미 그 위치를 볼 권한이 있는 경우
--      (can_view_location) 또는 본인 자신의 모드를 물어보는 경우에만 값을
--      반환한다. 그 외에는 null을 반환해 "임의 사용자의 공유 여부"를 알아내는
--      경로로 악용되지 않도록 한다.
-- -----------------------------------------------------------------------------
create or replace function public.get_share_mode(p_owner_id uuid, p_relationship_group_id uuid)
returns public.location_share_mode
language sql
security definer
stable
set search_path = public
as $$
  select s.mode
  from public.location_share_settings s
  where s.user_id = p_owner_id
    and s.relationship_group_id = p_relationship_group_id
    and (
      p_owner_id = auth.uid()
      or public.can_view_location(p_owner_id, auth.uid())
    );
$$;

revoke all on function public.get_share_mode(uuid, uuid) from public;
grant execute on function public.get_share_mode(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 1) 위치 핑 업서트: 본인의 user_locations 최신 행을 갱신 + location_history에
--    적재. "공유가 완전히 OFF"인 상태에서는 위치 저장 자체를 거부한다(프라이버시
--    원칙 — 서버가 불필요하게 위치를 보관하지 않음).
-- -----------------------------------------------------------------------------
create or replace function public.upsert_location_ping(
  p_location extensions.geography,
  p_accuracy_m numeric default null,
  p_battery_level smallint default null,
  p_is_charging boolean default null,
  p_movement_state text default null,
  p_captured_at timestamptz default now()
)
returns public.user_locations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.user_locations;
  v_result public.user_locations;
  v_has_active_share boolean;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  if extensions.geometrytype(p_location::extensions.geometry) <> 'POINT' then
    raise exception 'location must be a Point geography';
  end if;

  if p_movement_state is not null and p_movement_state not in ('stationary', 'walking', 'moving') then
    raise exception 'invalid movement_state: %', p_movement_state;
  end if;

  if p_captured_at is null then
    raise exception 'captured_at is required';
  end if;

  -- 프라이버시 게이트: mode가 off가 아닌 그룹이 하나도 없으면(=모든 그룹에서
  -- 완전히 꺼둔 경우) 위치 저장 자체를 거부한다. 일시중지(paused_until)는
  -- "누구에게 보일지"만 제어하는 가시성 문제이며 저장 허용 여부와는 무관하게
  -- 둔다 — 그래야 일시중지가 끝나는 즉시(새 GPS fix를 기다릴 필요 없이) 마지막
  -- 위치가 다시 노출될 수 있다. 완전 삭제는 mode가 실제로 'off'로 바뀔 때만
  -- set_location_share_mode()에서 수행한다.
  select exists (
    select 1
    from public.location_share_settings s
    where s.user_id = v_uid
      and s.mode <> 'off'
  ) into v_has_active_share;

  if not v_has_active_share then
    raise exception 'location sharing is off for all groups; enable sharing before sending a location ping';
  end if;

  select * into v_existing from public.user_locations where user_id = v_uid for update;

  -- 오프라인 큐 플러시 등으로 과거 시각의 좌표가 뒤늦게 도착한 경우, 이미 저장된
  -- 더 최신 captured_at 값보다 과거라면 역행을 방지하기 위해 무시하고 기존
  -- 최신 행을 그대로 반환한다.
  if found and v_existing.captured_at > p_captured_at then
    return v_existing;
  end if;

  insert into public.user_locations (
    user_id, location, accuracy_m, battery_level, is_charging, movement_state, captured_at, received_at
  ) values (
    v_uid, p_location, p_accuracy_m, p_battery_level, p_is_charging, p_movement_state, p_captured_at, now()
  )
  on conflict (user_id) do update set
    location = excluded.location,
    accuracy_m = excluded.accuracy_m,
    battery_level = excluded.battery_level,
    is_charging = excluded.is_charging,
    movement_state = excluded.movement_state,
    captured_at = excluded.captured_at,
    received_at = excluded.received_at
  returning * into v_result;

  insert into public.location_history (user_id, location, captured_at)
  values (v_uid, p_location, p_captured_at);

  -- Realtime 브로드캐스트 (실제 Supabase 환경에서만 존재하는 realtime 스키마가
  -- 있을 때만 동작; 20260820090012 참고).
  perform public.notify_location_ping(v_result);

  return v_result;
end;
$$;

revoke all on function public.upsert_location_ping(
  extensions.geography, numeric, smallint, boolean, text, timestamptz
) from public;
grant execute on function public.upsert_location_ping(
  extensions.geography, numeric, smallint, boolean, text, timestamptz
) to authenticated;

-- -----------------------------------------------------------------------------
-- 2) 그룹별 공유 모드 설정
--    OFF로 전환하더라도 다른 그룹에는 여전히 공유 중일 수 있으므로 무조건
--    user_locations 행을 지우지 않는다. "모든 그룹에서 OFF(또는 비활성 상태)"
--    인 경우에만 저장된 최신 위치를 즉시 삭제한다.
-- -----------------------------------------------------------------------------
create or replace function public.set_location_share_mode(
  p_relationship_group_id uuid,
  p_mode text,
  p_pause_minutes int default null
)
returns public.location_share_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_mode public.location_share_mode;
  v_paused_until timestamptz;
  v_result public.location_share_settings;
  v_any_active boolean;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  if not public.is_group_member(p_relationship_group_id, v_uid) then
    raise exception 'not a member of this group';
  end if;

  begin
    v_mode := p_mode::public.location_share_mode;
  exception when invalid_text_representation then
    raise exception 'invalid mode: % (expected off|precise|approx)', p_mode;
  end;

  if p_pause_minutes is not null then
    if p_pause_minutes <= 0 then
      raise exception 'pause_minutes must be a positive integer';
    end if;
    v_paused_until := now() + make_interval(mins => p_pause_minutes);
  else
    v_paused_until := null;
  end if;

  insert into public.location_share_settings (user_id, relationship_group_id, mode, paused_until)
  values (v_uid, p_relationship_group_id, v_mode, v_paused_until)
  on conflict (user_id, relationship_group_id) do update set
    mode = excluded.mode,
    paused_until = excluded.paused_until,
    updated_at = now()
  returning * into v_result;

  -- 이 사용자의 모든 그룹 설정이 실제로 'off'인지 확인한다(일시중지는 저장
  -- 삭제 트리거가 아니다 — upsert_location_ping()의 저장 게이트와 동일한 기준).
  select exists (
    select 1
    from public.location_share_settings s
    where s.user_id = v_uid
      and s.mode <> 'off'
  ) into v_any_active;

  if not v_any_active then
    delete from public.user_locations where user_id = v_uid;
  end if;

  return v_result;
end;
$$;

revoke all on function public.set_location_share_mode(uuid, text, int) from public;
grant execute on function public.set_location_share_mode(uuid, text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- 3) 그룹 내 상대들의 최신 위치 스냅샷 조회
--    SECURITY DEFINER가 아닌 일반(INVOKER) 함수로 정의한다: 호출자의 RLS가
--    user_locations / relationship_members / profiles에 그대로 적용되므로,
--    "누구의 위치가 보이는지"에 대한 단일 진실 공급원(RLS)을 이 함수에서
--    중복 구현하지 않는다. 다만 mode = 'approx'인 상대의 좌표는 약 100m
--    격자(0.001도 ≈ 111m)로 서버가 강제 반올림해서 반환한다.
-- -----------------------------------------------------------------------------
create or replace function public.get_peer_locations(p_relationship_group_id uuid)
returns table (
  user_id uuid,
  nickname text,
  location extensions.geography,
  accuracy_m numeric,
  battery_level smallint,
  is_charging boolean,
  movement_state text,
  captured_at timestamptz,
  received_at timestamptz,
  mode public.location_share_mode
)
language sql
stable
set search_path = public
as $$
  select
    ul.user_id,
    p.nickname,
    case
      when public.get_share_mode(ul.user_id, p_relationship_group_id) = 'approx' then
        extensions.st_setsrid(
          extensions.st_snaptogrid(ul.location::extensions.geometry, 0.001, 0.001),
          4326
        )::extensions.geography
      else ul.location
    end as location,
    case
      when public.get_share_mode(ul.user_id, p_relationship_group_id) = 'approx' then null
      else ul.accuracy_m
    end as accuracy_m,
    ul.battery_level,
    ul.is_charging,
    ul.movement_state,
    ul.captured_at,
    ul.received_at,
    public.get_share_mode(ul.user_id, p_relationship_group_id) as mode
  from public.user_locations ul
  join public.profiles p on p.id = ul.user_id
  join public.relationship_members rm
    on rm.user_id = ul.user_id
   and rm.group_id = p_relationship_group_id
  where ul.user_id <> auth.uid();
$$;

comment on function public.get_peer_locations(uuid) is
  '해당 관계 그룹에서 RLS상 조회 가능한 상대들의 최신 위치. mode=approx인 상대는 좌표를 약 100m 격자로 반올림해서 반환(서버 강제).';

revoke all on function public.get_peer_locations(uuid) from public;
grant execute on function public.get_peer_locations(uuid) to authenticated;

-- <<< END 20260820090011_location_functions.sql <<<


-- >>> FILE 12/16: 20260820090012_location_realtime.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- 곁에(Gyeote) Phase 1: 위치 변경 Realtime Broadcast
-- -----------------------------------------------------------------------------
-- upsert_location_ping() RPC가 저장을 마친 뒤 notify_location_ping()을 호출해
-- "relationship:{group_id}:location" 토픽으로 변경을 전파한다. Supabase의
-- Broadcast from Database 기능(realtime.send)을 사용한다.
--
--   realtime.send(payload jsonb, event text, topic text, private boolean)
--
-- 이 스키마/함수는 Supabase 플랫폼(Realtime 서버가 부트스트랩한 `realtime`
-- 스키마)에서만 존재한다. 순수 PostgreSQL(예: 이 저장소에서 RLS를 검증하기
-- 위해 쓰는 로컬 psql 환경)에는 `realtime` 스키마가 없으므로, 함수 내부에서
-- 스키마 존재 여부를 먼저 확인하고 없으면 조용히 아무 것도 하지 않는다
-- (마이그레이션 자체는 두 환경 모두에서 항상 적용 가능해야 하므로).
--
-- mode='approx'인 그룹에는 좌표를 get_peer_locations()와 동일하게 약 100m
-- 격자로 반올림해서 브로드캐스트한다 — 실시간 채널로도 정밀 좌표가 새어나가지
-- 않도록 서버가 강제한다.
--
-- ***Realtime Authorization 관련 중요 사항 (README에도 기재)***
-- 이 채널은 비멤버가 도청하지 못하도록 반드시 "Private" 채널로 구독해야 하며
-- (클라이언트: `supabase.channel(topic, { config: { private: true } })`),
-- 아래 DO 블록에서 `realtime.messages`에 RLS 정책을 걸어 그룹 멤버만 해당
-- 토픽을 구독(SELECT)할 수 있도록 제한한다. 이 RLS가 없으면 인증된 사용자
-- 누구나 임의의 관계 그룹 topic을 구독해 도청할 수 있으므로 반드시 필요하다.
-- =============================================================================

create or replace function public.notify_location_ping(p_location public.user_locations)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_realtime boolean;
  v_group record;
  v_geog extensions.geography;
  v_payload jsonb;
begin
  select exists (select 1 from pg_namespace where nspname = 'realtime')
    into v_has_realtime;

  if not v_has_realtime then
    -- 실제 Supabase 플랫폼이 아닌 환경(예: 순수 로컬 Postgres 검증 환경)에서는
    -- 브로드캐스트를 생략한다. 클라이언트는 이 경우 postgres_changes 구독으로
    -- 대체 가능(README 참고).
    return;
  end if;

  for v_group in
    select rm.group_id, s.mode
    from public.relationship_members rm
    join public.location_share_settings s
      on s.relationship_group_id = rm.group_id
     and s.user_id = rm.user_id
    where rm.user_id = p_location.user_id
      and s.mode <> 'off'
      and (s.paused_until is null or s.paused_until <= now())
  loop
    if v_group.mode = 'approx' then
      v_geog := extensions.st_setsrid(
        extensions.st_snaptogrid(p_location.location::extensions.geometry, 0.001, 0.001),
        4326
      )::extensions.geography;
    else
      v_geog := p_location.location;
    end if;

    v_payload := jsonb_build_object(
      'user_id', p_location.user_id,
      'longitude', extensions.st_x(v_geog::extensions.geometry),
      'latitude', extensions.st_y(v_geog::extensions.geometry),
      'accuracy_m', case when v_group.mode = 'approx' then null else p_location.accuracy_m end,
      'battery_level', p_location.battery_level,
      'is_charging', p_location.is_charging,
      'movement_state', p_location.movement_state,
      'captured_at', p_location.captured_at,
      'mode', v_group.mode
    );

    perform realtime.send(
      v_payload,
      'location_update',
      'relationship:' || v_group.group_id::text || ':location',
      true
    );
  end loop;
end;
$$;

comment on function public.notify_location_ping(public.user_locations) is
  'upsert_location_ping()에서 호출. relationship:{group_id}:location 토픽으로 위치 변경을 브로드캐스트(realtime 스키마가 있는 환경에서만 동작).';

revoke all on function public.notify_location_ping(public.user_locations) from public;
grant execute on function public.notify_location_ping(public.user_locations) to authenticated;

-- -----------------------------------------------------------------------------
-- Realtime Authorization: 그룹 멤버만 해당 위치 브로드캐스트 토픽을 구독 가능
-- realtime.messages 테이블은 Supabase 플랫폼에서만 존재하므로 DO 블록으로 감싸
-- 순수 로컬 Postgres 환경에서도 이 마이그레이션 전체가 에러 없이 적용되게 한다.
-- -----------------------------------------------------------------------------
do $outer$
begin
  if exists (select 1 from pg_namespace where nspname = 'realtime')
     and exists (
       select 1 from information_schema.tables
       where table_schema = 'realtime' and table_name = 'messages'
     )
  then
    execute 'alter table realtime.messages enable row level security';

    execute 'drop policy if exists "location_broadcast_group_members_only" on realtime.messages';

    execute $policy$
      create policy "location_broadcast_group_members_only"
      on realtime.messages
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.relationship_members m
          where m.user_id = auth.uid()
            and 'relationship:' || m.group_id::text || ':location' = realtime.topic()
        )
      )
    $policy$;
  else
    raise notice 'realtime.messages not found; skipping Realtime Authorization policy (local non-Supabase Postgres). Apply this migration against a real Supabase project so it takes effect.';
  end if;
end;
$outer$;

-- <<< END 20260820090012_location_realtime.sql <<<


-- >>> FILE 13/16: 20260823100001_fix_invitation_email_check.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260823100001_fix_invitation_email_check.sql <<<


-- >>> FILE 14/16: 20260823100002_fix_location_spoofing_and_scope_bypass.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- 곁에(Gyeote) 위치 공유 보안 수정: 스푸핑(HIGH-1) + 접근범위 우회(HIGH-2)
-- -----------------------------------------------------------------------------
-- Rena(Reviewer)가 지적한 이슈를 수정한다. 최초 리뷰에서 나온 HIGH-1/HIGH-2에
-- 더해, 재리뷰에서 "HIGH-2와 같은 종류의 그룹 경계 우회"가 형제 함수
-- get_share_mode()에 남아있는 것(A), get_peer_locations() 자체의 CASE
-- 분기가 mode='off'/설정 없음일 때 정밀 좌표를 흘리는 잔여 버그(B), 그리고
-- 일시중지(paused_until)가 읽기 경로(get_peer_locations)에서는 그룹별로
-- 적용되지 않는 것(C, Plexa 재확인 지적)이 추가로 발견되어 같이 수정한다.
-- 세 건 모두 "그룹별로 다르게 설정된 상태(멤버십/모드/일시중지)를 크로스-
-- 그룹 판별(can_view_location)로 대체해버려서, 그룹 A에서만 활성 공유
-- 중이어도 그룹 B의 정보에 접근/추론 가능해지는" 동일한 결함 패턴이므로
-- 한 마이그레이션에 묶는다.
--
-- [HIGH-1] 위치 스푸핑: notify_location_ping()은 SECURITY DEFINER이면서
--   `grant execute ... to authenticated`가 걸려 있어, 클라이언트가
--   upsert_location_ping()을 거치지 않고 이 함수를 직접 RPC로 호출할 수
--   있었다. 이 함수는 인자로 받은 user_locations 행(row)의 user_id를 그대로
--   신뢰해 realtime.send()로 브로드캐스트하므로, 인증된 사용자 누구나
--   임의의 p_location.user_id를 지정해 그 사람 명의로 위조된 좌표를
--   "relationship:{group_id}:location" 토픽에 전파할 수 있었다(피해자 본인의
--   실제 그룹 목록을 순회해 그 각각에 브로드캐스트하므로, 상대방 앱에는
--   실제로 그 사람이 위조된 위치로 이동한 것처럼 보이게 된다).
--   수정: 클라이언트에는 execute 권한을 주지 않아 upsert_location_ping()
--   내부 호출로만 도달 가능하게 하고, 함수 내부에도 방어적으로
--   p_location.user_id = auth.uid() 검증을 추가한다(정책 grant 실수로
--   다시 노출되더라도 스푸핑이 불가능하도록 이중 방어).
--
-- [HIGH-2] 접근범위 우회: get_peer_locations(p_relationship_group_id)가
--   호출자가 실제로 그 그룹의 멤버인지 전혀 검증하지 않았다. 기반 RLS
--   정책(user_locations_select_shared → can_view_location)은 "호출자와
--   대상이 활성 공유 중인 그룹이 하나라도 있는지"만 판별하고 어떤
--   특정 그룹인지는 보지 않으므로, 호출자가 자신이 속하지 않은 임의의
--   group_id를 인자로 넘겨도 "그 그룹의 다른 멤버와 다른 그룹에서
--   활성 공유 중"이기만 하면 해당 멤버의 실시간 위치(및 닉네임)가
--   그대로 반환됐다 — 즉 그룹 경계를 넘어 자신이 속하지 않은 그룹의
--   위치 정보를 열람할 수 있는 접근범위 우회였다.
--   수정: 호출자가 p_relationship_group_id의 실제 멤버인지를
--   is_group_member()로 명시적으로 검증하도록 WHERE 절에 추가한다
--   (set_location_share_mode()가 이미 쓰기 경로에서 쓰는 것과 동일한
--   검증을 읽기 경로에도 적용).
--
-- [A] get_share_mode 그룹경계 우회(HIGH-2와 동일 패턴, 재리뷰 지적):
--   get_share_mode(p_owner_id, p_relationship_group_id)는 authenticated에
--   직접 EXECUTE가 걸린 RPC이면서, "호출자가 p_relationship_group_id의
--   멤버인지"를 전혀 확인하지 않고 `can_view_location(p_owner_id,
--   auth.uid())`(= "어떤 그룹에서든 활성 공유 중이면 true"인 크로스-그룹
--   판별)만 확인했다. 즉 호출자가 피해자와 그룹 A에서만 활성 공유 중이어도,
--   자신이 속하지 않은 그룹 B의 id를 직접 넘겨 get_share_mode(피해자, 그룹B)를
--   호출하면 그룹 B에 대한 피해자의 공유 모드(및 그룹 B 멤버십 여부)를
--   알아낼 수 있었다 — get_peer_locations에서 막은 것과 같은 종류의 그룹
--   경계 우회가 형제 함수로 그대로 열려 있었다.
--   수정: WHERE 절에 is_group_member(p_relationship_group_id, auth.uid())를
--   추가한다. get_peer_locations()는 INVOKER 함수라 이 함수를 "실제 호출자"
--   권한으로 호출하므로 EXECUTE grant 자체는 유지해야 한다(notify_location_ping
--   처럼 revoke로 닫을 수 없다) — 로직 안쪽에서 멤버십을 검증하는 방식으로
--   막는다. 비멤버 호출 시에는 (get_peer_locations와 일관되게) 예외가 아니라
--   NULL을 반환한다: 예외를 던지면 "이 그룹이 존재하는지" 자체가 오라클이
--   되어 버리기 때문이다.
--
-- [B] get_peer_locations CASE 분기의 잔여 유출(재리뷰 지적, 이번 수정과
--   무관하게 원래부터 있던 버그이나 이번에 다시 정의하는 함수라 같이 고침):
--   CASE 분기가 get_share_mode() = 'approx'만 반올림 처리하고 나머지는 모두
--   else(정밀 좌표 그대로)로 떨어진다. get_share_mode가 'off'를 반환하거나
--   (해당 그룹에서 명시적으로 껐음) 아예 NULL을 반환하는(해당 그룹에 대한
--   location_share_settings 행 자체가 없음) 두 경우 모두 정밀 좌표가 그대로
--   노출됐다. RLS(can_view_location)는 "어떤 그룹에서든 활성 공유 중이면
--   통과"이므로, 피해자가 그룹 G1에서는 off, 그룹 G2에서는 공유 중이면
--   get_peer_locations(G1) 호출 시(G2 덕에 RLS는 통과) G1에서 꺼둔 사람의
--   정밀 좌표가 그대로 노출됐다 — "이 그룹에서는 안 보이게 껐다"는 사용자
--   기대와 정면으로 어긋난다.
--   수정: WHERE 절에 get_share_mode(...) in ('precise', 'approx') 조건을
--   추가해, 해당 그룹에서 mode가 명시적으로 precise/approx인 경우만 결과에
--   포함시킨다(off/설정 없음/NULL은 결과에서 완전히 제외).
--
-- [C] 일시중지(paused_until)가 읽기 경로에서 그룹별로 적용되지 않음:
--   paused_until은 mode 컬럼을 바꾸지 않고 location_share_settings의 별도
--   컬럼에만 기록되므로, 일시중지 중이어도 get_share_mode()는 여전히
--   'precise'/'approx'를 반환하고 위 (B)에서 추가한
--   `get_share_mode(...) in ('precise', 'approx')` 필터를 그대로 통과한다.
--   일시중지를 실제로 반영하는 건 user_locations의 RLS(can_view_location)
--   뿐인데, 이는 HIGH-2에서 확인했듯 "어떤 그룹에서든" 판별하는 크로스-그룹
--   함수다. 그 결과: 피해자가 그룹 G1에서는 일시중지, 그룹 G2에서는 정상
--   공유 중이고 호출자가 두 그룹 모두의 멤버이면, get_peer_locations(G1)
--   호출 시 RLS는 G2 덕분에 통과하고 is_group_member(G1)/get_share_mode(G1)
--   모두 통과해 G1에서 일시중지해둔 위치가 그대로 반환된다. 이는 특히
--   notify_location_ping()의 브로드캐스트 루프가 이미 그룹별로
--   `paused_until is null or paused_until <= now()`를 검사해 일시중지된
--   그룹에는 애초에 브로드캐스트하지 않는 것과 어긋난다 — 사용자가 일시중지를
--   누르면 실시간 갱신은 멈추지만, 상대가 폴링(새로고침)으로 get_peer_locations를
--   다시 부르면 그 그룹에서 일시중지해둔 위치가 다시 보이는 모순이 있었다.
--   수정: get_share_mode와 동일한 멤버십/가시성 게이팅을 쓰는 새 헬퍼
--   is_location_paused(p_owner_id, p_relationship_group_id)를 추가하고,
--   get_peer_locations의 WHERE 절에 `not coalesce(is_location_paused(...),
--   true)` 조건을 더한다(비멤버/비가시 상태에서 NULL이 나오면 기본값을
--   "일시중지된 것으로 간주"(제외)로 두어, (A)에서 세운 "비멤버에게는 예외
--   대신 조용한 제외" 원칙을 그대로 유지하면서 실패 시 기본을 안전한 쪽으로
--   둔다). get_share_mode 자체는 건드리지 않는다 — 본인이 자기 모드를 조회할
--   때(p_owner_id = auth.uid())는 일시중지 여부와 무관하게 "설정된 모드"를
--   그대로 알 수 있어야 하므로, 그 계약을 이 수정으로 바꾸지 않는다.
-- =============================================================================

create or replace function public.notify_location_ping(p_location public.user_locations)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_realtime boolean;
  v_group record;
  v_geog extensions.geography;
  v_payload jsonb;
begin
  -- 방어적 재검증: 이 함수는 upsert_location_ping() 내부에서만 호출되어야
  -- 하며, 그 경우 p_location.user_id는 항상 auth.uid()와 일치한다. grant
  -- 실수 등으로 클라이언트가 직접 호출하더라도 타인 명의로 브로드캐스트를
  -- 위조할 수 없도록 여기서도 반드시 재확인한다.
  if p_location.user_id is distinct from auth.uid() then
    raise exception 'cannot broadcast a location ping on behalf of another user';
  end if;

  select exists (select 1 from pg_namespace where nspname = 'realtime')
    into v_has_realtime;

  if not v_has_realtime then
    -- 실제 Supabase 플랫폼이 아닌 환경(예: 순수 로컬 Postgres 검증 환경)에서는
    -- 브로드캐스트를 생략한다. 클라이언트는 이 경우 postgres_changes 구독으로
    -- 대체 가능(README 참고).
    return;
  end if;

  for v_group in
    select rm.group_id, s.mode
    from public.relationship_members rm
    join public.location_share_settings s
      on s.relationship_group_id = rm.group_id
     and s.user_id = rm.user_id
    where rm.user_id = p_location.user_id
      and s.mode <> 'off'
      and (s.paused_until is null or s.paused_until <= now())
  loop
    if v_group.mode = 'approx' then
      v_geog := extensions.st_setsrid(
        extensions.st_snaptogrid(p_location.location::extensions.geometry, 0.001, 0.001),
        4326
      )::extensions.geography;
    else
      v_geog := p_location.location;
    end if;

    v_payload := jsonb_build_object(
      'user_id', p_location.user_id,
      'longitude', extensions.st_x(v_geog::extensions.geometry),
      'latitude', extensions.st_y(v_geog::extensions.geometry),
      'accuracy_m', case when v_group.mode = 'approx' then null else p_location.accuracy_m end,
      'battery_level', p_location.battery_level,
      'is_charging', p_location.is_charging,
      'movement_state', p_location.movement_state,
      'captured_at', p_location.captured_at,
      'mode', v_group.mode
    );

    perform realtime.send(
      v_payload,
      'location_update',
      'relationship:' || v_group.group_id::text || ':location',
      true
    );
  end loop;
end;
$$;

comment on function public.notify_location_ping(public.user_locations) is
  'upsert_location_ping()에서만 호출되는 내부 헬퍼(클라이언트에 execute 권한 없음). relationship:{group_id}:location 토픽으로 위치 변경을 브로드캐스트. p_location.user_id = auth.uid() 검증으로 타인 명의 스푸핑을 차단.';

-- [HIGH-1 수정 핵심] 클라이언트(authenticated)에는 더 이상 execute 권한을
-- 주지 않는다. upsert_location_ping()은 SECURITY DEFINER로 실행되므로 이
-- revoke와 무관하게 내부에서 계속 notify_location_ping()을 호출할 수 있다.
revoke all on function public.notify_location_ping(public.user_locations) from public;
revoke execute on function public.notify_location_ping(public.user_locations) from authenticated;

-- -----------------------------------------------------------------------------
-- [A 수정] get_share_mode: 호출자가 p_relationship_group_id의 실제 멤버가
-- 아니면 NULL을 반환한다(예외 아님 — get_peer_locations와 동일한 관례로
-- "그룹 존재 여부" 오라클을 만들지 않는다).
-- -----------------------------------------------------------------------------
create or replace function public.get_share_mode(p_owner_id uuid, p_relationship_group_id uuid)
returns public.location_share_mode
language sql
security definer
stable
set search_path = public
as $$
  -- 이 is_group_member 검증은 get_peer_locations 경유 호출 관점에서는 바깥
  -- WHERE의 is_group_member와 중복처럼 보일 수 있지만, 제거하면 안 된다:
  -- get_share_mode는 authenticated에 EXECUTE가 걸린 독립 RPC라서 클라이언트가
  -- get_peer_locations를 거치지 않고 이 함수를 직접 호출하는 경로가 있고,
  -- 그 경로에서는 이 검증이 (A)에서 막은 그룹경계 우회에 대한 유일한 방어선이다
  -- — 걷어내면 (A)가 그대로 되살아난다.
  select s.mode
  from public.location_share_settings s
  where s.user_id = p_owner_id
    and s.relationship_group_id = p_relationship_group_id
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and (
      p_owner_id = auth.uid()
      or public.can_view_location(p_owner_id, auth.uid())
    );
$$;

comment on function public.get_share_mode(uuid, uuid) is
  '특정 관계 그룹에서의 공유 모드 조회. 호출자가 p_relationship_group_id의 실제 멤버가 아니면 NULL(예외 아님 — 그룹 존재 여부 오라클 방지). 멤버라도 본인 자신을 조회하는 경우이거나 can_view_location()이 true인 경우에만 값을 반환.';

-- get_peer_locations()가 INVOKER 함수로서 이 함수를 실제 호출자 권한으로
-- 호출하므로, EXECUTE grant 자체는 유지한다(notify_location_ping처럼
-- revoke로 닫을 수 없다 — 멤버십 검증은 위 로직 안쪽에서 처리).
revoke all on function public.get_share_mode(uuid, uuid) from public;
grant execute on function public.get_share_mode(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- [C 수정] is_location_paused: 특정 관계 그룹에서 대상의 위치 공유가 지금
-- 일시중지 중인지 판별한다. get_share_mode와 동일한 멤버십/가시성 게이팅을
-- 쓰되(비멤버/비가시 상태에서는 NULL 반환 — 예외로 오라클을 만들지 않는다),
-- get_peer_locations에서 이 값이 NULL이면 coalesce로 "일시중지된 것으로
-- 간주"(안전 쪽 기본값)해서 사용한다.
-- -----------------------------------------------------------------------------
create or replace function public.is_location_paused(p_owner_id uuid, p_relationship_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select s.paused_until is not null and s.paused_until > now()
  from public.location_share_settings s
  where s.user_id = p_owner_id
    and s.relationship_group_id = p_relationship_group_id
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and (
      p_owner_id = auth.uid()
      or public.can_view_location(p_owner_id, auth.uid())
    );
$$;

comment on function public.is_location_paused(uuid, uuid) is
  '특정 관계 그룹에서 대상의 위치 공유가 지금 일시중지(paused_until > now()) 중인지 판별. 호출자가 그 그룹의 멤버가 아니거나 볼 권한이 없으면 NULL(예외 아님 — get_share_mode와 동일한 관례).';

revoke all on function public.is_location_paused(uuid, uuid) from public;
grant execute on function public.is_location_paused(uuid, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- [HIGH-2 / B / C 수정] get_peer_locations:
--   - (HIGH-2) 호출자가 p_relationship_group_id의 실제 멤버일 때만 결과를
--     반환한다. 기존에는 이 검증이 없어, 기반 RLS(can_view_location)가
--     "다른 그룹에서의 활성 공유"만으로 행을 통과시키는 특성을 악용해
--     호출자가 속하지 않은 그룹의 위치를 조회할 수 있었다.
--   - (B) get_share_mode(...) in ('precise', 'approx') 조건을 WHERE에
--     추가해, 해당 그룹에서 mode가 'off'이거나 설정이 아예 없는(NULL)
--     상대는 결과에서 완전히 제외한다. 이전에는 CASE 분기가 'approx'만
--     특별 취급하고 나머지(off/NULL 포함)를 전부 정밀 좌표로 반환했다.
--   - (C) not coalesce(is_location_paused(...), true) 조건을 WHERE에 추가해,
--     해당 그룹에서 지금 일시중지 중인 상대도 결과에서 제외한다(브로드캐스트
--     경로의 paused_until 검사와 동작을 맞춘다).
-- -----------------------------------------------------------------------------
create or replace function public.get_peer_locations(p_relationship_group_id uuid)
returns table (
  user_id uuid,
  nickname text,
  location extensions.geography,
  accuracy_m numeric,
  battery_level smallint,
  is_charging boolean,
  movement_state text,
  captured_at timestamptz,
  received_at timestamptz,
  mode public.location_share_mode
)
language sql
stable
set search_path = public
as $$
  select
    ul.user_id,
    p.nickname,
    case
      when public.get_share_mode(ul.user_id, p_relationship_group_id) = 'approx' then
        extensions.st_setsrid(
          extensions.st_snaptogrid(ul.location::extensions.geometry, 0.001, 0.001),
          4326
        )::extensions.geography
      else ul.location
    end as location,
    case
      when public.get_share_mode(ul.user_id, p_relationship_group_id) = 'approx' then null
      else ul.accuracy_m
    end as accuracy_m,
    ul.battery_level,
    ul.is_charging,
    ul.movement_state,
    ul.captured_at,
    ul.received_at,
    public.get_share_mode(ul.user_id, p_relationship_group_id) as mode
  from public.user_locations ul
  join public.profiles p on p.id = ul.user_id
  join public.relationship_members rm
    on rm.user_id = ul.user_id
   and rm.group_id = p_relationship_group_id
  where ul.user_id <> auth.uid()
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and public.get_share_mode(ul.user_id, p_relationship_group_id) in ('precise', 'approx')
    and not coalesce(public.is_location_paused(ul.user_id, p_relationship_group_id), true);
$$;

comment on function public.get_peer_locations(uuid) is
  '호출자가 실제 멤버인 관계 그룹에서, RLS상 조회 가능하고 해당 그룹에서 mode가 precise/approx로 켜져 있으며 지금 일시중지 중이 아닌 상대들의 최신 위치. mode=approx인 상대는 좌표를 약 100m 격자로 반올림해서 반환(서버 강제). 호출자가 해당 그룹의 멤버가 아니거나, 상대가 해당 그룹에서 off/미설정/일시중지 중이면 그 상대는 결과에서 제외된다.';

revoke all on function public.get_peer_locations(uuid) from public;
grant execute on function public.get_peer_locations(uuid) to authenticated;

-- <<< END 20260823100002_fix_location_spoofing_and_scope_bypass.sql <<<


-- >>> FILE 15/16: 20260823100003_fix_location_ping_input_validation.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- 곁에(Gyeote) 위치 핑 입력 검증 누락 수정 (원시 제약조건 에러 노출, P0-4)
-- -----------------------------------------------------------------------------
-- Rena(Reviewer) 재리뷰 지적: upsert_location_ping()은 p_location 타입,
-- movement_state, captured_at은 명시적으로 검증하지만 accuracy_m(>= 0)과
-- battery_level(0~100)은 검증 없이 바로 INSERT한다. user_locations
-- 테이블에는 이 두 컬럼에 CHECK 제약조건이 걸려 있으므로
-- (20260820090009_user_locations.sql), 클라이언트가 음수 accuracy_m이나
-- 101 이상 battery_level을 보내면 Postgres가 다음과 같은 원시 메시지를
-- 던지고 이게 PostgrestException.message로 그대로 화면까지 도달한다:
--
--   new row for relation "user_locations" violates check constraint
--   "user_locations_battery_level_check"
--
-- 테이블명과 자동생성된 제약조건명이 사용자 화면에 노출되는 내부 구현 정보
-- 유출이다. 스푸핑/접근범위 우회(100002)와는 성격이 다른 결함(권한/격리가
-- 아니라 입력 검증 누락)이라 별도 마이그레이션으로 분리한다.
--
-- 수정: movement_state와 동일한 패턴으로, INSERT 이전에 accuracy_m/
-- battery_level 범위를 명시적으로 검증해 사람이 읽을 수 있는 예외로 먼저
-- 걸러지게 한다. 원본 CHECK 제약조건은 그대로 두어(방어 심층화) 이 검증을
-- 우회하는 다른 쓰기 경로가 생기더라도 DB가 최종 방어선 역할을 계속한다.
-- =============================================================================

create or replace function public.upsert_location_ping(
  p_location extensions.geography,
  p_accuracy_m numeric default null,
  p_battery_level smallint default null,
  p_is_charging boolean default null,
  p_movement_state text default null,
  p_captured_at timestamptz default now()
)
returns public.user_locations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.user_locations;
  v_result public.user_locations;
  v_has_active_share boolean;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  if extensions.geometrytype(p_location::extensions.geometry) <> 'POINT' then
    raise exception 'location must be a Point geography';
  end if;

  if p_accuracy_m is not null and p_accuracy_m < 0 then
    raise exception 'accuracy_m must be non-negative';
  end if;

  if p_battery_level is not null and p_battery_level not between 0 and 100 then
    raise exception 'battery_level must be between 0 and 100';
  end if;

  if p_movement_state is not null and p_movement_state not in ('stationary', 'walking', 'moving') then
    raise exception 'invalid movement_state: %', p_movement_state;
  end if;

  if p_captured_at is null then
    raise exception 'captured_at is required';
  end if;

  -- 프라이버시 게이트: mode가 off가 아닌 그룹이 하나도 없으면(=모든 그룹에서
  -- 완전히 꺼둔 경우) 위치 저장 자체를 거부한다. 일시중지(paused_until)는
  -- "누구에게 보일지"만 제어하는 가시성 문제이며 저장 허용 여부와는 무관하게
  -- 둔다 — 그래야 일시중지가 끝나는 즉시(새 GPS fix를 기다릴 필요 없이) 마지막
  -- 위치가 다시 노출될 수 있다. 완전 삭제는 mode가 실제로 'off'로 바뀔 때만
  -- set_location_share_mode()에서 수행한다.
  select exists (
    select 1
    from public.location_share_settings s
    where s.user_id = v_uid
      and s.mode <> 'off'
  ) into v_has_active_share;

  if not v_has_active_share then
    raise exception 'location sharing is off for all groups; enable sharing before sending a location ping';
  end if;

  select * into v_existing from public.user_locations where user_id = v_uid for update;

  -- 오프라인 큐 플러시 등으로 과거 시각의 좌표가 뒤늦게 도착한 경우, 이미 저장된
  -- 더 최신 captured_at 값보다 과거라면 역행을 방지하기 위해 무시하고 기존
  -- 최신 행을 그대로 반환한다.
  if found and v_existing.captured_at > p_captured_at then
    return v_existing;
  end if;

  insert into public.user_locations (
    user_id, location, accuracy_m, battery_level, is_charging, movement_state, captured_at, received_at
  ) values (
    v_uid, p_location, p_accuracy_m, p_battery_level, p_is_charging, p_movement_state, p_captured_at, now()
  )
  on conflict (user_id) do update set
    location = excluded.location,
    accuracy_m = excluded.accuracy_m,
    battery_level = excluded.battery_level,
    is_charging = excluded.is_charging,
    movement_state = excluded.movement_state,
    captured_at = excluded.captured_at,
    received_at = excluded.received_at
  returning * into v_result;

  insert into public.location_history (user_id, location, captured_at)
  values (v_uid, p_location, p_captured_at);

  -- Realtime 브로드캐스트 (실제 Supabase 환경에서만 존재하는 realtime 스키마가
  -- 있을 때만 동작; 20260820090012 참고).
  perform public.notify_location_ping(v_result);

  return v_result;
end;
$$;

comment on function public.upsert_location_ping(
  extensions.geography, numeric, smallint, boolean, text, timestamptz
) is
  '본인 위치 핑 업서트 + location_history 적재. accuracy_m(>=0)/battery_level(0~100)/movement_state/captured_at을 INSERT 전에 명시적으로 검증해 사람이 읽을 수 있는 예외로 걸러낸다(원시 user_locations CHECK 제약조건 위반 메시지가 클라이언트까지 노출되는 것을 방지). 모든 그룹이 off면 거부.';

-- <<< END 20260823100003_fix_location_ping_input_validation.sql <<<


-- >>> FILE 16/16: 20260903090001_schedule_location_history_retention.sql >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

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

-- <<< END 20260903090001_schedule_location_history_retention.sql <<<


-- =============================================================================
-- 마이그레이션 원장 기록
-- -----------------------------------------------------------------------------
-- 위 마이그레이션들이 이 DB에 적용됐음을 supabase_migrations.schema_migrations
-- 에 남긴다. 이후 'supabase db push' 는 원장에 없는 버전만 적용하므로, 이
-- 기록이 있어야 수동 적용분을 CLI 가 다시 적용하지 않는다.
--
-- 스키마/테이블이 없을 수도 있어 방어적으로 생성한다(신규 프로젝트엔 보통
-- 이미 존재한다). 컬럼 구성은 Supabase CLI 가 만드는 것과 동일하게 맞춘다.
-- =============================================================================
create schema if not exists supabase_migrations;

create table if not exists supabase_migrations.schema_migrations (
  version text not null primary key,
  statements text[],
  name text
);

insert into supabase_migrations.schema_migrations (version, name) values
  ('20260820090001', 'extensions'),
  ('20260820090002', 'profiles'),
  ('20260820090003', 'relationship_groups'),
  ('20260820090004', 'relationship_members'),
  ('20260820090005', 'relationship_invitations'),
  ('20260820090006', 'relationship_functions'),
  ('20260820090007', 'location_extensions'),
  ('20260820090008', 'location_share_settings'),
  ('20260820090009', 'user_locations'),
  ('20260820090010', 'location_history'),
  ('20260820090011', 'location_functions'),
  ('20260820090012', 'location_realtime'),
  ('20260823100001', 'fix_invitation_email_check'),
  ('20260823100002', 'fix_location_spoofing_and_scope_bypass'),
  ('20260823100003', 'fix_location_ping_input_validation'),
  ('20260903090001', 'schedule_location_history_retention')
on conflict (version) do nothing;

commit;

-- =============================================================================
-- 끝. 아래로 확인:
--   select version, name from supabase_migrations.schema_migrations order by version;
--   select count(*) from pg_policies where schemaname = 'public';
--   select proname from pg_proc where pronamespace = 'public'::regnamespace order by 1;
-- pg_cron 잡(20260903090001)은 supabase/DEPLOYMENT.md 의 "잡 등록 확인" 게이트로
-- 별도 확인:
--   select jobid, jobname, schedule, active from cron.job
--    where jobname = 'gyeote-location-history-retention';
-- =============================================================================
