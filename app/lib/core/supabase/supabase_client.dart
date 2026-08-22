import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';

/// Supabase 초기화 및 client 접근을 담당하는 서비스.
///
/// 인증(Auth)만 이번 라운드에서 사용하며, Realtime/PostGIS 관련 기능은 관계 모델과
/// 위치 공유 스키마가 백엔드에서 확정된 다음 라운드에서 추가한다.
class SupabaseService {
  SupabaseService._();

  static bool _initialized = false;

  /// 앱 시작 시 한 번 호출한다. [EnvConfig.load]가 먼저 호출되어 있어야 한다.
  static Future<void> initialize() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;
}
