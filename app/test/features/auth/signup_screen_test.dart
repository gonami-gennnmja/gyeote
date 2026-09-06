import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gyeote/features/auth/data/auth_repository.dart';
import 'package:gyeote/features/auth/presentation/screens/signup_screen.dart';

/// signUp만 스텁하는 가짜 repository. 나머지 멤버는 호출되면 테스트가 깨지도록
/// noSuchMethod로 둔다.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.response});

  final AuthResponse? response;
  int signUpCalls = 0;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    signUpCalls++;
    return response ?? AuthResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _fillAndSubmit(WidgetTester tester, {String email = 'nova@example.com'}) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), 'password123');
  await tester.enterText(find.byType(TextFormField).at(2), 'password123');
  await tester.tap(find.widgetWithText(FilledButton, '가입하기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('session이 없으면 pop하지 않고 가입 확인 패널로 전환된다', (tester) async {
    final fake = _FakeAuthRepository(response: AuthResponse()); // session == null

    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authRepository: fake)),
    );

    await _fillAndSubmit(tester, email: 'nova@example.com');

    expect(fake.signUpCalls, 1);

    // 안내 패널이 뜨고 보낸 주소가 보인다.
    expect(find.text('가입 확인 메일을 보냈어요'), findsOneWidget);
    expect(find.textContaining('nova@example.com'), findsOneWidget);
    expect(find.text('메일이 안 보이면 스팸함도 확인해주세요.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '로그인하러 가기'), findsOneWidget);

    // 폼은 감춰지고 AppBar 제목이 바뀌며 뒤로가기가 사라진다.
    expect(find.text('비밀번호 확인'), findsNothing);
    expect(find.widgetWithText(FilledButton, '가입하기'), findsNothing);
    expect(find.text('가입 확인'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets(
      'session이 바로 발급되면(확인 비활성 환경) 패널로 넘어가지 않고 폼에 머문다',
      (tester) async {
    // 운영에서 mailer_autoconfirm을 끄면 signUp이 즉시 세션을 돌려준다.
    // 그때 이 화면은 아무것도 하지 않아야 한다(홈 전환은 AuthGate 담당).
    // 지금은 이 경로가 코드 주석으로만 보장돼서 회귀 방어로 못 박아둔다.
    final withSession = AuthResponse.fromJson({
      'access_token': 'fake-access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'fake-refresh-token',
      'user': {
        'id': '00000000-0000-0000-0000-000000000000',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00.000Z',
      },
    });
    expect(withSession.session, isNotNull, reason: '테스트 전제: 세션이 있는 응답');

    final fake = _FakeAuthRepository(response: withSession);
    await tester.pumpWidget(
      MaterialApp(home: SignupScreen(authRepository: fake)),
    );

    await _fillAndSubmit(tester);

    expect(fake.signUpCalls, 1);
    // 확인 패널로 전환되지 않고 폼이 그대로 남는다.
    expect(find.text('가입 확인 메일을 보냈어요'), findsNothing);
    expect(find.text('비밀번호 확인'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '가입하기'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
  });

  testWidgets('확인 패널의 "로그인하러 가기"가 화면을 닫는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SignupScreen(authRepository: _FakeAuthRepository()),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _fillAndSubmit(tester);
    expect(find.text('가입 확인 메일을 보냈어요'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '로그인하러 가기'));
    await tester.pumpAndSettle();

    // signup 화면이 닫히고 원래 화면으로 돌아온다.
    expect(find.text('가입 확인 메일을 보냈어요'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
