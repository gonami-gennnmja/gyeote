/// `get_invitation_preview` RPC의 반환 행 하나를 표현하는 모델.
///
/// 아직 그룹 멤버가 아닌 사용자가 초대 코드로 그룹 정보를 미리 볼 때 사용하며,
/// `status`가 `pending`이 아니면(만료/취소/이미 수락됨) 수락 버튼을 비활성화해야 한다.
class InvitationPreview {
  const InvitationPreview({
    required this.groupId,
    required this.groupType,
    required this.groupName,
    required this.invitedByNickname,
    required this.status,
    required this.expiresAt,
  });

  factory InvitationPreview.fromJson(Map<String, dynamic> json) {
    return InvitationPreview(
      groupId: json['group_id'] as String,
      groupType: json['group_type'] as String,
      groupName: json['group_name'] as String?,
      invitedByNickname: json['invited_by_nickname'] as String,
      status: json['status'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String groupId;
  final String groupType;
  final String? groupName;
  final String invitedByNickname;
  final String status; // 'pending' | 'accepted' | 'expired' | 'revoked'
  final DateTime expiresAt;

  bool get isPending =>
      status == 'pending' && expiresAt.isAfter(DateTime.now());
}
