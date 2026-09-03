/// GoTrue(supabase_flutter auth)가 로그인/회원가입 경로에서 던지는 예외를
/// 사용자 문구로 바꾸기 위한 화이트리스트(Din UX 리뷰 P0-8 카피 확정,
/// 2026-09-02). 이 표에 없는 메시지는 `mapServerErrorMessage`가 호출부의
/// `fallback`으로 덮는다 — 서버·GoTrue 원문(영어 메시지, 에러 코드 문자열)이
/// 화면에 그대로 노출되는 경로를 한 군데로 모으는 P0-4/P0-5/P0-7 계약을 잇는다.
///
/// ## 호출부에서 넘기는 문자열
/// `AuthException.message` 텍스트는 GoTrue 버전에 따라 바뀌어 안정 계약이
/// 아니다. `supabase_flutter ^2.8.0`부터 `AuthException.code`(스네이크케이스
/// 안정 식별자, 예: `invalid_credentials`)가 있으므로 호출부는
/// `'${e.code ?? ''} ${e.message}'` 를 `mapServerErrorMessage`에 넘긴다. 아래
/// 키는 코드형(`invalid_credentials`)과 문구형(`invalid login credentials`)을
/// 둘 다 등록해 어느 쪽이 들어와도 소문자 `contains`로 매칭된다.
///
/// ## 표 밖에서 먼저 분기하는 것
/// 네트워크 예외(`AuthRetryableFetchException` — GoTrue 5xx/타임아웃/host
/// lookup 실패)는 메시지가 플랫폼 원문이라 표로 못 잡는다. 호출부에서
/// `if (e is AuthRetryableFetchException)` 로 먼저 분기해 [authNetworkError]를
/// 쓴다.
///
/// ## 로그인 실패는 계정 열거 오라클이 되지 않게 한다
/// "이메일 미등록"과 "비밀번호 틀림"을 절대 구분하지 않는다. GoTrue의
/// `invalid_credentials`는 두 경우를 뭉뚱그린 하나의 코드이고, 우리 문구도
/// 항상 하나뿐이다.
///
/// 삽입 순서 = 검사 순서(첫 매칭 채택). 구체적인 키를 앞에 둔다.
library;

const _alreadyRegistered = '이미 가입된 이메일이에요. 로그인해주세요.';
const _rateLimited = '요청이 많아요. 잠시 후 다시 시도해주세요.';

const authServerErrors = <String, String>{
  'email not confirmed':
      '아직 메일 인증이 안 끝났어요. 가입할 때 보내드린 메일에서 인증 링크를 눌러주세요.',
  'email_not_confirmed':
      '아직 메일 인증이 안 끝났어요. 가입할 때 보내드린 메일에서 인증 링크를 눌러주세요.',
  'invalid login credentials': '이메일 또는 비밀번호가 올바르지 않아요.',
  'invalid_credentials': '이메일 또는 비밀번호가 올바르지 않아요.',
  'user_banned': '로그인할 수 없는 계정이에요. 도움이 필요하면 문의해주세요.',
  'user is banned': '로그인할 수 없는 계정이에요. 도움이 필요하면 문의해주세요.',
  'already registered': _alreadyRegistered,
  'been registered': _alreadyRegistered,
  'user_already_exists': _alreadyRegistered,
  'email_exists': _alreadyRegistered,
  'weak_password': '비밀번호가 너무 단순해요. 다른 비밀번호로 다시 시도해주세요.',
  'weak password': '비밀번호가 너무 단순해요. 다른 비밀번호로 다시 시도해주세요.',
  'password is known to be weak': '비밀번호가 너무 단순해요. 다른 비밀번호로 다시 시도해주세요.',
  'password should be at least': '비밀번호가 조건에 맞지 않아요. 6자 이상으로 다시 입력해주세요.',
  'password should contain': '비밀번호가 조건에 맞지 않아요. 6자 이상으로 다시 입력해주세요.',
  'email_address_invalid': '이메일 주소 형식을 다시 확인해주세요.',
  'unable to validate email address': '이메일 주소 형식을 다시 확인해주세요.',
  'invalid format': '이메일 주소 형식을 다시 확인해주세요.',
  'signup_disabled': '지금은 새로 가입할 수 없어요. 잠시 후 다시 시도해주세요.',
  'signups not allowed': '지금은 새로 가입할 수 없어요. 잠시 후 다시 시도해주세요.',
  'over_email_send_rate_limit': '인증 메일을 너무 자주 보냈어요. 잠시 후 다시 시도해주세요.',
  'email rate limit exceeded': '인증 메일을 너무 자주 보냈어요. 잠시 후 다시 시도해주세요.',
  'over_request_rate_limit': _rateLimited,
  'request this after': _rateLimited,
  'too many requests': _rateLimited,
  'captcha_failed': '확인에 실패했어요. 잠시 후 다시 시도해주세요.',
  'captcha protection': '확인에 실패했어요. 잠시 후 다시 시도해주세요.',
};

/// `AuthRetryableFetchException`(네트워크 계층 실패)용 문구. 표 매칭 대상이
/// 아니라 호출부에서 타입으로 먼저 분기해 쓴다.
const authNetworkError = '연결 상태가 좋지 않아요. 인터넷 연결을 확인하고 다시 시도해주세요.';
