import 'package:flutter/material.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';

/// 라우트 이름 상수.
///
/// 로그인 여부에 따른 최상위 분기(로그인 화면 vs 홈 화면)는 [AuthGate]
/// (`lib/main.dart`)가 Supabase auth state 스트림을 구독해 직접 처리하므로,
/// 이 라우터는 인증 플로우 내부 화면 전환(로그인 <-> 회원가입)과 임시 홈 화면
/// 진입에만 사용한다.
abstract class AppRoutes {
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
}

class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
      case AppRoutes.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case AppRoutes.login:
      default:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
    }
  }
}
