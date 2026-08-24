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
        message: '현재 위치 공유가 꺼져 있어요. 아무에게도 보이지 않습니다.',
      );
    }

    final sharingGroups = groups.where((group) {
      final setting = settingsByGroup[group.id];
      return setting != null && !setting.isOff;
    }).toList();

    if (sharingGroups.isEmpty) {
      return const ShareStatusSummary(
        tone: ShareStatusTone.collectingOnly,
        message: '위치 수집은 켜져 있지만, 아직 공유 중인 그룹이 없어요. 아래에서 그룹을 선택해주세요.',
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
