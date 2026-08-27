import 'geo_point.dart';

/// `get_peer_locations()` RPC의 한 행 (상대방의 최신 위치 스냅샷).
class PeerLocation {
  const PeerLocation({
    required this.userId,
    required this.nickname,
    required this.position,
    required this.accuracyM,
    required this.batteryLevel,
    required this.isCharging,
    required this.movementState,
    required this.capturedAt,
    required this.receivedAt,
    required this.mode,
  });

  factory PeerLocation.fromJson(Map<String, dynamic> json) {
    return PeerLocation(
      userId: json['user_id'] as String,
      nickname: json['nickname'] as String? ?? '알 수 없음',
      position: GeoPoint.parse(json['location']),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      batteryLevel: json['battery_level'] as int?,
      isCharging: json['is_charging'] as bool?,
      movementState: json['movement_state'] as String?,
      capturedAt: DateTime.parse(json['captured_at'] as String),
      receivedAt: DateTime.parse(json['received_at'] as String),
      mode: json['mode'] as String? ?? 'off',
    );
  }

  final String userId;
  final String nickname;
  final GeoPoint position;
  final double? accuracyM;
  final int? batteryLevel;
  final bool? isCharging;
  final String? movementState;
  final DateTime capturedAt;
  final DateTime receivedAt;

  /// 'off' | 'precise' | 'approx'. `get_peer_locations`가 이미 RLS로 볼 수
  /// 있는 상대만 반환하므로 실질적으로 'precise'/'approx'만 오지만, 방어적으로
  /// 문자열 그대로 보관한다.
  final String mode;

  bool get isApprox => mode == 'approx';

  /// `receivedAt` 기준 이 시간 이상 지나면 "오래된 위치"로 간주해 지도
  /// 마커/피어 칩에서 시각적으로 톤다운한다(Din UX 리뷰 P1-3) — 텍스트
  /// (`freshnessLabel()`)만으로는 지도를 훑어볼 때 오래된 위치도 방금 위치와
  /// 똑같아 보여 "지금 여기 있다"고 오해하기 쉽다는 지적에 대한 대응이다.
  static const staleThreshold = Duration(minutes: 30);

  /// stale로 판정된 피어를 지도에서 톤다운할 때 쓰는 불투명도. 마커 alpha와
  /// 피어 칩 배경(불투명색으로 합성)이 같은 값을 참조하도록 여기 하나로
  /// 모아둔다(Rena 리뷰 nit — 두 곳에 매직넘버 0.55/0.5가 따로 있어 "오래돼
  /// 보이는 정도"가 어긋났다).
  static const staleOpacity = 0.55;

  /// [staleThreshold] 이상 지났는지 여부. `freshnessLabel()`과 같은 방식으로
  /// `now`를 주입받을 수 있어(기본값은 현재 시각) 위젯 없이 바로 테스트할 수
  /// 있다.
  bool isStale({DateTime? now}) {
    final reference = now ?? DateTime.now().toUtc();
    final diff = reference.difference(receivedAt.toUtc());
    return !diff.isNegative && diff >= staleThreshold;
  }

  /// realtime 브로드캐스트 delta로 이 스냅샷을 갱신한 새 인스턴스를 만든다.
  PeerLocation copyWithRealtime({
    required GeoPoint position,
    double? accuracyM,
    int? batteryLevel,
    bool? isCharging,
    String? movementState,
    required DateTime capturedAt,
    required DateTime receivedAt,
    required String mode,
  }) {
    return PeerLocation(
      userId: userId,
      nickname: nickname,
      position: position,
      accuracyM: accuracyM,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      movementState: movementState,
      capturedAt: capturedAt,
      receivedAt: receivedAt,
      mode: mode,
    );
  }

  /// "n분 전" 등 신선도 표시 문자열. 서버 `received_at` 기준으로 계산한다
  /// (기기 간 시계 오차의 영향을 덜 받는 `captured_at`이 아니라, 서버가 실제로
  /// 이 값을 반영한 시각을 기준으로 하라는 과제 요구사항에 맞춤).
  String freshnessLabel({DateTime? now}) {
    final reference = now ?? DateTime.now().toUtc();
    final diff = reference.difference(receivedAt.toUtc());

    if (diff.isNegative || diff.inSeconds < 60) return '방금 전';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }
}
