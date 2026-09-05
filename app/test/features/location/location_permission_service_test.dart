import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:gyeote/features/location/permission/location_permission_service.dart';

void main() {
  group('LocationPermissionService.mapStatus', () {
    test('허용되면 grantedWhileInUse', () {
      expect(
        LocationPermissionService.mapStatus(PermissionStatus.granted),
        LocationPermissionResult.grantedWhileInUse,
      );
    });

    test('아직 아무것도 안 준 첫 실행(denied)은 denied — 정상 요청 플로우로 간다', () {
      // 회귀 방어: 예전엔 매니페스트에 없는 ACCESS_BACKGROUND_LOCATION을
      // Permission.locationAlways로 조회하면 permanentlyDenied가 돌아와서,
      // whileInUse=denied인 첫 실행 사용자가 permanentlyDenied 분기로 잘못
      // 떨어졌다. v0.1은 always를 아예 보지 않으므로 whileInUse만으로 판정한다.
      expect(
        LocationPermissionService.mapStatus(PermissionStatus.denied),
        LocationPermissionResult.denied,
      );
    });

    test('다시 묻지 않음 거부(permanentlyDenied)만 설정 앱 유도', () {
      expect(
        LocationPermissionService.mapStatus(PermissionStatus.permanentlyDenied),
        LocationPermissionResult.permanentlyDenied,
      );
    });
  });
}
