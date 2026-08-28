import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gyeote/core/errors/server_error_message.dart';
import 'package:gyeote/features/location/data/server_error_messages.dart';
import 'package:gyeote/features/relationships/data/server_error_messages.dart';

PostgrestException _err(String message) => PostgrestException(message: message);

void main() {
  group('mapServerErrorMessage', () {
    const fallback = '문제가 생겼어요. 다시 시도해주세요.';

    test('화이트리스트에 없는 미지의 예외는 무조건 fallback으로 덮인다 (원문이 새지 않는다)', () {
      // 이게 이 함수의 핵심 안전장치다. PostgREST가 뱉는 임의의 인프라 원문이
      // 화면까지 올라오지 않아야 한다.
      final result = mapServerErrorMessage(
        _err('duplicate key value violates unique constraint "pg_xyz"'),
        whitelist: shareSettingsServerErrors,
        fallback: fallback,
      );
      expect(result, fallback);
    });

    test('빈 메시지도 fallback으로 덮인다', () {
      expect(
        mapServerErrorMessage(_err(''),
            whitelist: relationshipGroupServerErrors, fallback: fallback),
        fallback,
      );
    });

    test('대소문자가 섞인 메시지도 매칭된다 (소문자 contains)', () {
      final result = mapServerErrorMessage(
        _err('ERROR: Not A Member Of This Group'),
        whitelist: shareSettingsServerErrors,
        fallback: fallback,
      );
      expect(result, '더 이상 이 그룹의 멤버가 아니에요.');
    });

    test('메시지에 원문이 앞뒤로 더 붙어 있어도 부분 매칭된다', () {
      final result = mapServerErrorMessage(
        _err('PostgrestException(message: authentication required, code: 401)'),
        whitelist: relationshipGroupServerErrors,
        fallback: fallback,
      );
      expect(result, '로그인이 만료됐어요. 다시 로그인해주세요.');
    });

    test('삽입 순서대로 검사해 첫 매칭을 채택한다', () {
      const whitelist = <String, String>{
        'conflict': '먼저 걸리는 문구',
        'edit conflict': '나중 문구',
      };
      expect(
        mapServerErrorMessage(_err('edit conflict detected'),
            whitelist: whitelist, fallback: fallback),
        '먼저 걸리는 문구',
      );
    });
  });

  group('shareSettingsServerErrors - 각 항목이 의도한 문구로 매핑된다', () {
    const fallback = '공유 설정을 바꾸지 못했어요. 다시 시도해주세요.';
    final cases = {
      'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
      'User is not a member of this group': '더 이상 이 그룹의 멤버가 아니에요.',
      'invalid mode: sideways': '선택할 수 없는 모드예요. 다시 시도해주세요.',
      'pause_minutes must be a positive integer':
          '일시중지 시간을 다시 선택해주세요.',
    };
    cases.forEach((raw, expected) {
      test('"$raw" → "$expected"', () {
        expect(
          mapServerErrorMessage(_err(raw),
              whitelist: shareSettingsServerErrors, fallback: fallback),
          expected,
        );
      });
    });
  });

  group('relationshipGroupServerErrors - 각 항목이 의도한 문구로 매핑된다', () {
    const fallback = '문제가 생겼어요. 다시 시도해주세요.';
    final cases = {
      'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
      'only members of the group can create invitations':
          '이 그룹의 멤버만 초대 코드를 만들 수 있어요.',
      'not a member of this group': '더 이상 이 그룹의 멤버가 아니에요.',
      'only the group owner can remove members':
          '그룹을 만든 사람만 멤버를 내보낼 수 있어요.',
      'use leave_relationship_group() to remove yourself':
          '자기 자신은 "그룹 탈퇴"로 나가야 해요.',
    };
    cases.forEach((raw, expected) {
      test('"$raw" → "$expected"', () {
        expect(
          mapServerErrorMessage(_err(raw),
              whitelist: relationshipGroupServerErrors, fallback: fallback),
          expected,
        );
      });
    });
  });
}
