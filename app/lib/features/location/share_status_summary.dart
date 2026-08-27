import 'data/models/location_share_setting.dart';
import '../relationships/data/models/relationship_group.dart';
import '../relationships/presentation/widgets/relationship_type_x.dart';

/// "지금 실제로 누구에게 내 위치가 보이는가"를 한 줄로 요약한 결과.
///
/// 실제 공유 여부는 ① 수집 스위치 ON, ② 그룹 모드가 off가 아님, ③ 일시중지
/// 중이 아님 세 조건이 화면 여러 곳(수집 스위치 카드 + 그룹 카드들)에 흩어져
/// 있어 사용자가 직접 조합해야 오해가 생기기 쉽다(Din UX 리뷰 P0-1). 이 계산을
/// `ShareSettingsScreen`과 `HomeScreen`에서 동일하게 재사용하기 위해 분리했다.
enum ShareStatusTone { off, collectingOnly, sharing }

class ShareStatusSummary {
  const ShareStatusSummary({required this.tone, required this.message});

  final ShareStatusTone tone;
  final String message;

  static ShareStatusSummary compute({
    required List<RelationshipGroup> groups,
    required Map<String, LocationShareSetting> settingsByGroup,
    required bool collectorRunning,
  }) {
    if (!collectorRunning) {
      return const ShareStatusSummary(
        tone: ShareStatusTone.off,
        message: '현재 위치 공유가 꺼져 있어요. 아무에게도 보이지 않아요.',
      );
    }

    final sharingGroups = groups.where((group) {
      final setting = settingsByGroup[group.id];
      return setting != null && !setting.isOff;
    }).toList();

    if (sharingGroups.isEmpty) {
      return const ShareStatusSummary(
        tone: ShareStatusTone.collectingOnly,
        message: '내 위치 공유는 켜져 있지만, 공유할 그룹을 아직 안 골랐어요. 아래에서 그룹을 켜주세요.',
      );
    }

    String nameOf(RelationshipGroup group) =>
        group.displayName(group.type.relationshipTypeLabel);

    final names = sharingGroups.map(nameOf).toList();
    final namesText = names.length > 3
        ? '${names.take(3).join(', ')} 외 ${names.length - 3}곳'
        : names.join(', ');

    final pausedNames = sharingGroups
        .where((group) => settingsByGroup[group.id]!.isPaused)
        .map(nameOf)
        .toList();

    final message = StringBuffer('$namesText에게 위치가 공유되고 있어요.');
    if (pausedNames.isNotEmpty) {
      message.write(' (${pausedNames.join(', ')}는 일시중지 중)');
    }

    return ShareStatusSummary(
      tone: ShareStatusTone.sharing,
      message: message.toString(),
    );
  }
}

/// 그룹 카드에서 선택된 공유 모드('off'/'precise'/'approx')에 대한 설명
/// 한 줄(Din UX 리뷰 P1-1). SegmentedButton 레이블만으로는 "정밀"/"대략"의
/// 실질적 차이(정확한 좌표 vs ~100m 격자 반올림)를 알 수 없다는 지적에 대한
/// 대응이다.
String shareModeDescription(String mode) {
  switch (mode) {
    case 'precise':
      return '정확한 위치가 실시간으로 보여요.';
    case 'approx':
      return '실제 위치에서 반경 약 100m 이내로 뭉뚱그려 보여요.';
    case 'off':
    default:
      return '이 그룹에는 내 위치가 전혀 보이지 않아요.';
  }
}

/// 일시중지 종료 시각을 `DateTime.toLocal()` 원본 대신 사람이 읽기 쉬운
/// 형태로 포맷한다(Din UX 리뷰 P1-2) — 오늘 안이면 "오후 3:32까지
/// 일시중지됨", 다음날 이후면 "8/24 오후 3:32까지 일시중지됨" 형태. 프로젝트에
/// `intl` 의존성이 없어 직접 계산한다.
String formatPausedUntil(DateTime pausedUntil, {DateTime? now}) {
  final local = pausedUntil.toLocal();
  final reference = now ?? DateTime.now();
  final isToday = local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;

  final period = local.hour < 12 ? '오전' : '오후';
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final timeText = '$period $hour12:$minute';

  final datePrefix = isToday ? '' : '${local.month}/${local.day} ';
  return '$datePrefix$timeText까지 일시중지됨';
}
