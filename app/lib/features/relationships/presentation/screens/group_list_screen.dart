import 'package:flutter/material.dart';

import '../../data/models/relationship_group.dart';
import '../../data/relationship_repository.dart';
import '../widgets/relationship_type_x.dart';
import 'group_create_screen.dart';
import 'group_detail_screen.dart';
import 'invitation_accept_screen.dart';

/// 내가 속한 관계 그룹(커플/가족/친구) 목록 화면.
///
/// 진입점: 홈 화면의 "관계 그룹" 버튼.
class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  final _repository = RelationshipRepository();
  late Future<List<RelationshipGroup>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.fetchMyGroups();
  }

  void _reload() {
    setState(() => _future = _repository.fetchMyGroups());
  }

  Future<void> _goToCreate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
    );
    _reload();
  }

  Future<void> _goToAcceptInvitation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InvitationAcceptScreen()),
    );
    _reload();
  }

  Future<void> _goToDetail(RelationshipGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('관계 그룹'),
        actions: [
          IconButton(
            tooltip: '초대 코드로 참여',
            icon: const Icon(Icons.mail_outline),
            onPressed: _goToAcceptInvitation,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '그룹 만들기',
        onPressed: _goToCreate,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<RelationshipGroup>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
          }

          final groups = snapshot.data ?? const [];

          if (groups.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      '아직 속한 관계 그룹이 없습니다.\n오른쪽 아래 + 버튼으로 그룹을 만들거나,\n메일 아이콘으로 초대 코드를 입력해보세요.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final typeLabel = group.type.relationshipTypeLabel;
                return Card(
                  child: ListTile(
                    leading: Icon(group.type.relationshipTypeIcon),
                    title: Text(group.displayName(typeLabel)),
                    subtitle: Text(typeLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _goToDetail(group),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
