import 'package:flutter/material.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../location/settings/share_settings_screen.dart';
import '../../../relationships/presentation/screens/group_list_screen.dart';

/// 로그인 완료 후 보여주는 홈 화면.
///
/// 버킷리스트, 스토리 업로드 UI는 다음 라운드에서 이 화면에 추가된다.
/// 위치 공유 설정 진입점은 이번 라운드에 추가했다. 그룹별 위치 지도 보기는
/// 그룹 상세 화면(`group_detail_screen.dart`)에 있다 — 지도는 특정 그룹을
/// 전제로 하므로 그룹 컨텍스트가 이미 있는 화면에 두는 것이 자연스럽다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepository = AuthRepository();
    final email = authRepository.currentUser?.email ?? '알 수 없음';

    return Scaffold(
      appBar: AppBar(
        title: const Text('곁에'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () => authRepository.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, size: 48),
            const SizedBox(height: 16),
            Text('$email 님, 환영합니다.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.groups),
              label: const Text('관계 그룹 보기'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GroupListScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('위치 공유 설정'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ShareSettingsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '버킷리스트, 스토리 업로드 기능은 다음 라운드에서 추가됩니다.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
