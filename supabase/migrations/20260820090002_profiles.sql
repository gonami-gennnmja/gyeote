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
