import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 환경변수(.env) 접근을 한 곳으로 모아두는 유틸리티.
///
/// 가정(assumption): 백엔드(Supabase) 프로젝트의 실제 URL/anon key는 아직 확정되지
/// 않았으므로, `.env`에는 더미 값을 넣어두고 로컬 개발 시 각자 `.env.example`을 복사해
/// 실제 값으로 교체하는 방식을 가정한다. CI 등에서는 `--dart-define`으로 주입하는 값을
/// 우선 사용할 수 있도록 [String.fromEnvironment] fallback도 함께 둔다.
class EnvConfig {
  EnvConfig._();

  static const _dartDefineSupabaseUrl =
      String.fromEnvironment('SUPABASE_URL');
  static const _dartDefineSupabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// `.env` 파일을 로드한다. 앱 시작(main) 시 한 번 호출되어야 한다.
  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
  }

  static String get supabaseUrl {
    if (_dartDefineSupabaseUrl.isNotEmpty) return _dartDefineSupabaseUrl;
    return dotenv.maybeGet('SUPABASE_URL') ?? '';
  }

  static String get supabaseAnonKey {
    if (_dartDefineSupabaseAnonKey.isNotEmpty) {
      return _dartDefineSupabaseAnonKey;
    }
    return dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';
  }
}
