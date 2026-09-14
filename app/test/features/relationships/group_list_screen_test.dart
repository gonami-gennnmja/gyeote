import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gyeote/features/relationships/data/models/relationship_group.dart';
import 'package:gyeote/features/relationships/data/relationship_repository.dart';
import 'package:gyeote/features/relationships/presentation/screens/group_list_screen.dart';

/// 실제 Supabase에 붙지 않기 위한 더미 클라이언트(stale_rerender_widget_test와 동일 패턴).
SupabaseClient _dummyClient() => SupabaseClient(
      'https://example.supabase.co',
      'dummy-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

class _FakeRelationshipRepository extends RelationshipRepository {
  _FakeRelationshipRepository(this._groups) : super(client: _dummyClient());

  final List<RelationshipGroup> _groups;
  int fetchCalls = 0;

  @override
  Future<List<RelationshipGroup>> fetchMyGroups() async {
    fetchCalls++;
    return _groups;
  }
}

void main() {
  testWidgets(
    '재로드가 setState() 콜백에서 Future를 반환하지 않는다 (당겨서 새로고침 → 화면 복귀와 동일 코드 경로)',
    (tester) async {
      // 회귀 배경: _reload()가 setState(() => _future = ...) 화살표 바디로
      // 짜여 있으면, 대입식 자체의 값(Future)이 setState 콜백의 반환값이 돼서
      // "setState() callback argument returned a Future." assertion을 던진다.
      // 이 화면에서 _reload()는 그룹 생성/초대 수락/상세 화면에서 **돌아올 때**
      // (_goToCreate/_goToAcceptInvitation/_goToDetail의 push 이후) 호출되는
      // 것과 완전히 같은 함수이며, 당겨서 새로고침(RefreshIndicator.onRefresh)
      // 에서도 동일하게 호출된다. 실제 push 대상 화면들은 기본 생성자로
      // RelationshipRepository()를 직접 만들어(Supabase.instance 접근) 위젯
      // 테스트에서 초기화되지 않은 Supabase에 부딪혀 무관한 이유로 실패하므로,
      // 여기서는 push/pop 대신 같은 _reload()를 타는 pull-to-refresh로
      // 재현한다 — 검증 대상인 setState 콜백은 완전히 동일하다.
      final fake = _FakeRelationshipRepository([
        RelationshipGroup(
          id: 'g1',
          type: 'couple',
          name: '우리 둘',
          createdBy: 'u1',
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(home: GroupListScreen(repository: fake)),
      );
      await tester.pumpAndSettle();

      expect(fake.fetchCalls, 1);
      expect(find.text('우리 둘'), findsOneWidget);

      // 당겨서 새로고침 제스처 → _reload() 호출.
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // 핵심 단언: setState 콜백이 Future를 반환해서 던지는 assertion이 없다.
      expect(tester.takeException(), isNull);
      // 목록도 실제로 다시 로드됐다(단순히 예외를 삼킨 게 아니라 갱신됨).
      expect(fake.fetchCalls, 2);
      expect(find.text('우리 둘'), findsOneWidget);
    },
  );
}
