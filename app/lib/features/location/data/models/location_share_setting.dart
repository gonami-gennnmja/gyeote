/// `location_share_settings` 테이블 한 행 (본인 설정만 조회 가능).
class LocationShareSetting {
  const LocationShareSetting({
    required this.userId,
    required this.relationshipGroupId,
    required this.mode,
    required this.pausedUntil,
  });

  factory LocationShareSetting.fromJson(Map<String, dynamic> json) {
    final pausedUntilRaw = json['paused_until'] as String?;
    return LocationShareSetting(
      userId: json['user_id'] as String,
      relationshipGroupId: json['relationship_group_id'] as String,
      mode: json['mode'] as String? ?? 'off',
      pausedUntil:
          pausedUntilRaw == null ? null : DateTime.parse(pausedUntilRaw),
    );
  }

  /// 해당 그룹에 대한 설정 행이 아직 없는 경우(기본값 'off')를 표현.
  factory LocationShareSetting.off({
    required String userId,
    required String relationshipGroupId,
  }) {
    return LocationShareSetting(
      userId: userId,
      relationshipGroupId: relationshipGroupId,
      mode: 'off',
      pausedUntil: null,
    );
  }

  final String userId;
  final String relationshipGroupId;

  /// 'off' | 'precise' | 'approx'
  final String mode;

  /// null이 아니고 아직 지나지 않았으면 "일시중지 중"으로 취급한다.
  final DateTime? pausedUntil;

  bool get isPaused =>
      pausedUntil != null && pausedUntil!.isAfter(DateTime.now().toUtc());

  bool get isOff => mode == 'off';
}
