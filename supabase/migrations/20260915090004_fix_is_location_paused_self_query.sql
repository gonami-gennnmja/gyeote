-- =============================================================================
-- 곁에(Gyeote) v0.2: is_location_paused 자기조회 불일치 수정 (Rena 지적,
-- 2026-09-15)
-- -----------------------------------------------------------------------------
-- 20260915090003이 is_location_paused()를 그룹 한정으로 고치면서
-- `and s.mode <> 'off'`를 WHERE 최상위(본인 조회/타인 조회 공통 조건)에
-- 넣었다. 그 결과: 본인이 그 그룹을 off로 꺼둔 상태에서 자기 자신의 pause
-- 상태를 물으면(p_owner_id = auth.uid()) NULL이 나온다. get_share_mode()는
-- 같은 090003에서 `s.mode <> 'off'` 조건을 **비-본인 분기 안쪽에만** 넣어서
-- 본인 조회는 항상 통과하는데, is_location_paused()는 그 조건이 최상위에
-- 있어 본인 조회까지 막힌다 — 두 함수가 구조적으로 어긋나 있었다.
--
-- 지금 이 어긋남이 실제로 문제를 일으키는 경로는 없다(get_peer_locations는
-- `ul.user_id <> auth.uid()`로 애초에 본인을 제외하고 호출하고, 프론트
-- location_repository.dart의 isLocationPaused()도 숨은 멤버 후보에서
-- 본인을 미리 제외한 뒤 호출한다 — 둘 다 p_owner_id = auth.uid()로
-- 호출되는 경로 자체가 없음). 그래도 고치는 이유: 20260915090003 커밋
-- 메시지가 "p_owner_id = auth.uid() 본인 조회 분기는 그대로 보존해 본인
-- 접근 무영향"이라고 적었는데, is_location_paused()는 실제로 그렇지 않았다
-- — 커밋 설명이 코드보다 앞서 있었다(이번 라운드 내내 잡아온 "성공처럼
-- 보이는 실패"/"검증 안 된 걸 검증된 것처럼 쓰는" 문제가, 이번엔 우리
-- 자신의 커밋 메시지에서 재현된 사례). 그 설명을 정확하게 만들려면 코드
-- 자체를 고쳐야 한다.
--
-- 수정: `s.mode <> 'off'` 조건을 get_share_mode와 동일한 자리(비-본인 분기
-- 안쪽)로 옮긴다. 이제 두 함수의 게이팅 구조가 동일하다: 본인 조회는 항상
-- 통과(mode/멤버십 무관), 비-본인 조회만 "그 그룹에서 owner가 활성 공유
-- 중 + owner도 진짜 멤버"를 요구한다.
-- =============================================================================

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
      or (
        public.is_group_member(p_relationship_group_id, p_owner_id)
        and s.mode <> 'off'
      )
    );
$$;

comment on function public.is_location_paused(uuid, uuid) is
  '특정 관계 그룹에서 대상의 위치 공유가 지금 일시중지(paused_until > now()) 중인지 판별. 본인 자신을 조회하면 그 그룹의 mode/멤버십과 무관하게 항상 값을 반환한다(get_share_mode와 동일한 게이팅 구조, v0.2 2차 수정). 그 외에는 호출자가 그 그룹의 멤버가 아니거나, mode가 off거나, owner가 이미 그 그룹을 나갔으면 NULL.';

revoke all on function public.is_location_paused(uuid, uuid) from public;
grant execute on function public.is_location_paused(uuid, uuid) to authenticated;
