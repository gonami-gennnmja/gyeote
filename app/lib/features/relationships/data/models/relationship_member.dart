/// `relationship_members` 테이블 한 행 + 조인된 `profiles` 정보를 표현하는 모델.
///
/// repository에서 `profiles:user_id(nickname, avatar_url)` 형태로 embed
/// 조회한 결과를 그대로 매핑한다.
class RelationshipMember {
  const RelationshipMember({
    required this.groupId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.nickname,
    required this.avatarUrl,
  });

  factory RelationshipMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return RelationshipMember(
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      nickname: profile?['nickname'] as String? ?? '알 수 없음',
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  final String groupId;
  final String userId;
  final String role; // 'owner' | 'member'
  final DateTime joinedAt;
  final String nickname;
  final String? avatarUrl;

  bool get isOwner => role == 'owner';
}
