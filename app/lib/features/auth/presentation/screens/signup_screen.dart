import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/server_error_message.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/auth_repository.dart';
import '../../data/server_error_messages.dart';

/// 이메일/비밀번호 회원가입 화면.
///
/// 운영 Supabase는 이메일 확인 필수(`mailer_autoconfirm = false`)이므로 `signUp`
/// 응답에는 세션이 바로 오지 않는다. 이게 v0.1의 **기본 가입 경로**다:
/// - `response.session == null` (기본): 가입 확인 메일을 보냈다는 안내 패널로
///   화면을 전환하고(폼을 감춤), 사용자가 메일함을 다녀올 시간을 준다.
///   사용자는 "로그인하러 가기"로 명시적으로 로그인 화면에 간다.
/// - `response.session != null` (확인 비활성 환경 — 로컬/테스트): AuthGate가
///   자동으로 홈으로 전환하므로 이 화면은 아무것도 하지 않는다.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, AuthRepository? authRepository})
      : _authRepository = authRepository;

  /// 테스트에서 주입하기 위한 것. 실제 앱에서는 null이고 [AuthRepository]를
  /// 직접 만든다.
  final AuthRepository? _authRepository;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  late final AuthRepository _authRepository =
      widget._authRepository ?? AuthRepository();

  bool _isLoading = false;
  String? _errorMessage;

  /// 가입 확인 메일 발송 완료 상태. true면 폼 대신 안내 패널을 보여준다.
  bool _signupDone = false;

  /// 확인 메일을 보낸 주소 (안내 패널에 표시).
  String _sentToEmail = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _authRepository.signUp(
        email: email,
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response.session == null) {
        // 이메일 확인 필수 환경(운영 기본). 안내 패널로 전환한다.
        setState(() {
          _signupDone = true;
          _sentToEmail = email;
        });
      }
      // session이 바로 발급된 경우, AuthGate가 자동으로 홈 화면으로 전환한다.
    } on AuthRetryableFetchException {
      setState(() => _errorMessage = authNetworkError);
    } on AuthException catch (e) {
      setState(() => _errorMessage = mapServerErrorMessage(
            '${e.code ?? ''} ${e.message}',
            whitelist: authServerErrors,
            fallback: '회원가입 중 문제가 생겼어요. 다시 시도해주세요.',
          ));
    } catch (e) {
      setState(() => _errorMessage = '회원가입 중 문제가 생겼어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_signupDone ? '가입 확인' : '회원가입'),
        // 완료 상태에서는 반쯤 채운 폼으로 돌아가는 뒤로가기를 막고
        // "로그인하러 가기" 버튼만 남긴다.
        automaticallyImplyLeading: !_signupDone,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _signupDone ? _buildConfirmPanel(context) : _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: '이메일'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '이메일을 입력해주세요.';
              }
              if (!value.contains('@')) {
                return '올바른 이메일 형식이 아닙니다.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: '비밀번호'),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '비밀번호를 입력해주세요.';
              }
              if (value.length < 6) {
                return '비밀번호는 6자 이상이어야 해요.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordConfirmController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호 확인'),
            validator: (value) {
              if (value != _passwordController.text) {
                return '비밀번호가 일치하지 않아요.';
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: '가입하기',
            isLoading: _isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_unread_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          '가입 확인 메일을 보냈어요',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(
          '$_sentToEmail 주소로 인증 링크를 보냈어요.\n'
          '메일 속 링크를 누르면 가입이 완료돼요. 그다음 이 화면에서 로그인해주세요.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '메일이 안 보이면 스팸함도 확인해주세요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: '로그인하러 가기',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
