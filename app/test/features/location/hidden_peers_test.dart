import 'package:flutter_test/flutter_test.dart';

import 'package:gyeote/features/location/hidden_peers.dart';
import 'package:gyeote/features/relationships/data/models/relationship_member.dart';

RelationshipMember _member(String userId, {String nickname = 'nick'}) {
  return RelationshipMember(
    groupId: 'g1',
    userId: userId,
    role: 'member',
    joinedAt: DateTime.utc(2026, 1, 1),
    nickname: nickname,
    avatarUrl: null,
  );
}

void main() {
  group('selectHiddenCandidates', () {
    test('로스터에서 본인과 visiblePeerIds에 있는 상대는 제외하고 나머지만 고른다', () {
      final roster = [
        _member('me'),
        _member('visible'),
        _member('hidden1'),
        _member('hidden2'),
      ];

      final result = selectHiddenCandidates(
        roster: roster,
        visiblePeerIds: {'visible'},
        currentUserId: 'me',
      );

      expect(result.map((m) => m.userId).toList(), ['hidden1', 'hidden2']);
    });

    test('본인이 visiblePeerIds에도 없어도(스스로 위치를 안 보내는 상태여도) 여전히 제외된다', () {
      final roster = [_member('me'), _member('hidden1')];

      final result = selectHiddenCandidates(
        roster: roster,
        visiblePeerIds: const <String>{},
        currentUserId: 'me',
      );

      expect(result.map((m) => m.userId).toList(), ['hidden1']);
    });

    test('모두 visible이면 빈 목록을 반환한다', () {
      final roster = [_member('me'), _member('a'), _member('b')];

      final result = selectHiddenCandidates(
        roster: roster,
        visiblePeerIds: {'a', 'b'},
        currentUserId: 'me',
      );

      expect(result, isEmpty);
    });

    test('currentUserId가 null이어도(로그인 사용자 식별 실패 등 예외적 상황) 예외 없이 동작한다', () {
      final roster = [_member('a'), _member('b')];

      final result = selectHiddenCandidates(
        roster: roster,
        visiblePeerIds: {'a'},
        currentUserId: null,
      );

      expect(result.map((m) => m.userId).toList(), ['b']);
    });
  });

  group('buildHiddenPeers', () {
    test(
      '핵심 정책: isPaused가 false인 후보와 pausedByUserId에 아예 없는(=null) 후보는 '
      'HiddenPeer 목록에 포함되는지 여부와 순서에서 완전히 동일하게 취급된다 '
      '(둘 다 빠짐없이 포함되고, isPaused=true인 후보와만 구별된다)',
      () {
        final candidates = [
          _member('hidden-false'),
          _member('hidden-null'),
          _member('hidden-true'),
        ];

        final result = buildHiddenPeers(
          candidates: candidates,
          pausedByUserId: {
            'hidden-false': false,
            'hidden-true': true,
            // 'hidden-null'은 의도적으로 키 자체를 넣지 않는다(아직 조회 못한 경우 재현).
          },
        );

        expect(result.map((h) => h.member.userId).toList(),
            ['hidden-false', 'hidden-null', 'hidden-true']);
        expect(result[0].isPaused, isFalse);
        expect(result[1].isPaused, isNull);
        expect(result[2].isPaused, isTrue);

        // "false와 null을 구분하지 않는다"는 정책의 관찰 가능한 형태: 이 레이어에서는
        // 둘 다 후보 목록에서 빠지거나 예외를 내지 않고 그대로 포함된다는 것 —
        // true인 항목과 달리 어느 쪽도 별도 취급/필터링되지 않는다.
        final nonTruePaused =
            result.where((h) => h.isPaused != true).map((h) => h.member.userId);
        expect(nonTruePaused, containsAll(['hidden-false', 'hidden-null']));
      },
    );

    test('명시적 null 값과 키 자체가 없는 경우가 같은 결과(isPaused == null)를 낸다', () {
      final candidates = [_member('a'), _member('b')];

      final result = buildHiddenPeers(
        candidates: candidates,
        pausedByUserId: {'a': null},
      );

      expect(result[0].isPaused, isNull);
      expect(result[1].isPaused, isNull);
    });

    test('빈 후보 목록이면 빈 결과를 낸다', () {
      final result = buildHiddenPeers(candidates: const [], pausedByUserId: const {});
      expect(result, isEmpty);
    });
  });

  group('selectHiddenCandidates + buildHiddenPeers 결합', () {
    test('로스터 전체에서 본인/visible/hidden(false·null·true)을 한 번에 올바르게 분류한다', () {
      final roster = [
        _member('me'),
        _member('visible'),
        _member('hidden-false'),
        _member('hidden-null'),
        _member('hidden-true'),
      ];

      final candidates = selectHiddenCandidates(
        roster: roster,
        visiblePeerIds: {'visible'},
        currentUserId: 'me',
      );
      final hiddenPeers = buildHiddenPeers(
        candidates: candidates,
        pausedByUserId: {'hidden-false': false, 'hidden-true': true},
      );

      expect(hiddenPeers.map((h) => h.member.userId).toSet(),
          {'hidden-false', 'hidden-null', 'hidden-true'});
      expect(
        hiddenPeers.firstWhere((h) => h.member.userId == 'hidden-false').isPaused,
        isFalse,
      );
      expect(
        hiddenPeers.firstWhere((h) => h.member.userId == 'hidden-null').isPaused,
        isNull,
      );
      expect(
        hiddenPeers.firstWhere((h) => h.member.userId == 'hidden-true').isPaused,
        isTrue,
      );
    });
  });

  group('HiddenPeer.showPausedBadge', () {
    test(
      '핵심 정책을 직접 비교로 검증: isPaused=false / isPaused=null / '
      'pausedByUserId에 키 자체가 없는 경우(=조회 결과에 없음) 세 가지는 '
      'showPausedBadge가 서로 완전히 같아야 하고(모두 false), isPaused=true인 '
      '경우만 달라야 한다. 이 규칙은 HiddenPeer 생성자에서 고정되므로(위젯을 '
      '거치지 않고) 여기서 직접 검증한다.',
      () {
        final withFalse = HiddenPeer(member: _member('a'), isPaused: false);
        final withNull = HiddenPeer(member: _member('b'), isPaused: null);
        final withoutEntry = buildHiddenPeers(
          candidates: [_member('c')],
          pausedByUserId: const {}, // 'c'에 대한 키 자체가 없음
        ).single;
        final withTrue = HiddenPeer(member: _member('d'), isPaused: true);

        // 세 경우가 서로 완전히 동일해야 한다는 것을 "각각 false다"라고 세 번
        // 단언하는 대신, 서로를 직접 비교해 의도를 분명히 한다.
        expect(withFalse.showPausedBadge, equals(withNull.showPausedBadge));
        expect(withNull.showPausedBadge, equals(withoutEntry.showPausedBadge));
        expect(withFalse.showPausedBadge, equals(withoutEntry.showPausedBadge));
        expect(withFalse.showPausedBadge, isFalse);

        // true인 경우만 위 세 경우 전부와 달라야 한다.
        expect(withTrue.showPausedBadge, isNot(equals(withFalse.showPausedBadge)));
        expect(withTrue.showPausedBadge, isNot(equals(withNull.showPausedBadge)));
        expect(withTrue.showPausedBadge, isNot(equals(withoutEntry.showPausedBadge)));
        expect(withTrue.showPausedBadge, isTrue);
      },
    );
  });
}
