import 'package:supabase_flutter/supabase_flutter.dart';

/// PostgREST가 전달한 서버 예외 메시지를, 미리 정의한 [whitelist]에 있으면
/// 사용자용 한글 문구로 바꾸고 **없으면 무조건 [fallback]으로 덮는다.**
///
/// 서버가 던진 원문(영어 메시지, PostgREST 코드, 내부 함수명)이 화면에 그대로
/// 노출되는 경로를 한 군데에서 차단하기 위한 유일한 진입점이다(Din UX 리뷰
/// P0-4/P0-5/P0-7). 도메인마다 다른 것은 [whitelist]의 *내용*뿐이고, "매칭
/// 방식(소문자 `contains`) + 매칭 실패 시 폴백 보장"은 이 함수 하나로만
/// 존재한다 — 도메인별로 비슷한 함수를 복제하지 말 것. 복제하면 안전장치가
/// 두 벌이 되고 나중에 한쪽만 고쳐질 때 다른 쪽으로 원문이 샌다.
///
/// 판별이 문자열 `contains`인 이유: 백엔드가 아직 전용 에러 코드(errcode/
/// detail)를 정의하지 않아, plain `raise exception` 메시지 매칭이 현재로선
/// 유일한 수단이다. 백엔드가 에러 코드를 붙이면 이 함수의 매칭만 코드 기반으로
/// 바꾸면 되고 호출부와 도메인 데이터는 그대로 둘 수 있다.
///
/// [whitelist]는 삽입 순서대로 검사된다(첫 매칭 채택). 한 키가 다른 키의
/// 부분문자열이면 더 구체적인 것을 앞에 둘 것.
///
/// 참고: `LocationRepository._isAllSharesOffError()`도 같은 "소문자 `contains`"
/// 관행을 쓰지만 그건 메시지 *매핑*이 아니라 정상 상태 여부의 *불리언 판별*이라
/// 목적이 달라 이 함수로 합치지 않는다 — 관행만 같다.
String mapServerErrorMessage(
  PostgrestException e, {
  required Map<String, String> whitelist,
  required String fallback,
}) {
  final message = e.message.toLowerCase();
  for (final entry in whitelist.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  return fallback;
}
