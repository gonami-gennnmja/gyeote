/// 관계 그룹 RPC(`create_relationship_invitation`, `remove_relationship_member`,
/// `leave_relationship_group`)가 `raise exception`으로 던지는 서버 메시지
/// 전수 조사 결과(Din UX 리뷰 P0-7). 그룹 상세 화면의 초대 생성/멤버 내보내기/
/// 그룹 나가기 경로에서 이 표에 없는 메시지는 `mapServerErrorMessage`가
/// 호출부의 `fallback`으로 덮는다 — 서버 원문(영어 메시지, 내부 함수명 등)이
/// 스낵바에 그대로 노출되지 않도록.
///
/// 실사용 시나리오에서 실제로 도달 가능한 건 `not a member of this group`
/// (화면을 열어둔 채 다른 기기/멤버가 나를 내보낸 경우)뿐이고, 나머지는
/// 방어적으로만 둔다.
const relationshipGroupServerErrors = <String, String>{
  'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
  'only members of the group can create invitations':
      '이 그룹의 멤버만 초대 코드를 만들 수 있어요.',
  'not a member of this group': '더 이상 이 그룹의 멤버가 아니에요.',
  'only the group owner can remove members':
      '그룹을 만든 사람만 멤버를 내보낼 수 있어요.',
  'use leave_relationship_group': '자기 자신은 "그룹 탈퇴"로 나가야 해요.',
};
