import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gyeote/features/location/data/location_repository.dart';
import 'package:gyeote/features/location/data/models/geo_point.dart';
import 'package:gyeote/features/location/data/models/peer_location.dart';
import 'package:gyeote/features/location/map/location_map_screen.dart';
import 'package:gyeote/features/relationships/data/models/relationship_member.dart';
import 'package:gyeote/features/relationships/data/relationship_repository.dart';

/// 실제 Supabase에 붙지 않기 위한 더미 클라이언트(hidden_peer_widget_test와 동일).
SupabaseClient _dummyClient() => SupabaseClient(
      'https://example.supabase.co',
      'dummy-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository({required this.peers}) : super(client: _dummyClient());

  final List<PeerLocation> peers;

  @override
  String? get currentUserId => 'me-uid';

  @override
  Future<List<PeerLocation>> getPeerLocations(String relationshipGroupId) async =>
      peers;

  @override
  Future<bool?> isLocationPaused(String peerId, String groupId) async => null;
}

class _FakeRelationshipRepository extends RelationshipRepository {
  _FakeRelationshipRepository() : super(client: _dummyClient());

  @override
  Future<List<RelationshipMember>> fetchGroupMembers(String groupId) async =>
      const [];
}

PeerLocation _peerAt(DateTime receivedAt) => PeerLocation(
      userId: 'peer-uid',
      nickname: '민지',
      position: const GeoPoint(latitude: 37.5, longitude: 127.0),
      accuracyM: 10,
      batteryLevel: 80,
      isCharging: false,
      movementState: 'stationary',
      capturedAt: receivedAt,
      receivedAt: receivedAt,
      mode: 'precise',
    );

void main() {
  testWidgets(
    '새 브로드캐스트 없이 시간만 임계값을 넘겨도 1분 주기 타이머가 피어 칩을 '
    'stale로 다시 그린다 (P1-3 회귀 방어: 상대가 앱을 끄면 재렌더가 안 걸리던 버그)',
    (tester) async {
      final broadcastStopped = DateTime.utc(2026, 8, 27, 9, 0, 0);
      // 이 값만 앞으로 옮기고 새 위치 이벤트는 주지 않는다 = "상대가 앱을 끈"
      // 상황. receivedAt은 broadcastStopped에 고정돼 있다.
      var fakeNow = broadcastStopped;

      await tester.pumpWidget(
        MaterialApp(
          home: LocationMapScreen(
            groupId: 'g1',
            groupName: '테스트 그룹',
            repository: _FakeLocationRepository(peers: [_peerAt(broadcastStopped)]),
            relationshipRepository: _FakeRelationshipRepository(),
            clock: () => fakeNow,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 처음엔 방금 받은 위치라 stale 표시(Icons.history)가 없다.
      expect(find.text('방금 전'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsNothing);

      // 시각을 임계값(30분) 너머로 옮긴다. 하지만 새 프레임을 유발하는 건
      // 아무것도 없다 — 이 시점엔 화면이 아직 갱신되지 않아야 한다.
      fakeNow = broadcastStopped.add(const Duration(minutes: 31));
      await tester.pump();
      expect(
        find.byIcon(Icons.history),
        findsNothing,
        reason: '타이머가 아직 안 돌았으므로 화면은 옛 상태 그대로여야 한다',
      );

      // 1분 주기 타이머가 한 번 발화하도록 시간을 흘린다. 타이머 → setState →
      // 재렌더 → isStale 재평가로 칩이 흐려져야 한다.
      await tester.pump(const Duration(minutes: 1));

      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.text('31분 전'), findsOneWidget);
    },
  );

  testWidgets(
    'LocationMapScreen을 dispose하면 신선도 타이머가 취소된다 (pending timer 없음)',
    (tester) async {
      final t = DateTime.utc(2026, 8, 27, 9, 0, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: LocationMapScreen(
            groupId: 'g1',
            groupName: '테스트 그룹',
            repository: _FakeLocationRepository(peers: [_peerAt(t)]),
            relationshipRepository: _FakeRelationshipRepository(),
            clock: () => t,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 다른 화면으로 교체 → State.dispose 호출. _staleTicker.cancel()이
      // 빠져 있으면 여기서 "A Timer is still pending" 로 이 테스트가 깨진다.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(minutes: 5));
    },
  );
}
