import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../relationships/data/models/relationship_group.dart';
import '../../relationships/data/relationship_repository.dart';
import '../../relationships/presentation/widgets/relationship_type_x.dart';
import '../collector/location_collector_service.dart';
import '../data/location_repository.dart';
import '../data/models/location_share_setting.dart';
import '../permission/location_permission_screen.dart';
import '../permission/location_permission_service.dart';
import '../share_status_summary.dart';

/// `set_location_share_mode` RPC가 던지는 서버 원문 예외 메시지를 사용자
/// 대상 한글 문구로 매핑한다(Din UX 리뷰 P0-5).
///
/// `_setMode`/`_pause`/`_resumeNow`가 지금까지 `PostgrestException.message`를
/// 스낵바에 그대로 노출해왔다 — 위치 기능 마이그레이션 전체를 전수 조사한
/// 결과 이 경로로 실제 도달 가능한 서버 메시지는 아래 4개뿐이었다(그중
/// `not a member of this group`만 실사용 시나리오에서 실제로 트리거된다).
/// 화이트리스트에 없는 메시지는 절대 원문을 그대로 흘려보내지 않고 항상
/// 호출부가 넘긴 `fallback`으로 덮는다 — 매칭 실패가 곧 원문 노출로 이어지는
/// 구조를 만들지 않기 위함이다. 판별은 `LocationRepository._isAllSharesOffError()`와
/// 동일하게 `e.message`를 소문자로 바꿔 `contains()`로 매칭한다(백엔드가
/// 전용 에러 코드를 아직 정의하지 않아 문자열 매칭이 현재 유일한 수단).
String _mapShareErrorMessage(PostgrestException e, {required String fallback}) {
  final message = e.message.toLowerCase();

  if (message.contains('authentication required')) {
    return '로그인이 만료됐어요. 다시 로그인해주세요.';
  }
  if (message.contains('not a member of this group')) {
    return '더 이상 이 그룹의 멤버가 아니에요.';
  }
  if (message.contains('invalid mode:')) {
    return '선택할 수 없는 모드예요. 다시 시도해주세요.';
  }
  if (message.contains('pause_minutes must be a positive integer')) {
    return '일시중지 시간을 다시 선택해주세요.';
  }

  return fallback;
}

/// 관계 그룹별 위치 공유 모드(off/precise/approx)를 설정하는 화면.
///
/// - 상단: 내 기기의 위치 수집 자체를 시작/중지하는 스위치. 모든 그룹이
///   'off'여도 이 스위치를 켤 수는 있지만, 이 경우 `upsert_location_ping`이
///   서버에서 조용히 거부되므로(계약대로) 실질적으로는 최소 한 그룹을 켜야
///   의미가 있다 — 안내 문구로 이를 설명한다.
/// - 그룹별 카드: off/precise/approx 선택 + "일시중지"(N분) 옵션.
///
/// 일시중지 해석에 대한 가정은 `LocationRepository.setShareMode` 문서 참고:
/// "N분간 공유 자체를 켜는" 것이 아니라 "이미 켜진 공유를 N분간 숨기는" 것으로
/// 구현했다(백엔드 `paused_until` 스키마와 일치시키기 위함).
class ShareSettingsScreen extends StatefulWidget {
  const ShareSettingsScreen({super.key});

  @override
  State<ShareSettingsScreen> createState() => _ShareSettingsScreenState();
}

class _ShareSettingsScreenState extends State<ShareSettingsScreen> {
  final _relationshipRepository = RelationshipRepository();
  final _locationRepository = LocationRepository();
  final _permissionService = const LocationPermissionService();
  final _collector = LocationCollectorService.instance;

  late Future<_ShareSettingsData> _future;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    // 이 화면을 떠나도 수집기는 백그라운드로 계속 동작해야 하므로 stop()을
    // 호출하지 않는다. 앱 전체 라이프사이클에서 수집기를 언제 멈출지는
    // 다음 라운드에서 별도 전역 상태 관리로 다듬을 부분.
    super.dispose();
  }

  Future<_ShareSettingsData> _load() async {
    final results = await Future.wait([
      _relationshipRepository.fetchMyGroups(),
      _locationRepository.fetchMyShareSettings(),
    ]);

    final groups = results[0] as List<RelationshipGroup>;
    final settings = results[1] as List<LocationShareSetting>;
    final settingsByGroup = {for (final s in settings) s.relationshipGroupId: s};

    return _ShareSettingsData(groups: groups, settingsByGroup: settingsByGroup);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _toggleCollector(bool enable) async {
    if (!enable) {
      await _collector.stop();
      setState(() {});
      return;
    }

    final status = await _permissionService.checkStatus();
    if (!mounted) return;

    final alreadyGranted =
        status == LocationPermissionResult.grantedWhileInUse ||
        status == LocationPermissionResult.grantedAlways;

    if (!alreadyGranted) {
      final granted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LocationPermissionScreen()),
      );
      if (granted != true) return;
    }

    await _collector.start();
    if (mounted) setState(() {});
  }

  Future<void> _setMode({
    required RelationshipGroup group,
    required String mode,
  }) async {
    setState(() => _isMutating = true);
    try {
      await _locationRepository.setShareMode(
        relationshipGroupId: group.id,
        mode: mode,
      );
      _reload();
    } on PostgrestException catch (e) {
      _showSnackBar(_mapShareErrorMessage(
        e,
        fallback: '공유 설정을 변경하지 못했습니다. 다시 시도해주세요.',
      ));
    } catch (e) {
      _showSnackBar('공유 설정을 변경하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _pause({
    required RelationshipGroup group,
    required String currentMode,
    required int minutes,
  }) async {
    setState(() => _isMutating = true);
    try {
      await _locationRepository.setShareMode(
        relationshipGroupId: group.id,
        mode: currentMode,
        pauseMinutes: minutes,
      );
      _showSnackBar('$minutes분 동안 위치 공유를 일시중지합니다.');
      _reload();
    } on PostgrestException catch (e) {
      _showSnackBar(_mapShareErrorMessage(
        e,
        fallback: '일시중지 설정에 실패했습니다. 다시 시도해주세요.',
      ));
    } catch (e) {
      _showSnackBar('일시중지 설정에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _resumeNow({
    required RelationshipGroup group,
    required String currentMode,
  }) async {
    setState(() => _isMutating = true);
    try {
      await _locationRepository.setShareMode(
        relationshipGroupId: group.id,
        mode: currentMode,
      );
      _showSnackBar('공유를 다시 시작합니다.');
      _reload();
    } on PostgrestException catch (e) {
      _showSnackBar(_mapShareErrorMessage(
        e,
        fallback: '공유를 다시 시작하지 못했습니다. 다시 시도해주세요.',
      ));
    } catch (e) {
      _showSnackBar('공유를 다시 시작하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _showPauseSheet(RelationshipGroup group, String currentMode) {
    const options = [15, 30, 60, 120];
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('얼마나 일시중지할까요?'),
            ),
            for (final minutes in options)
              ListTile(
                title: Text('$minutes분'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pause(group: group, currentMode: currentMode, minutes: minutes);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('위치 공유 설정')),
      body: FutureBuilder<_ShareSettingsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
          }

          final data = snapshot.data!;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    title: const Text('내 위치 수집'),
                    subtitle: const Text(
                      '이 기기의 위치를 주기적으로 서버에 전송합니다. '
                      '실제로 상대에게 보이려면 아래에서 최소 한 그룹을 '
                      '"정밀" 또는 "대략"으로 켜야 해요.',
                    ),
                    value: _collector.isRunning,
                    onChanged: _isMutating ? null : _toggleCollector,
                  ),
                ),
                const SizedBox(height: 8),
                _ShareStatusBanner(
                  summary: ShareStatusSummary.compute(
                    groups: data.groups,
                    settingsByGroup: data.settingsByGroup,
                    collectorRunning: _collector.isRunning,
                  ),
                ),
                const SizedBox(height: 16),
                if (data.groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(child: Text('속한 관계 그룹이 없습니다.')),
                  )
                else
                  ...data.groups.map(
                    (group) => _GroupShareCard(
                      group: group,
                      setting: data.settingsByGroup[group.id] ??
                          LocationShareSetting.off(
                            userId: _locationRepository.currentUserId ?? '',
                            relationshipGroupId: group.id,
                          ),
                      isMutating: _isMutating,
                      collectorRunning: _collector.isRunning,
                      onModeSelected: (mode) =>
                          _setMode(group: group, mode: mode),
                      onPauseRequested: (currentMode) =>
                          _showPauseSheet(group, currentMode),
                      onResumeNow: (currentMode) =>
                          _resumeNow(group: group, currentMode: currentMode),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupShareCard extends StatelessWidget {
  const _GroupShareCard({
    required this.group,
    required this.setting,
    required this.isMutating,
    required this.collectorRunning,
    required this.onModeSelected,
    required this.onPauseRequested,
    required this.onResumeNow,
  });

  final RelationshipGroup group;
  final LocationShareSetting setting;
  final bool isMutating;
  final bool collectorRunning;
  final ValueChanged<String> onModeSelected;
  final ValueChanged<String> onPauseRequested;
  final ValueChanged<String> onResumeNow;

  @override
  Widget build(BuildContext context) {
    final typeLabel = group.type.relationshipTypeLabel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(group.type.relationshipTypeIcon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.displayName(typeLabel),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (!collectorRunning) ...[
              const SizedBox(height: 8),
              Text(
                '⚠ 위치 수집이 꺼져 있어 이 설정은 적용되지 않아요.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Opacity(
              opacity: collectorRunning ? 1.0 : 0.6,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'off', label: Text('끄기')),
                  ButtonSegment(value: 'precise', label: Text('정밀')),
                  ButtonSegment(value: 'approx', label: Text('대략')),
                ],
                selected: {setting.mode},
                onSelectionChanged: isMutating
                    ? null
                    : (selection) => onModeSelected(selection.first),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              shareModeDescription(setting.mode),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (!setting.isOff) ...[
              const SizedBox(height: 12),
              if (setting.isPaused)
                Row(
                  children: [
                    const Icon(Icons.pause_circle_outline, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        formatPausedUntil(setting.pausedUntil!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed:
                          isMutating ? null : () => onResumeNow(setting.mode),
                      child: const Text('즉시 재개'),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('N분만 일시중지'),
                    onPressed:
                        isMutating ? null : () => onPauseRequested(setting.mode),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "지금 실제로 누구에게 내 위치가 보이는가"를 요약해 보여주는 배너
/// (Din UX 리뷰 P0-1). 수집 스위치 카드 바로 아래 배치해, 그룹 카드들을
/// 하나하나 조합해 보지 않아도 실제 공유 상태를 한눈에 알 수 있게 한다.
class _ShareStatusBanner extends StatelessWidget {
  const _ShareStatusBanner({required this.summary});

  final ShareStatusSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final IconData icon;
    final Color color;
    switch (summary.tone) {
      case ShareStatusTone.off:
        icon = Icons.visibility_off_outlined;
        color = colorScheme.onSurfaceVariant;
        break;
      case ShareStatusTone.collectingOnly:
        icon = Icons.info_outline;
        color = colorScheme.onSurfaceVariant;
        break;
      case ShareStatusTone.sharing:
        icon = Icons.visibility_outlined;
        color = colorScheme.primary;
        break;
    }

    return Card(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                summary.message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareSettingsData {
  const _ShareSettingsData({required this.groups, required this.settingsByGroup});

  final List<RelationshipGroup> groups;
  final Map<String, LocationShareSetting> settingsByGroup;
}
