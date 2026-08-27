import 'package:flutter/material.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../location/collector/location_collector_service.dart';
import '../../../location/data/location_repository.dart';
import '../../../location/data/models/location_share_setting.dart';
import '../../../location/settings/share_settings_screen.dart';
import '../../../location/share_status_summary.dart';
import '../../../relationships/data/models/relationship_group.dart';
import '../../../relationships/data/relationship_repository.dart';
import '../../../relationships/presentation/screens/group_list_screen.dart';

/// 로그인 완료 후 보여주는 홈 화면.
///
/// 버킷리스트, 스토리 업로드 UI는 다음 라운드에서 이 화면에 추가된다.
/// 위치 공유 설정 진입점은 이번 라운드에 추가했다. 그룹별 위치 지도 보기는
/// 그룹 상세 화면(`group_detail_screen.dart`)에 있다 — 지도는 특정 그룹을
/// 전제로 하므로 그룹 컨텍스트가 이미 있는 화면에 두는 것이 자연스럽다.
///
/// "위치 공유 설정" 버튼 아래 상태 캡션은 P0-1(공유 설정 화면 배너)에서
/// 뽑아둔 `ShareStatusSummary.compute()`를 그대로 재사용한다(Din UX 리뷰
/// P1-6) — 계산을 새로 만들지 않고 그러려고 분리해둔 헬퍼를 그대로 쓴다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authRepository = AuthRepository();
  final _relationshipRepository = RelationshipRepository();
  final _locationRepository = LocationRepository();
  final _collector = LocationCollectorService.instance;

  late Future<_ShareStatusData> _shareStatusFuture;

  @override
  void initState() {
    super.initState();
    _shareStatusFuture = _loadShareStatus();
  }

  Future<_ShareStatusData> _loadShareStatus() async {
    final results = await Future.wait([
      _relationshipRepository.fetchMyGroups(),
      _locationRepository.fetchMyShareSettings(),
    ]);

    final groups = results[0] as List<RelationshipGroup>;
    final settings = results[1] as List<LocationShareSetting>;
    final settingsByGroup = {
      for (final s in settings) s.relationshipGroupId: s,
    };

    return _ShareStatusData(groups: groups, settingsByGroup: settingsByGroup);
  }

  Future<void> _openShareSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShareSettingsScreen()),
    );
    // 설정 화면에서 모드/일시중지를 바꾸고 돌아왔을 수 있으니 캡션을 새로
    // 불러온다 — 안 그러면 실제 공유 상태와 홈 화면 캡션이 어긋난다.
    if (mounted) setState(() => _shareStatusFuture = _loadShareStatus());
  }

  @override
  Widget build(BuildContext context) {
    final email = _authRepository.currentUser?.email ?? '알 수 없음';

    return Scaffold(
      appBar: AppBar(
        title: const Text('곁에'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () => _authRepository.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, size: 48),
            const SizedBox(height: 16),
            Text('$email 님, 환영해요.'),
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
              onPressed: _openShareSettings,
            ),
            FutureBuilder<_ShareStatusData>(
              future: _shareStatusFuture,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) return const SizedBox.shrink();

                final summary = ShareStatusSummary.compute(
                  groups: data.groups,
                  settingsByGroup: data.settingsByGroup,
                  collectorRunning: _collector.isRunning,
                );

                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    summary.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '버킷리스트, 스토리 업로드는 다음 업데이트에서 추가될 예정이에요.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareStatusData {
  const _ShareStatusData({required this.groups, required this.settingsByGroup});

  final List<RelationshipGroup> groups;
  final Map<String, LocationShareSetting> settingsByGroup;
}
