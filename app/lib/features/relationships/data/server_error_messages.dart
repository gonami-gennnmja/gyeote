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

/// `create_relationship_group` RPC가 던지는 서버 메시지(Din UX 리뷰 P0-8,
/// Dexa 전수 조사 2026-09-02). 그룹 생성 화면에서 이 표에 없는 메시지는
/// `mapServerErrorMessage`가 호출부의 `fallback`으로 덮는다.
///
/// 이 RPC의 `raise exception`은 `authentication required` 하나뿐이다(세션이
/// 화면을 열어둔 사이 만료된 경우 도달). 타입 enum 오입력
/// (`invalid input value for enum relationship_type`)은 타입 피커로 통제되는
/// 값이라 정상 UI로는 도달 불가 — 화이트리스트에 넣지 않고 폴백으로 덮는다
/// (P0-5부터 지켜온 "실제 도달 가능한 키만" 기준).
const groupCreateServerErrors = <String, String>{
  'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
};

/// 초대 미리보기(`get_invitation_preview`) / 수락(`accept_relationship_invitation`)
/// 경로가 던지는 서버 메시지(Din UX 리뷰 P0-8, Dexa 전수 조사 2026-09-02).
/// `invitation_accept_screen`의 두 경로 모두 이 표 하나로 처리한다 — 예전엔
/// 미리보기는 원문 직행, 수락은 별도 `_friendlyAcceptError`(폴백이 원문 return)
/// 라 한 화면에서 문구 품질이 갈렸다. P0-8이 둘을 `mapServerErrorMessage` +
/// 이 화이트리스트로 통일했다.
///
/// `get_invitation_preview`는 순수 SELECT라 `raise exception`이 0건이고,
/// 유효하지 않은 코드는 예외가 아니라 0행으로 온다(그건 repository에서
/// `RelationshipException('존재하지 않는 초대 코드예요.')`로 이미 처리). 따라서
/// 미리보기 경로의 `PostgrestException`은 전부 인프라 계층이며 폴백으로 덮인다.
///
/// 수락 경로의 6개 메시지는 `accept_relationship_invitation`(마이그레이션
/// 100001이 최종 정의)에서 전수 확인했다. `invitation is not pending (status: %)`
/// 는 `%`에 status enum(accepted/expired/revoked)이 치환되므로 부분일치 키를
/// 쓴다.
const invitationServerErrors = <String, String>{
  'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
  'invitation not found': '존재하지 않는 초대 코드예요.',
  'invitation is not pending': '이미 처리됐거나 취소된 초대예요.',
  'invitation has expired': '만료된 초대예요.',
  'invitation is scoped to a different email address':
      '초대받은 이메일 계정으로 로그인해야 참여할 수 있어요.',
  'already a member of this group': '이미 이 그룹의 멤버예요.',
};
