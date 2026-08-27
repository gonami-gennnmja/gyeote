import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gyeote/features/location/data/models/geo_point.dart';
import 'package:gyeote/features/location/data/models/peer_location.dart';
import 'package:gyeote/features/location/map/location_map_screen.dart';

PeerLocation _peer(
  String userId,
  DateTime receivedAt, {
  String mode = 'precise',
}) {
  return PeerLocation(
    userId: userId,
    nickname: userId,
    position: const GeoPoint(latitude: 37.5, longitude: 127.0),
    accuracyM: 10,
    batteryLevel: 80,
    isCharging: false,
    movementState: 'stationary',
    capturedAt: receivedAt,
    receivedAt: receivedAt,
    mode: mode,
  );
}

Marker _markerFor(Set<Marker> markers, String userId) =>
    markers.firstWhere((m) => m.markerId.value == userId);

void main() {
  group('buildPeerMarkers - stale 톤다운', () {
    // 상대가 앱을 끄면(=브로드캐스트가 멈추면) receivedAt은 그 시점에 고정되고
    // 벽시계(now)만 계속 흐른다. 화면의 1분 주기 타이머는 이 now를
    // buildPeerMarkers에 새로 주입해서 재렌더하는 역할을 하므로, 여기서는
    // "같은 PeerLocation + now만 진행"으로 그 상황을 재현한다.
    final broadcastStopped = DateTime.utc(2026, 8, 27, 9, 0, 0);
    final peer = _peer('u1', broadcastStopped);

    test('마지막 수신 10분 뒤에는 아직 진하게(alpha 1.0) 그린다', () {
      final markers = buildPeerMarkers(
        [peer],
        now: broadcastStopped.add(const Duration(minutes: 10)),
      );
      expect(_markerFor(markers, 'u1').alpha, 1.0);
    });

    test('마지막 수신 31분 뒤(임계값 초과)에는 alpha를 staleOpacity로 낮춘다', () {
      final markers = buildPeerMarkers(
        [peer],
        now: broadcastStopped.add(const Duration(minutes: 31)),
      );
      expect(_markerFor(markers, 'u1').alpha, PeerLocation.staleOpacity);
    });

    test('2인 그룹: 한 명만 앱을 끄면 그 사람 마커만 흐려진다', () {
      final now = DateTime.utc(2026, 8, 27, 12, 0, 0);
      final active = _peer('active', now.subtract(const Duration(minutes: 2)));
      final wentOffline =
          _peer('offline', now.subtract(const Duration(minutes: 45)));

      final markers = buildPeerMarkers([active, wentOffline], now: now);

      expect(_markerFor(markers, 'active').alpha, 1.0);
      expect(_markerFor(markers, 'offline').alpha, PeerLocation.staleOpacity);
    });

    test('피어 한 명당 마커 하나를 만들고 id는 userId를 쓴다', () {
      final now = DateTime.utc(2026, 8, 27, 12, 0, 0);
      final markers = buildPeerMarkers(
        [_peer('a', now), _peer('b', now)],
        now: now,
      );
      expect(markers.map((m) => m.markerId.value).toSet(), {'a', 'b'});
    });

    test('approx/precise 모드에 따라 마커 색(hue)을 다르게 준다', () {
      final now = DateTime.utc(2026, 8, 27, 12, 0, 0);
      final markers = buildPeerMarkers(
        [
          _peer('precise', now, mode: 'precise'),
          _peer('approx', now, mode: 'approx'),
        ],
        now: now,
      );
      // BitmapDescriptor에는 값 동등성이 없어 toJson()(['defaultMarker', hue])
      // 으로 비교한다.
      expect(
        _markerFor(markers, 'precise').icon.toJson(),
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure).toJson(),
      );
      expect(
        _markerFor(markers, 'approx').icon.toJson(),
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
            .toJson(),
      );
    });
  });
}
