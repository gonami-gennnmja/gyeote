import '../relationships/data/models/relationship_member.dart';

/// 그룹 로스터에는 있지만(=아직 멤버) 위치 결과엔 없는(=지금 내게 위치가
/// 안 보이는) 상대 한 명. 화면이 그대로 그릴 수 있는 형태다.
///
/// `isPaused`는 `is_location_paused` RPC의 결과를 그대로 담는다 — `true`만
/// "일시중지 중"으로 구체적으로 표시한다. `false`(설정 행 있음=명시적으로
/// 껐음)와 `null`(설정 행 없음=미설정)은 서로 다른 값이지만 절대 구분해서
/// 보여주지 않고 하나의 중립 상태로 합친다 — 구분해 보여주면 상대가 감추고
/// 싶어하는 "off 여부" 자체를 노출하는 오라클이 되기 때문이다(Din UX 리뷰
/// P0-6, Plexa 2026-08-24 정정).
class HiddenPeer {
  const HiddenPeer({required this.member, required this.isPaused});

  final RelationshipMember member;
  final bool? isPaused;
}

/// 그룹 로스터에는 있고(=아직 멤버) 지금 위치 결과엔 없는(=화면에 보이지
/// 않는) 상대만 골라낸다. 본인은 제외한다.
///
/// 로스터에도 없는 상대(=그룹을 나감)는 애초에 이 목록에 들어오지 않는다 —
/// 원래 그 그룹에 없던 사람과 UI상 구분할 필요가 없고, 멤버십 변경 알림은
/// 이 판단의 범위 밖이다(P0-6 참고).
List<RelationshipMember> selectHiddenCandidates({
  required List<RelationshipMember> roster,
  required Iterable<String> visiblePeerIds,
  required String? currentUserId,
}) {
  final visible = visiblePeerIds.toSet();
  return roster
      .where((member) =>
          member.userId != currentUserId && !visible.contains(member.userId))
      .toList();
}

/// [selectHiddenCandidates]가 골라낸 후보들에 `is_location_paused` 조회
/// 결과(userId -> isPaused)를 붙여, 화면이 그대로 그릴 수 있는 목록을
/// 만든다. `pausedByUserId`에 값이 없는 후보는 아직 조회하지 못한 것으로
/// 보고 `null`(중립 상태)로 취급한다.
List<HiddenPeer> buildHiddenPeers({
  required List<RelationshipMember> candidates,
  required Map<String, bool?> pausedByUserId,
}) {
  return [
    for (final member in candidates)
      HiddenPeer(member: member, isPaused: pausedByUserId[member.userId]),
  ];
}
