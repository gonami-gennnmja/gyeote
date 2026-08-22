import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import 'models/invitation_preview.dart';
import 'models/relationship_group.dart';
import 'models/relationship_invitation.dart';
import 'models/relationship_member.dart';

/// 관계 그룹(커플/가족/친구) 관련 Supabase 접근을 감싸는 repository.
///
/// 원칙(백엔드 RLS 설계에 맞춤):
/// - 조회는 `relationship_groups` / `relationship_members` / `profiles`에
///   `.select()`로 직접 접근한다 (RLS가 "내가 속한 그룹/멤버"만 보이도록 필터링).
/// - 쓰기(생성/수락/탈퇴/추방/초대)는 전부 `.rpc(...)`로만 수행한다. 테이블에
///   직접 insert/update/delete 하지 않는다 (RLS가 이를 차단하도록 설계되어 있음).
class RelationshipRepository {
  RelationshipRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// 내가 속한 관계 그룹 목록 (RLS가 자동으로 본인 그룹만 반환).
  Future<List<RelationshipGroup>> fetchMyGroups() async {
    final rows = await _client
        .from('relationship_groups')
        .select()
        .order('created_at', ascending: false);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RelationshipGroup.fromJson)
        .toList();
  }

  /// 그룹 단건 조회 (상세 화면 새로고침 등에 사용).
  Future<RelationshipGroup> fetchGroup(String groupId) async {
    final row = await _client
        .from('relationship_groups')
        .select()
        .eq('id', groupId)
        .single();

    return RelationshipGroup.fromJson(row);
  }

  /// 그룹 멤버 목록 (닉네임/아바타는 profiles를 embed 조회).
  Future<List<RelationshipMember>> fetchGroupMembers(String groupId) async {
    // `profiles!user_id(...)`: relationship_members.user_id -> profiles.id FK를
    // 명시적으로 지정하는 PostgREST embed 힌트 문법
    // (alias:table(cols) 형태와 달리, `!`는 FK/컬럼 힌트를 지정하는 문법이다).
    final rows = await _client
        .from('relationship_members')
        .select('group_id, user_id, role, joined_at, profiles!user_id(nickname, avatar_url)')
        .eq('group_id', groupId)
        .order('joined_at');

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(RelationshipMember.fromJson)
        .toList();
  }

  /// 새 관계 그룹 생성. 호출자가 자동으로 owner가 된다.
  Future<RelationshipGroup> createGroup({
    required String type,
    String? name,
  }) async {
    final row = await _client.rpc(
      'create_relationship_group',
      params: {
        'p_type': type,
        'p_name': (name == null || name.trim().isEmpty) ? null : name.trim(),
      },
    );

    return RelationshipGroup.fromJson(row as Map<String, dynamic>);
  }

  /// 그룹 초대 생성 (그룹 멤버만 호출 가능). 반환된 `inviteCode`를 공유한다.
  Future<RelationshipInvitation> createInvitation({
    required String groupId,
    String? invitedEmail,
  }) async {
    final row = await _client.rpc(
      'create_relationship_invitation',
      params: {
        'p_group_id': groupId,
        'p_invited_email': invitedEmail,
      },
    );

    return RelationshipInvitation.fromJson(row as Map<String, dynamic>);
  }

  /// 초대 코드로 그룹 정보 미리보기 (아직 멤버가 아니어도 로그인만 하면 호출 가능).
  Future<InvitationPreview> getInvitationPreview(String inviteCode) async {
    final rows = await _client.rpc(
      'get_invitation_preview',
      params: {'p_invite_code': inviteCode},
    );

    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) {
      throw const RelationshipException('존재하지 않는 초대 코드입니다.');
    }

    return InvitationPreview.fromJson(list.first);
  }

  /// 초대 수락. 성공 시 생성된 그룹 id를 반환한다.
  Future<String> acceptInvitation(String inviteCode) async {
    final row = await _client.rpc(
      'accept_relationship_invitation',
      params: {'p_invite_code': inviteCode},
    );

    return (row as Map<String, dynamic>)['group_id'] as String;
  }

  /// 초대 취소 (초대자 본인 또는 owner만 가능).
  Future<void> revokeInvitation(String invitationId) {
    return _client.rpc(
      'revoke_relationship_invitation',
      params: {'p_invitation_id': invitationId},
    );
  }

  /// 본인 그룹 탈퇴. 마지막 멤버였다면 서버에서 그룹 자체가 삭제된다.
  Future<void> leaveGroup(String groupId) {
    return _client.rpc(
      'leave_relationship_group',
      params: {'p_group_id': groupId},
    );
  }

  /// 멤버 추방 (owner만 가능, 본인은 대상이 될 수 없음).
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) {
    return _client.rpc(
      'remove_relationship_member',
      params: {'p_group_id': groupId, 'p_user_id': userId},
    );
  }
}

/// repository 계층에서 사용하는 도메인 예외 (예: 미리보기 결과 없음).
/// RPC 자체 에러는 `PostgrestException`이 그대로 전파되며, 화면단에서
/// `e.message`를 사용자에게 보여준다.
class RelationshipException implements Exception {
  const RelationshipException(this.message);

  final String message;

  @override
  String toString() => message;
}
