import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env_config.dart';
import 'core/routing/app_router.dart';
import 'core/supabase/supabase_client.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EnvConfig.load();
  await SupabaseService.initialize();

  runApp(const GyeoteApp());
}

class GyeoteApp extends StatelessWidget {
  const GyeoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '곁에',
      debugShowCheckedModeBanner: false,
      // 로고 2B(2026-09-14, e2920d1) 반영 — 인디고 `#3B4272`(파형/구조)로 시드
      // 변경. 로즈 `#D4685E`(하트/애정)를 시드로 잡으면 M3가 모든 버튼·선택
      // 상태에 그 색을 퍼뜨려 "하트는 희소하게"라는 로고의 역할 분리 논리가
      // UI에서 무너진다. 인디고를 시드로 두면 상시 노출되는 크롬은 차분하게
      // 가라앉고, 로즈는 M3가 파생하는 tertiary 자리에 남는다(자세한 근거:
      // docs/design/v0.1-release-assets.md §1-5). 아이콘 배경(1-1)과 같은
      // 값이라 스토어 아이콘 -> 앱 실행 -> UI 색이 끊기지 않는다.
      // fromSeed가 파생한 tertiary가 로즈감이 부족하면
      // `.copyWith(tertiary: const Color(0xFFD4685E))`로 override하는 것도
      // 문서에 옵션으로 적혀 있다 — 1차는 순수 fromSeed로 두고 눈으로 확인.
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B4272),
        useMaterial3: true,
      ),
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: const AuthGate(),
    );
  }
}

/// 로그인 여부에 따라 로그인 화면 / (임시) 홈 화면으로 라우팅하는 최상위 위젯.
///
/// Supabase의 `onAuthStateChange` 스트림을 구독해, 로그인/로그아웃/토큰 갱신 등
/// 어떤 이유로든 세션 상태가 바뀌면 자동으로 화면을 전환한다. 최초 스트림 이벤트가
/// 도착하기 전에는 이미 저장된 세션(`currentSession`)이 있는지로 우선 판단하고,
/// 그마저도 없으면 스플래시 화면을 보여준다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepository = AuthRepository();

    return StreamBuilder<AuthState>(
      stream: authRepository.authStateChanges,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? authRepository.currentSession;

        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const SplashScreen();
        }

        if (session != null) {
          return const HomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
