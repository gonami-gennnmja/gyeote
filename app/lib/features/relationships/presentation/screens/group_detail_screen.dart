import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../location/map/location_map_screen.dart';
import '../../data/models/relationship_group.dart';
import '../../data/models/relationship_member.dart';
import '../../data/relationship_repository.dart';
import '../widgets/relationship_type_x.dart';
import '../widgets/role_badge.dart';

/// 관계 그룹 상세 화면.
///
/// - 멤버 목록(닉네임, role 배지)을 보여준다.
/// - 본인이 owner인 경우에만 "멤버 내보내기" / "초대 만들기" 버튼을 노출한다.
///   (백엔드 RPC 자체는 member도 초대를 만들 수 있도록 허용하지만, 화면
///   요구사항에 따라 owner로 한정해 노출한다.)
/// - 누구나 본인 탈퇴가 가능하며, 실수 방지를 위해 확인 다이얼로그를 거친다.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _repository = RelationshipRepository();

  late Future<_GroupDetailData> _future;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_GroupDetailData> _load() async {
    final results = await Future.wait([
      _repository.fetchGroup(widget.groupId),
      _repository.fetchGroupMembers(widget.groupId),
    ]);

    return _GroupDetailData(
      group: results[0] as RelationshipGroup,
      members: results[1] as List<RelationshipMember>,
    );
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _createInvitation() async {
    setState(() => _isMutating = true);
    try {
      final invitation = await _repository.createInvitation(
        groupId: widget.groupId,
      );
      if (!mounted) return;
      await _showInviteCodeDialog(invitation.inviteCode);
    } on PostgrestException catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar('초대 코드를 만들지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _showInviteCodeDialog(String inviteCode) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('초대 코드를 만들었어요'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('아래 코드를 상대방에게 공유해주세요. (7일간 유효)'),
            const SizedBox(height: 12),
            SelectableText(
              inviteCode,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inviteCode));
              if (context.mounted) {
                Navigator.of(context).pop();
                _showSnackBar('초대 코드를 복사했어요.');
              }
            },
            child: const Text('복사하고 닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMember(RelationshipMember member) async {
    final confirmed = await _showConfirmDialog(
      title: '멤버 내보내기',
      message: '${member.nickname}님을 그룹에서 내보낼까요?',
      confirmLabel: '내보내기',
    );
    if (confirmed != true) return;

    setState(() => _isMutating = true);
    try {
      await _repository.removeMember(
        groupId: widget.groupId,
        userId: member.userId,
      );
      _reload();
    } on PostgrestException catch (e) {
      _showSnackBar(e.message);
    } catch (e) {
      _showSnackBar('멤버를 내보내지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await _showConfirmDialog(
      title: '그룹 탈퇴',
      message: '정말 이 그룹에서 나갈까요? 마지막 멤버가 나가면 그룹도 사라져요.',
      confirmLabel: '탈퇴',
    );
    if (confirmed != true) return;

    setState(() => _isMutating = true);
    try {
      await _repository.leaveGroup(widget.groupId);
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      _showSnackBar(e.message);
      if (mounted) setState(() => _isMutating = false);
    } catch (e) {
      _showSnackBar('그룹에서 나가지 못했어요. 다시 시도해주세요.');
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('그룹 상세')),
      body: FutureBuilder<_GroupDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          final currentUserId = _repository.currentUserId;
          final isOwner = data.members.any(
            (m) => m.userId == currentUserId && m.isOwner,
          );

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Icon(data.group.type.relationshipTypeIcon, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        data.group.displayName(
                          data.group.type.relationshipTypeLabel,
                        ),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('위치 지도 보기'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LocationMapScreen(
                          groupId: data.group.id,
                          groupName: data.group.displayName(
                            data.group.type.relationshipTypeLabel,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('멤버 (${data.members.length}명)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...data.members.map(
                  (member) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: member.avatarUrl != null
                            ? NetworkImage(member.avatarUrl!)
                            : null,
                        child: member.avatarUrl == null
                            ? Text(
                                member.nickname.isNotEmpty
                                    ? member.nickname.substring(0, 1)
                                    : '?',
                              )
                            : null,
                      ),
                      title: Text(member.nickname),
                      subtitle: RoleBadge(isOwner: member.isOwner),
                      trailing:
                          (isOwner && member.userId != currentUserId)
                              ? IconButton(
                                  tooltip: '내보내기',
                                  icon: const Icon(Icons.person_remove),
                                  onPressed: _isMutating
                                      ? null
                                      : () => _removeMember(member),
                                )
                              : null,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (isOwner) ...[
                  FilledButton.icon(
                    onPressed: _isMutating ? null : _createInvitation,
                    icon: const Icon(Icons.person_add),
                    label: const Text('초대 코드 만들기'),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _isMutating ? null : _leaveGroup,
                  icon: const Icon(Icons.logout),
                  label: const Text('그룹 탈퇴'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupDetailData {
  const _GroupDetailData({required this.group, required this.members});

  final RelationshipGroup group;
  final List<RelationshipMember> members;
}
