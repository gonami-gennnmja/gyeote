-- =============================================================================
-- 곁에(Gyeote) v0.2: get_share_mode / is_location_paused 게이팅을 그룹 한정으로
-- -----------------------------------------------------------------------------
-- Rena 지적 (2026-09-14, 승인 2026-09-15): get_share_mode()/is_location_paused()
-- 의 게이팅이 `is_group_member(G, caller)`(그룹 한정, 정확함) 뒤에
-- `or can_view_location(owner, caller)`를 붙여놨는데, can_view_location은
-- **크로스그룹**("owner와 caller가 같이 속한 그룹이 하나라도 있고, 그중
-- owner가 활성 공유 중인 그룹이 있으면" true)이다. 그 결과: caller가 그룹
-- G의 진짜 멤버이고 owner와 **다른** 그룹에서 활성 공유 중이면, owner가 G
-- 자체에서는 mode='off'로 꺼놨어도 get_share_mode(owner, G)/
-- is_location_paused(owner, G)를 직접 RPC로 호출해 G의 진짜 모드값·일시중지
-- 상태를 읽어낼 수 있었다 — get_peer_locations()는 이미 자체 WHERE로
-- off/paused를 걸러내 이 경로로 새지 않지만(무영향), 두 함수를 직접 호출하는
-- 경로에는 이 구멍이 그대로 남아 있었다.
--
-- 수정: 두 함수의 `or can_view_location(owner, auth.uid())` 분기를 걷어내고,
-- **같은 그룹 안에서** owner의 실제 상태를 직접 보는 조건으로 인라인 교체한다
-- (100002가 B/C를 고칠 때 쓴 것과 동일한 스타일 — 호출처가 2곳뿐이라 새
-- 공유 헬퍼는 만들지 않는다. 헬퍼를 늘리면 "어느 게이트가 어디 걸리는지"가
-- 다시 흐려진다는 판단, Plexa 승인 2026-09-15).
--
--   get_share_mode: 비-본인 caller는 owner가 **이 그룹에서** mode<>'off' 이고
--     지금 paused가 아니며 owner 자신도 이 그룹의 진짜 멤버일 때만 진짜
--     mode 값을 본다. 그 외에는 NULL(예외 아님 — 기존 관례 유지).
--   is_location_paused: 비-본인 caller는 owner가 **이 그룹에서** mode<>'off'
--     이고 owner 자신도 이 그룹의 진짜 멤버일 때만 진짜 pause 여부를 본다.
--     mode가 off면 pause 여부 자체를 안 알려준다(off 상태에서 paused_until이
--     남아있을 수 있어 그 값을 그대로 노출하면 또 다른 오라클이 되므로).
--
-- p_owner_id = auth.uid()(본인 자기 조회) 분기는 그대로 첫 조건으로 보존한다
-- — 본인 접근은 이번 수정과 무관하고, 좁아지는 건 비-본인 경로뿐이다.
--
-- 영향 범위(설계 리뷰에서 정리, Plexa 확인):
--   - can_view_location() 자체, user_locations RLS: 안 건드림(구조적으로
--     그룹 특정이 불가능한 자리라 이번 리스크의 원인이 아님, 기존 README에
--     이미 문서화된 트레이드오프).
--   - get_peer_locations(): 겉보기 동작 무영향. WHERE에 이미
--     `get_share_mode(...) in ('precise','approx')`와
--     `not coalesce(is_location_paused(...), true)`가 있어, 이 두 함수가
--     더 엄격해져도(= off/paused일 때 항상 NULL) 결과셋이 달라지지 않는다.
--   - 프론트: get_share_mode()를 직접 호출하는 코드는 없음(grep 확인).
--     is_location_paused()는 location_repository.dart의 isLocationPaused()가
--     호출하지만, HiddenPeer(hidden_peers.dart, P0-6)가 이미 false/null을
--     구분하지 않고 병합해서 화면에 쓰므로 무영향.
--   - 부수 발견(이번 마이그레이션이 부가로 막아주는 것): leave_relationship_
--     group()/remove_relationship_member()는 relationship_members 행만
--     지우고 location_share_settings 행은 안 지운다 — 그룹을 나가도 설정
--     행이 고아로 남을 수 있다. 이번에 추가하는
--     `is_group_member(G, p_owner_id)` 조건이 이 고아 행도 자동으로
--     걸러준다. 근본 정리(나갈 때 설정 행도 지우기)는 이 마이그레이션의
--     범위가 아니며 별도 후속 티켓으로 남긴다(리스크 낮음 — 이 게이트가
--     이미 가려줌).
-- =============================================================================

create or replace function public.get_share_mode(p_owner_id uuid, p_relationship_group_id uuid)
returns public.location_share_mode
language sql
security definer
stable
set search_path = public
as $$
  -- is_group_member(G, caller) 검증은 get_peer_locations 경유 호출 관점에서는
  -- 바깥 WHERE의 is_group_member와 중복처럼 보일 수 있지만, 제거하면 안
  -- 된다 — get_share_mode는 authenticated에 EXECUTE가 걸린 독립 RPC라서
  -- 클라이언트가 get_peer_locations를 거치지 않고 이 함수를 직접 호출하는
  -- 경로가 있고, 그 경로에서는 이 검증이 그룹경계 우회에 대한 유일한
  -- 방어선이다.
  select s.mode
  from public.location_share_settings s
  where s.user_id = p_owner_id
    and s.relationship_group_id = p_relationship_group_id
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and (
      p_owner_id = auth.uid()
      or (
        -- [v0.2 그룹 한정 수정] 크로스그룹 can_view_location 대신, 같은
        -- 그룹 안에서 owner가 실제로 활성 공유 중인지만 본다. owner가 이
        -- 그룹에서 off거나 paused면(또는 이미 그룹을 나갔으면) NULL.
        public.is_group_member(p_relationship_group_id, p_owner_id)
        and s.mode <> 'off'
        and (s.paused_until is null or s.paused_until <= now())
      )
    );
$$;

comment on function public.get_share_mode(uuid, uuid) is
  '특정 관계 그룹에서의 공유 모드 조회. 호출자가 p_relationship_group_id의 실제 멤버가 아니면 NULL. 본인 자신을 조회하는 경우가 아니면, owner가 그 그룹에서 실제로 활성 공유 중(mode<>off, not paused)일 때만 값을 반환한다(v0.2: 크로스그룹 can_view_location 제거 — 다른 그룹의 활성 공유로 이 그룹의 off/paused 상태를 알아내는 경로 차단).';

revoke all on function public.get_share_mode(uuid, uuid) from public;
grant execute on function public.get_share_mode(uuid, uuid) to authenticated;

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
    and s.mode <> 'off'
    and public.is_group_member(p_relationship_group_id, auth.uid())
    and (
      p_owner_id = auth.uid()
      or public.is_group_member(p_relationship_group_id, p_owner_id)
    );
$$;

comment on function public.is_location_paused(uuid, uuid) is
  '특정 관계 그룹에서 대상의 위치 공유가 지금 일시중지(paused_until > now()) 중인지 판별. 호출자가 그 그룹의 멤버가 아니거나, mode가 off거나, owner가 이미 그 그룹을 나갔으면 NULL(v0.2: 크로스그룹 can_view_location 제거 — get_share_mode와 동일한 그룹 한정 원칙).';

revoke all on function public.is_location_paused(uuid, uuid) from public;
grant execute on function public.is_location_paused(uuid, uuid) to authenticated;
