import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gyeote/features/location/data/location_repository.dart';
import 'package:gyeote/features/location/data/models/geo_point.dart';
import 'package:gyeote/features/location/data/models/peer_location.dart';
import 'package:gyeote/features/location/map/location_map_screen.dart';
import 'package:gyeote/features/relationships/data/models/relationship_member.dart';
import 'package:gyeote/features/relationships/data/relationship_repository.dart';

/// 실제 Supabase에 연결하지 않기 위한 더미 클라이언트. 아래 Fake들이 모든
/// repository 메서드를 오버라이드하므로 이 클라이언트는 실제로 쓰이지
/// 않지만, LocationRepository/RelationshipRepository의 생성자가 요구하는
/// SupabaseClient 타입을 만족시키기 위해 형태만 필요하다.
SupabaseClient _dummyClient() => SupabaseClient(
      'https://example.supabase.co',
      'dummy-anon-key',
      // autoRefreshToken이 기본값(true)이면 GoTrueClient가 10초 주기 타이머를
      // 시작하는데, 위젯이 dispose된 뒤에도 그 타이머가 남아 flutter_test의
      // "pending timer" 불변식 검사에 걸린다. 이 Fake들은 _client를 실제로
      // 쓰지 않으므로(모든 repository 메서드를 오버라이드함) 꺼도 무방하다.
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

/// P0-6(숨은 멤버) 로직 검증용 Fake. getPeerLocations는 "지금 위치가 보이는"
/// 상대 목록을, isLocationPaused는 상대별 일시중지 여부(true/false/null)를
/// 미리 정해둔 값 그대로 돌려준다.
class _FakeLocationRepository extends LocationRepository {
  _FakeLocationRepository({
    required this.userId,
    required this.visiblePeers,
    required this.pausedByUserId,
  }) : super(client: _dummyClient());

  final String userId;
  final List<PeerLocation> visiblePeers;
  final Map<String, bool?> pausedByUserId;

  @override
  String? get currentUserId => userId;

  @override
  Future<List<PeerLocation>> getPeerLocations(String relationshipGroupId) async {
    return visiblePeers;
  }

  @override
  Future<bool?> isLocationPaused(String peerId, String groupId) async {
    return pausedByUserId[peerId];
  }
}

/// 그룹 로스터를 고정값으로 돌려주는 Fake.
class _FakeRelationshipRepository extends RelationshipRepository {
  _FakeRelationshipRepository({required this.roster}) : super(client: _dummyClient());

  final List<RelationshipMember> roster;

  @override
  Future<List<RelationshipMember>> fetchGroupMembers(String groupId) async {
    return roster;
  }
}

RelationshipMember _member(String userId, String nickname) {
  return RelationshipMember(
    groupId: 'g1',
    userId: userId,
    role: 'member',
    joinedAt: DateTime.utc(2026, 1, 1),
    nickname: nickname,
    avatarUrl: null,
  );
}

PeerLocation _visiblePeer(String userId, String nickname) {
  final now = DateTime.utc(2026, 8, 24, 12);
  return PeerLocation(
    userId: userId,
    nickname: nickname,
    position: const GeoPoint(latitude: 37.5, longitude: 127.0),
    accuracyM: 10,
    batteryLevel: 80,
    isCharging: false,
    movementState: 'stationary',
    capturedAt: now,
    receivedAt: now,
    mode: 'precise',
  );
}

void main() {
  // 나(me) 자신은 로스터에는 있지만 절대 "숨은 멤버"로 취급되면 안 되고,
  // 가시멤버는 get_peer_locations 결과에 있으므로 역시 숨은 멤버가 아니다.
  // 진짜로 숨어야 하는 세 명 중 핵심은 거짓일시중지(false)와 NULL일시중지(null)가
  // *반드시 같은* 중립 상태로 표시돼야 한다는 것 — 이게 지금까지 주석에만
  // 있고 자동 검증이 없던 정책이다(Plexa 2026-08-24 지적).
  const meId = 'me-uid';
  const visibleId = 'visible-uid';
  const hiddenFalseId = 'hidden-false-uid';
  const hiddenNullId = 'hidden-null-uid';
  const hiddenTrueId = 'hidden-true-uid';

  testWidgets(
    'LocationMapScreen: 숨은 멤버 중 isPaused=false와 null은 같은 중립 상태로, true만 일시중지로 표시된다',
    (tester) async {
      final fakeLocationRepo = _FakeLocationRepository(
        userId: meId,
        visiblePeers: [_visiblePeer(visibleId, '가시멤버')],
        pausedByUserId: {
          hiddenFalseId: false,
          hiddenNullId: null,
          hiddenTrueId: true,
        },
      );
      final fakeRelationshipRepo = _FakeRelationshipRepository(
        roster: [
          _member(meId, '나'),
          _member(visibleId, '가시멤버'),
          _member(hiddenFalseId, '거짓일시중지'),
          _member(hiddenNullId, 'NULL일시중지'),
          _member(hiddenTrueId, '진짜일시중지'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LocationMapScreen(
            groupId: 'g1',
            groupName: '테스트 그룹',
            repository: fakeLocationRepo,
            relationshipRepository: fakeRelationshipRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 핵심 케이스: false와 null은 반드시 같은 개수(2건)의 중립 라벨로
      // 합쳐져야 하고, true만 별도로 1건의 일시중지 라벨로 표시돼야 한다.
      expect(find.text('지금은 위치가 보이지 않아요'), findsNWidgets(2));
      expect(find.text('일시중지 중 · 곧 다시 보일 수 있어요'), findsOneWidget);

      // 세 명 모두 숨은 멤버 섹션에 나타나야 한다.
      expect(find.text('거짓일시중지'), findsOneWidget);
      expect(find.text('NULL일시중지'), findsOneWidget);
      expect(find.text('진짜일시중지'), findsOneWidget);

      // 본인은 절대 숨은 멤버로 표시되면 안 된다(자기 자신 제외 로직).
      expect(find.text('나'), findsNothing);
    },
  );
}
