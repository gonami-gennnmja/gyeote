import 'package:flutter/material.dart';

/// AuthGate가 최초 auth 상태(세션 유무)를 아직 확인하지 못했을 때 보여주는 화면.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
