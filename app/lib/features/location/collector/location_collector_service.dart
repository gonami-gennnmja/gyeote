import 'dart:async';
import 'dart:developer' as developer;

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../data/location_repository.dart';

/// 위치를 지속적으로 수집해 서버에 전송하는 서비스.
///
/// 이동 상태에 따른 적응형 전송 주기:
///   - stationary(정지): 5분
///   - walking(도보 수준 속도): 1분
///   - moving(차량 등 빠른 이동): 20초
///
/// 판단 기준은 `Position.speed`(m/s, geolocator가 OS 위치 API로부터 제공)를
/// 단순 임계값으로 나눈 것이다. 실제 기기에서 GPS 노이즈로 값이 튈 수 있어
/// 다음 라운드에서 스무딩(예: 최근 N개 speed의 이동평균)을 고려할 만하다.
///
/// 스트림 자체는 `distanceFilter`로 최소 이동 거리 미만은 걸러내고, 그 위에
/// 이 서비스가 "마지막 전송 후 최소 이 시간만큼 지나야 다시 보낸다"는 하한
/// 주기를 얹어 적응형 전송을 구현한다(그 반대인 "정지 상태에서도 주기적으로
/// 최소 한 번은 보낸다"는 별도 heartbeat 타이머로 보완).
///
/// 오프라인 큐(다음 라운드 과제): 전송이 실패했을 때(네트워크 끊김 등) 이번
/// 라운드는 SQLite 등 영속 큐를 두지 않는다. 대신 실패 시 "마지막 전송 성공
/// 시각"을 갱신하지 않아, 다음 위치 갱신이 오면 최소 주기 제약이 지나는 대로
/// 다시 시도된다. 앱이 완전히 종료되거나 장시간 오프라인이었던 구간의 위치는
/// 유실될 수 있다 — 영속 큐(SQLite) 도입은 다음 라운드로 명시적으로 남긴다.
class LocationCollectorService {
  LocationCollectorService({
    LocationRepository? repository,
    Battery? battery,
  }) : _repository = repository ?? LocationRepository(),
       _battery = battery ?? Battery();

  /// 앱 전역에서 단일 인스턴스를 공유한다(`SupabaseService`와 동일한 static
  /// 싱글턴 컨벤션). 화면(위젯) 단위로 새 인스턴스를 만들면 화면을 벗어났다
  /// 돌아왔을 때 `isRunning` 등 실행 상태를 잃어버리므로, 수집기는 반드시 이
  /// 인스턴스를 통해서만 시작/중지해야 한다.
  static final LocationCollectorService instance = LocationCollectorService();

  final LocationRepository _repository;
  final Battery _battery;

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeatTimer;

  DateTime? _lastSentAt;
  String _lastMovementState = 'stationary';
  bool _isSending = false;

  bool get isRunning => _positionSub != null;

  String get lastMovementState => _lastMovementState;

  /// 위치 스트림 구독을 시작한다. 권한/서비스 확인은 호출자가
  /// `LocationPermissionService`로 먼저 처리했다고 가정한다(이 서비스는
  /// 권한이 없으면 스트림 구독 자체가 실패하거나 빈 스트림이 되므로 조용히
  /// 아무 것도 하지 않는다).
  Future<void> start() async {
    if (_positionSub != null) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_onPosition, onError: (_) {/* 스트림 에러는 다음 이벤트로 자연 복구 시도 */});

    // 정지 상태로 오래 머물러 distanceFilter 때문에 스트림 이벤트 자체가 뜸해질
    // 때도, 최소한 정지 주기(5분)마다 한 번은 배터리/상태 정보를 최신화해
    // 보내기 위한 heartbeat.
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        await _onPosition(last, forceSend: true);
      }
    });
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _onPosition(Position position, {bool forceSend = false}) async {
    final movementState = _classifyMovement(position);
    _lastMovementState = movementState;

    if (!forceSend) {
      final minInterval = _minIntervalFor(movementState);
      final lastSentAt = _lastSentAt;
      if (lastSentAt != null &&
          DateTime.now().difference(lastSentAt) < minInterval) {
        return;
      }
    }

    await _send(position, movementState);
  }

  String _classifyMovement(Position position) {
    final speed = position.speed.isFinite ? position.speed : 0.0;
    if (speed < 0.3) return 'stationary';
    if (speed < 1.5) return 'walking';
    return 'moving';
  }

  Duration _minIntervalFor(String movementState) {
    switch (movementState) {
      case 'moving':
        return const Duration(seconds: 20);
      case 'walking':
        return const Duration(minutes: 1);
      case 'stationary':
      default:
        return const Duration(minutes: 5);
    }
  }

  Future<void> _send(Position position, String movementState) async {
    if (_isSending) return;
    _isSending = true;
    try {
      int? batteryLevel;
      bool? isCharging;
      try {
        batteryLevel = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        isCharging =
            state == BatteryState.charging || state == BatteryState.full;
      } catch (_) {
        // 배터리 정보 조회 실패(일부 플랫폼/에뮬레이터)는 위치 전송을 막을
        // 이유가 아니므로 null로 두고 계속 진행.
      }

      final sent = await _repository.upsertLocationPing(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        movementState: movementState,
        capturedAt: position.timestamp,
      );

      if (sent) {
        _lastSentAt = DateTime.now();
      }
      // sent == false: 모든 그룹에서 공유가 OFF라 서버가 조용히 거부한 것
      // (upsert_location_ping 계약, LocationRepository에서 이미 필터링됨).
      // 사용자가 의도적으로 꺼둔 상태이므로 에러로 취급하지 않는다.
    } on Exception catch (e, stackTrace) {
      // 네트워크 오류 등. 위 클래스 doc 참고 — 영속 재시도 큐는 다음 라운드.
      // _lastSentAt을 갱신하지 않으므로 다음 위치 갱신 시 다시 시도된다.
      //
      // 화면에는 표시하지 않지만(수집기는 백그라운드 동작이라 보여줄 화면이
      // 없음) 로그는 반드시 남긴다 — 서버에 새로 추가된 accuracy_m/
      // battery_level 범위 검증처럼 센서·클라이언트 버그를 가리키는 예외까지
      // 이 블록이 흔적 없이 삼키면 디버깅 단서가 전혀 남지 않는다(Rena
      // 재리뷰 지적). location_map_screen._refresh와 동일한 패턴.
      developer.log(
        '위치 핑 전송 실패',
        name: 'LocationCollectorService',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isSending = false;
    }
  }
}
