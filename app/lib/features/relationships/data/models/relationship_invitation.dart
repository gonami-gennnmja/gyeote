/// `create_relationship_invitation` RPC가 반환하는 `relationship_invitations`
/// 행 전체를 표현하는 모델. 생성 직후 초대 코드를 화면에 보여주고 클립보드로
/// 복사할 수 있도록 사용한다.
class RelationshipInvitation {
  const RelationshipInvitation({
    required this.id,
    required this.groupId,
    required this.inviteCode,
    required this.invitedBy,
    required this.invitedEmail,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
  });

  factory RelationshipInvitation.fromJson(Map<String, dynamic> json) {
    return RelationshipInvitation(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      inviteCode: json['invite_code'] as String,
      invitedBy: json['invited_by'] as String,
      invitedEmail: json['invited_email'] as String?,
      status: json['status'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String groupId;
  final String inviteCode;
  final String invitedBy;
  final String? invitedEmail;
  final String status;
  final DateTime expiresAt;
  final DateTime createdAt;
}
