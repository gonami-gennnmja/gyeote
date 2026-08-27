import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/widgets/primary_button.dart';
import '../../data/relationship_repository.dart';
import '../widgets/relationship_type_x.dart';
import 'group_detail_screen.dart';

/// 관계 그룹 생성 화면: 타입 선택 + (선택) 이름 입력 -> 생성 -> 상세 화면 이동.
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  static const _types = ['couple', 'family', 'friend'];

  final _repository = RelationshipRepository();
  final _nameController = TextEditingController();

  String _selectedType = _types.first;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final group = await _repository.createGroup(
        type: _selectedType,
        name: _nameController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupDetailScreen(groupId: group.id),
        ),
      );
    } on PostgrestException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = '그룹을 만들지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('관계 그룹 만들기')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('어떤 관계인가요?', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ..._types.map(
                (type) => RadioListTile<String>(
                  value: type,
                  groupValue: _selectedType,
                  onChanged: _isLoading
                      ? null
                      : (value) => setState(() => _selectedType = value!),
                  title: Row(
                    children: [
                      Icon(type.relationshipTypeIcon),
                      const SizedBox(width: 8),
                      Text(type.relationshipTypeLabel),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  labelText: '그룹 이름 (선택)',
                  hintText: '예: 우리 둘, 가족 채팅방',
                ),
                maxLength: 50,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                label: '그룹 만들기',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
