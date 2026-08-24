import 'package:flutter_test/flutter_test.dart';
import 'package:gyeote/features/location/data/models/geo_point.dart';
import 'package:gyeote/features/location/data/models/peer_location.dart';

PeerLocation _peerAt(DateTime receivedAt, {String mode = 'precise'}) {
  return PeerLocation(
    userId: 'u1',
    nickname: '민지',
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

void main() {
  group('PeerLocation.freshnessLabel', () {
    test('shows 방금 전 for under a minute', () {
      final now = DateTime.utc(2026, 8, 23, 12, 0, 0);
      final peer = _peerAt(now.subtract(const Duration(seconds: 30)));
      expect(peer.freshnessLabel(now: now), '방금 전');
    });

    test('shows minutes for under an hour', () {
      final now = DateTime.utc(2026, 8, 23, 12, 0, 0);
      final peer = _peerAt(now.subtract(const Duration(minutes: 5)));
      expect(peer.freshnessLabel(now: now), '5분 전');
    });

    test('shows hours for under a day', () {
      final now = DateTime.utc(2026, 8, 23, 12, 0, 0);
      final peer = _peerAt(now.subtract(const Duration(hours: 3)));
      expect(peer.freshnessLabel(now: now), '3시간 전');
    });

    test('shows days at/after 24 hours', () {
      final now = DateTime.utc(2026, 8, 23, 12, 0, 0);
      final peer = _peerAt(now.subtract(const Duration(days: 2)));
      expect(peer.freshnessLabel(now: now), '2일 전');
    });

    test('treats a slightly-future receivedAt (clock skew) as 방금 전', () {
      final now = DateTime.utc(2026, 8, 23, 12, 0, 0);
      final peer = _peerAt(now.add(const Duration(seconds: 5)));
      expect(peer.freshnessLabel(now: now), '방금 전');
    });
  });

  group('PeerLocation.isApprox', () {
    test('true only for mode=approx', () {
      expect(_peerAt(DateTime.now(), mode: 'approx').isApprox, isTrue);
      expect(_peerAt(DateTime.now(), mode: 'precise').isApprox, isFalse);
    });
  });

  group('PeerLocation.fromJson', () {
    test('parses a get_peer_locations row', () {
      final peer = PeerLocation.fromJson({
        'user_id': 'u1',
        'nickname': '민지',
        'location': 'SRID=4326;POINT(127.0 37.5)',
        'accuracy_m': 12.5,
        'battery_level': 42,
        'is_charging': true,
        'movement_state': 'walking',
        'captured_at': '2026-08-23T11:59:00Z',
        'received_at': '2026-08-23T12:00:00Z',
        'mode': 'precise',
      });

      expect(peer.userId, 'u1');
      expect(peer.position.longitude, 127.0);
      expect(peer.position.latitude, 37.5);
      expect(peer.batteryLevel, 42);
      expect(peer.isCharging, isTrue);
      expect(peer.movementState, 'walking');
    });

    test('falls back to 알 수 없음 when nickname missing', () {
      final peer = PeerLocation.fromJson({
        'user_id': 'u1',
        'location': 'POINT(127.0 37.5)',
        'accuracy_m': null,
        'battery_level': null,
        'is_charging': null,
        'movement_state': null,
        'captured_at': '2026-08-23T11:59:00Z',
        'received_at': '2026-08-23T12:00:00Z',
        'mode': 'approx',
      });

      expect(peer.nickname, '알 수 없음');
      expect(peer.isApprox, isTrue);
    });
  });
}
