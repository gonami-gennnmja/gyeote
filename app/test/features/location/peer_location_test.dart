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

  group('PeerLocation.isStale', () {
    // 임계값은 30분(PeerLocation.staleThreshold). 지도 마커 alpha와 피어 칩
    // 톤다운이 이 값 하나에 걸려 있으므로 경계(29:59 / 30:00 / 30:01)를 못박아
    // 둔다.
    final now = DateTime.utc(2026, 8, 23, 12, 0, 0);

    test('threshold 상수가 30분이다', () {
      expect(PeerLocation.staleThreshold, const Duration(minutes: 30));
    });

    test('방금 받은 위치는 stale이 아니다', () {
      final peer = _peerAt(now.subtract(const Duration(seconds: 10)));
      expect(peer.isStale(now: now), isFalse);
    });

    test('임계값 직전(29분 59초)은 아직 stale이 아니다', () {
      final peer = _peerAt(
        now.subtract(const Duration(minutes: 29, seconds: 59)),
      );
      expect(peer.isStale(now: now), isFalse);
    });

    test('정확히 임계값(30분 0초)이면 stale이다 (>= 비교)', () {
      final peer = _peerAt(now.subtract(const Duration(minutes: 30)));
      expect(peer.isStale(now: now), isTrue);
    });

    test('임계값을 넘으면(30분 1초) stale이다', () {
      final peer = _peerAt(
        now.subtract(const Duration(minutes: 30, seconds: 1)),
      );
      expect(peer.isStale(now: now), isTrue);
    });

    test('몇 시간 지난 위치도 stale이다', () {
      final peer = _peerAt(now.subtract(const Duration(hours: 5)));
      expect(peer.isStale(now: now), isTrue);
    });

    test('미래 시각(시계 오차로 receivedAt이 now보다 뒤)이면 stale이 아니다', () {
      final peer = _peerAt(now.add(const Duration(minutes: 40)));
      expect(peer.isStale(now: now), isFalse);
    });

    test('receivedAt이 로컬 타임존이어도 UTC로 환산해 판단한다', () {
      // now(UTC 12:00)에서 정확히 40분 전을 KST(+09:00)로 표현한 값.
      // toUtc() 없이 로컬끼리 빼면 오프셋만큼 어긋나 결과가 뒤집힐 수 있다.
      final receivedLocalKst = DateTime.parse('2026-08-23T20:20:00+09:00');
      final peer = _peerAt(receivedLocalKst);
      expect(peer.isStale(now: now), isTrue);
    });

    test('now를 생략하면 현재 시각 기준으로 동작한다 (오래된 위치 → stale)', () {
      final peer = _peerAt(DateTime.now().toUtc().subtract(
            const Duration(hours: 2),
          ));
      expect(peer.isStale(), isTrue);
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
