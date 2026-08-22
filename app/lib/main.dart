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
      theme: ThemeData(
        colorSchemeSeed: Colors.pinkAccent,
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
