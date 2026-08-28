/// `set_location_share_mode` RPC가 `raise exception`으로 던지는 서버 메시지
/// 전수 조사 결과(Din UX 리뷰 P0-5). 위치 공유 설정 화면의 모드 변경/일시중지/
/// 재개 경로에서 이 표에 없는 메시지는 `mapServerErrorMessage`가 호출부의
/// `fallback`으로 덮는다 — 매칭 실패가 곧 원문 노출로 이어지지 않도록.
///
/// 이 화면 경로로 실제 도달 가능한 건 `not a member of this group` 하나뿐이고
/// 나머지는 방어적으로만 둔다.
const shareSettingsServerErrors = <String, String>{
  'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
  'not a member of this group': '더 이상 이 그룹의 멤버가 아니에요.',
  'invalid mode:': '선택할 수 없는 모드예요. 다시 시도해주세요.',
  'pause_minutes must be a positive integer': '일시중지 시간을 다시 선택해주세요.',
};
