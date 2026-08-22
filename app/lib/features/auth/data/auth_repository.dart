import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// Supabase Auth(이메일/비밀번호) 접근을 감싸는 repository.
///
/// 표준 Supabase Auth API(signInWithPassword / signUp / onAuthStateChange 등)는
/// 안정적인 공개 계약이므로, 백엔드의 관계 모델(커플/가족/친구 그룹) 스키마 확정을
/// 기다리지 않고 바로 사용한다. 회원가입 시 이메일 확인(email confirmation)이
/// 필수인지 여부는 Supabase 프로젝트 설정(백엔드 담당)에 따라 달라질 수 있으므로,
/// 여기서는 "확인 메일이 필요할 수도, 없을 수도 있다"고 가정하고 두 경우 모두
/// 자연스럽게 동작하도록 UI에서 처리한다 (session이 즉시 생기면 AuthGate가 자동으로
/// 홈으로 전환하고, session이 없으면 이메일 확인 안내 메시지를 보여준다).
class AuthRepository {
  AuthRepository({GoTrueClient? auth}) : _auth = auth ?? SupabaseService.auth;

  final GoTrueClient _auth;

  /// 로그인/로그아웃 등 인증 상태 변화 스트림.
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// 현재 세션 (앱 시작 시 이미 로그인되어 있는지 확인할 때 사용).
  Session? get currentSession => _auth.currentSession;

  User? get currentUser => _auth.currentUser;

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _auth.signUp(email: email, password: password);
  }

  Future<void> signOut() {
    return _auth.signOut();
  }
}
