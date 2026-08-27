import 'package:flutter/material.dart';

import 'location_permission_service.dart';

/// 위치 권한을 요청하기 전에 보여주는 사전 설명 화면.
///
/// 플로우: 설명 화면 -> "위치 권한 허용" 버튼 -> OS 권한 다이얼로그 ->
///   - 허용되면 `Navigator.pop(true)`로 이 화면을 닫고 호출자에게 성공을 알림.
///   - 거부(다시 물어볼 수 있음)면 이 화면에 머무르며 안내 문구를 보여줌.
///   - 영구 거부면 "설정 앱으로 이동" 버튼을 보여줌.
///   - 위치 서비스(OS 전역 설정) 자체가 꺼져 있으면 위치 설정 화면으로 유도.
///
/// 호출자는 `Navigator.push`의 반환값(`bool?`)으로 권한 획득 성공 여부를 알 수
/// 있다. 위치 공유가 필요한 화면(공유 설정, 지도, 수집 시작 등) 진입 전에
/// 이 화면을 거치도록 한다.
class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  final _service = const LocationPermissionService();

  bool _isRequesting = false;
  LocationPermissionResult? _lastResult;

  Future<void> _requestPermission() async {
    setState(() => _isRequesting = true);
    try {
      final result = await _service.requestWhileInUse();
      setState(() => _lastResult = result);

      if (!mounted) return;

      if (result == LocationPermissionResult.grantedWhileInUse ||
          result == LocationPermissionResult.grantedAlways) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  Future<void> _openSettings() => _service.openAppSettings();

  Future<void> _openLocationSettings() => _service.openLocationSettings();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('위치 권한')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.location_on, size: 64),
            const SizedBox(height: 16),
            Text(
              '가족·연인·친구와 실시간 위치를 공유하려면\n위치 권한이 필요해요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              '• 그룹별로 공유 대상과 정밀도(정밀/대략)를 직접 설정할 수 있어요.\n'
              '• 언제든지 공유 설정 화면에서 공유를 끌 수 있어요.\n'
              '• 위치는 공유를 켠 그룹의 멤버에게만 보여요.\n'
              '• 지금은 앱이 켜져 있을 때만 위치가 전달돼요. 앱을 완전히 끄면\n'
              '  위치 공유가 잠시 멈춰요. (백그라운드 공유는 다음 업데이트 예정)',
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 24),
            if (_lastResult == LocationPermissionResult.serviceDisabled) ...[
              const _StatusBanner(
                icon: Icons.location_off,
                message: '기기의 위치 서비스가 꺼져 있어요. 아래 "위치 서비스 설정 열기"에서 위치를 켜주세요.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _openLocationSettings,
                child: const Text('위치 서비스 설정 열기'),
              ),
              const SizedBox(height: 12),
            ] else if (_lastResult ==
                LocationPermissionResult.permanentlyDenied) ...[
              const _StatusBanner(
                icon: Icons.block,
                message: '위치 권한이 꺼져 있어요. 아래 "설정 앱 열기"를 눌러 권한 > 위치를 허용해주세요.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _openSettings,
                child: const Text('설정 앱 열기'),
              ),
              const SizedBox(height: 12),
            ] else if (_lastResult == LocationPermissionResult.denied) ...[
              const _StatusBanner(
                icon: Icons.info_outline,
                message: '위치 권한이 거부됐어요. 아래 "위치 권한 다시 요청" '
                    '버튼으로 한 번 더 요청할 수 있어요.',
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              icon: const Icon(Icons.my_location),
              // denied 상태에서는 라벨을 "다시 요청"으로 바꿔서 바로 위
              // 배너 문구("아래 \"위치 권한 다시 요청\" 버튼으로…")와 말이
              // 연결되게 한다(Din UX 리뷰 P1-4).
              label: Text(
                _isRequesting
                    ? '요청 중…'
                    : (_lastResult == LocationPermissionResult.denied
                        ? '위치 권한 다시 요청'
                        : '위치 권한 허용'),
              ),
              onPressed: _isRequesting ? null : _requestPermission,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('나중에 하기'),
            ),
            const SizedBox(height: 4),
            Text(
              '지금 건너뛰면 위치 공유 기능을 쓸 수 없어요. '
              '나중에 홈 화면의 "위치 공유 설정"에서 언제든 다시 켤 수 있어요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
