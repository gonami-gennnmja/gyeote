import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/server_error_message.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/models/invitation_preview.dart';
import '../../data/relationship_repository.dart';
import '../../data/server_error_messages.dart';
import '../widgets/relationship_type_x.dart';
import 'group_detail_screen.dart';

/// 초대 코드를 입력해 그룹 정보를 미리 보고 참여를 수락하는 화면.
class InvitationAcceptScreen extends StatefulWidget {
  const InvitationAcceptScreen({super.key});

  @override
  State<InvitationAcceptScreen> createState() =>
      _InvitationAcceptScreenState();
}

class _InvitationAcceptScreenState extends State<InvitationAcceptScreen> {
  final _repository = RelationshipRepository();
  final _codeController = TextEditingController();

  bool _isPreviewLoading = false;
  bool _isAccepting = false;
  String? _errorMessage;
  InvitationPreview? _preview;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = '초대 코드를 입력해주세요.');
      return;
    }

    setState(() {
      _isPreviewLoading = true;
      _errorMessage = null;
      _preview = null;
    });

    try {
      final preview = await _repository.getInvitationPreview(code);
      setState(() => _preview = preview);
    } on PostgrestException catch (e) {
      // get_invitation_preview는 순수 SELECT라 raise exception이 없다 —
      // 여기 오는 PostgrestException은 전부 인프라 계층(토큰/네트워크/RPC)이라
      // 화이트리스트에 걸릴 게 없고 폴백으로 덮인다. 미리보기와 수락이 같은
      // 함수를 타도록 수락 경로와 동일하게 mapServerErrorMessage를 쓴다.
      setState(() => _errorMessage = mapServerErrorMessage(
            e.message,
            whitelist: invitationServerErrors,
            fallback: '초대 정보를 불러오지 못했어요. 다시 시도해주세요.',
          ));
    } on RelationshipException catch (e) {
      // 결과 0행("존재하지 않는 초대 코드예요.")을 repository가 우리 한글 문구로
      // 던진다 — 서버 원문이 아니므로 그대로 노출한다(P0-8 대상 아님).
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = '초대 정보를 불러오지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isPreviewLoading = false);
    }
  }

  Future<void> _accept() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isAccepting = true;
      _errorMessage = null;
    });

    try {
      final groupId = await _repository.acceptInvitation(code);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)),
      );
    } on PostgrestException catch (e) {
      setState(() => _errorMessage = mapServerErrorMessage(
            e.message,
            whitelist: invitationServerErrors,
            fallback: '초대를 수락하지 못했어요. 다시 시도해주세요.',
          ));
    } catch (e) {
      setState(() => _errorMessage = '초대를 수락하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  String _previewStatusMessage(InvitationPreview preview) {
    switch (preview.status) {
      case 'accepted':
        return '이미 수락된 초대예요.';
      case 'revoked':
        return '취소된 초대예요.';
      case 'expired':
        return '만료된 초대예요.';
      case 'pending':
        return preview.expiresAt.isBefore(DateTime.now())
            ? '만료된 초대예요.'
            : '';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final statusMessage = preview == null ? null : _previewStatusMessage(preview);
    final canAccept = preview != null && preview.isPending;

    return Scaffold(
      appBar: AppBar(title: const Text('초대 코드로 참여하기')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: '초대 코드',
                  hintText: '전달받은 초대 코드를 입력하세요',
                ),
                onSubmitted: (_) => _loadPreview(),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: '미리보기',
                isLoading: _isPreviewLoading,
                onPressed: _loadPreview,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(preview.groupType.relationshipTypeIcon),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (preview.groupName == null ||
                                        preview.groupName!.trim().isEmpty)
                                    ? '이름 없는 ${preview.groupType.relationshipTypeLabel} 그룹'
                                    : preview.groupName!,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('초대한 사람: ${preview.invitedByNickname}'),
                        const SizedBox(height: 4),
                        Text(
                          '만료: ${preview.expiresAt.toLocal()}'.split('.').first,
                        ),
                        if (statusMessage != null &&
                            statusMessage.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            statusMessage,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: '수락하고 그룹 참여하기',
                  isLoading: _isAccepting,
                  onPressed: canAccept ? _accept : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
