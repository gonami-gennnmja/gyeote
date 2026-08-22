import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// 위치 권한/서비스 상태를 화면에서 다루기 쉬운 형태로 단순화한 결과.
enum LocationPermissionResult {
  /// 위치 서비스(OS 설정) 자체가 꺼져 있음 — 권한과 별개.
  serviceDisabled,

  /// 사용자가 거부했지만 다시 물어볼 수 있는 상태.
  denied,

  /// 사용자가 "다시 묻지 않음"과 함께 거부 (iOS는 이전에 한 번이라도 거부하면
  /// 바로 이 상태로 취급되는 경우가 많음) — 설정 앱으로 유도해야 함.
  permanentlyDenied,

  /// "앱 사용 중"만 허용됨. 이번 라운드 기능(포그라운드 위치 공유)은 이 정도로
  /// 충분하다.
  grantedWhileInUse,

  /// 백그라운드에서도 위치 추적 허용("항상 허용").
  grantedAlways,
}

/// `permission_handler` + `geolocator`를 조합해 위치 권한 흐름을 감싼다.
///
/// - 상태 조회/설정 앱 이동: `permission_handler` (영구 거부 판별,
///   `openAppSettings()`가 명확하게 분리되어 있어 다루기 쉬움).
/// - 위치 서비스 on/off 확인 및 실제 위치 스트림: `geolocator`
///   (`collector/location_collector_service.dart` 참고).
class LocationPermissionService {
  const LocationPermissionService();

  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermissionResult> checkStatus() async {
    if (!await isLocationServiceEnabled()) {
      return LocationPermissionResult.serviceDisabled;
    }

    final whileInUse = await Permission.locationWhenInUse.status;
    final always = await Permission.locationAlways.status;

    return _mapStatuses(whileInUse: whileInUse, always: always);
  }

  /// OS 권한 다이얼로그를 띄운다. iOS는 "항상 허용"을 한 번에 요청하지 않는
  /// 것이 권장 패턴이므로, 우선 "앱 사용 중"만 요청한다. 이번 라운드는 앱이
  /// 포그라운드에 있을 때의 위치 공유만 다루므로 이것으로 충분하다(백그라운드
  /// 상시 추적은 범위 밖).
  Future<LocationPermissionResult> requestWhileInUse() async {
    if (!await isLocationServiceEnabled()) {
      return LocationPermissionResult.serviceDisabled;
    }

    final status = await Permission.locationWhenInUse.request();
    final always = await Permission.locationAlways.status;
    return _mapStatuses(whileInUse: status, always: always);
  }

  Future<void> openAppSettings() => openAppSettingsPermissionHandler();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  LocationPermissionResult _mapStatuses({
    required PermissionStatus whileInUse,
    required PermissionStatus always,
  }) {
    if (always.isGranted) return LocationPermissionResult.grantedAlways;
    if (whileInUse.isGranted) return LocationPermissionResult.grantedWhileInUse;
    if (whileInUse.isPermanentlyDenied || always.isPermanentlyDenied) {
      return LocationPermissionResult.permanentlyDenied;
    }
    return LocationPermissionResult.denied;
  }
}

/// `permission_handler` 패키지의 최상위 함수 `openAppSettings()`를 가리키는
/// 래퍼. 클래스 내부 메서드 이름도 `openAppSettings`로 지었기 때문에, 그
/// 메서드 본문에서 그냥 `openAppSettings()`를 호출하면 (최상위 함수가 아니라)
/// 자기 자신을 재귀 호출하게 된다 — 이를 피하기 위해 최상위 함수를 별도
/// 이름으로 한 번 감싼다.
Future<void> openAppSettingsPermissionHandler() => openAppSettings();
