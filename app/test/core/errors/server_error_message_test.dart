import 'package:flutter_test/flutter_test.dart';

import 'package:gyeote/core/errors/server_error_message.dart';
import 'package:gyeote/features/auth/data/server_error_messages.dart';
import 'package:gyeote/features/location/data/server_error_messages.dart';
import 'package:gyeote/features/relationships/data/server_error_messages.dart';

void main() {
  group('mapServerErrorMessage', () {
    const fallback = '문제가 생겼어요. 다시 시도해주세요.';

    test('화이트리스트에 없는 미지의 예외는 무조건 fallback으로 덮인다 (원문이 새지 않는다)', () {
      // 이게 이 함수의 핵심 안전장치다. 서버가 뱉는 임의의 인프라 원문이
      // 화면까지 올라오지 않아야 한다.
      final result = mapServerErrorMessage(
        'duplicate key value violates unique constraint "pg_xyz"',
        whitelist: shareSettingsServerErrors,
        fallback: fallback,
      );
      expect(result, fallback);
    });

    test('빈 메시지도 fallback으로 덮인다', () {
      expect(
        mapServerErrorMessage('',
            whitelist: relationshipGroupServerErrors, fallback: fallback),
        fallback,
      );
    });

    test('대소문자가 섞인 메시지도 매칭된다 (소문자 contains)', () {
      final result = mapServerErrorMessage(
        'ERROR: Not A Member Of This Group',
        whitelist: shareSettingsServerErrors,
        fallback: fallback,
      );
      expect(result, '더 이상 이 그룹의 멤버가 아니에요.');
    });

    test('메시지에 원문이 앞뒤로 더 붙어 있어도 부분 매칭된다', () {
      final result = mapServerErrorMessage(
        'PostgrestException(message: authentication required, code: 401)',
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
        mapServerErrorMessage('edit conflict detected',
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
          mapServerErrorMessage(raw,
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
          mapServerErrorMessage(raw,
              whitelist: relationshipGroupServerErrors, fallback: fallback),
          expected,
        );
      });
    });
  });

  group('groupCreateServerErrors (P0-8)', () {
    const fallback = '그룹을 만들지 못했어요. 다시 시도해주세요.';

    test('세션 만료(authentication required)만 매핑한다', () {
      expect(
        mapServerErrorMessage('authentication required',
            whitelist: groupCreateServerErrors, fallback: fallback),
        '로그인이 만료됐어요. 다시 로그인해주세요.',
      );
    });

    test('enum 오입력 원문은 화이트리스트에 없고 폴백으로 덮인다 (정상 UI로는 도달 불가)', () {
      expect(
        mapServerErrorMessage(
          'invalid input value for enum relationship_type: "spouse"',
          whitelist: groupCreateServerErrors,
          fallback: fallback,
        ),
        fallback,
      );
    });
  });

  group('invitationServerErrors (P0-8) - 미리보기/수락 공용', () {
    const fallback = '초대를 수락하지 못했어요. 다시 시도해주세요.';
    final cases = {
      'authentication required': '로그인이 만료됐어요. 다시 로그인해주세요.',
      'invitation not found': '존재하지 않는 초대 코드예요.',
      // status enum이 % 자리에 치환돼도 부분일치로 잡힌다.
      'invitation is not pending (status: accepted)':
          '이미 처리됐거나 취소된 초대예요.',
      'invitation is not pending (status: revoked)':
          '이미 처리됐거나 취소된 초대예요.',
      'invitation has expired': '만료된 초대예요.',
      'invitation is scoped to a different email address':
          '초대받은 이메일 계정으로 로그인해야 참여할 수 있어요.',
      'already a member of this group': '이미 이 그룹의 멤버예요.',
    };
    cases.forEach((raw, expected) {
      test('"$raw" → "$expected"', () {
        expect(
          mapServerErrorMessage(raw,
              whitelist: invitationServerErrors, fallback: fallback),
          expected,
        );
      });
    });

    test('미리보기 경로의 인프라 원문은 폴백으로 덮인다', () {
      expect(
        mapServerErrorMessage(
          'FormatException: Unexpected character (at character 1)',
          whitelist: invitationServerErrors,
          fallback: '초대 정보를 불러오지 못했어요. 다시 시도해주세요.',
        ),
        '초대 정보를 불러오지 못했어요. 다시 시도해주세요.',
      );
    });
  });

  group('authServerErrors (P0-8) - code+message 합친 문자열로 매칭', () {
    const loginFallback = '로그인 중 문제가 생겼어요. 다시 시도해주세요.';
    const signupFallback = '회원가입 중 문제가 생겼어요. 다시 시도해주세요.';

    // 호출부가 넘기는 형태: '${e.code ?? ''} ${e.message}'
    String joined(String? code, String message) => '${code ?? ''} $message';

    test('로그인 실패는 코드형 키(invalid_credentials)로 단일 문구', () {
      expect(
        mapServerErrorMessage(
          joined('invalid_credentials', 'Invalid login credentials'),
          whitelist: authServerErrors,
          fallback: loginFallback,
        ),
        '이메일 또는 비밀번호가 올바르지 않아요.',
      );
    });

    test('code가 null이어도 문구형 키로 매칭된다', () {
      expect(
        mapServerErrorMessage(
          joined(null, 'Invalid login credentials'),
          whitelist: authServerErrors,
          fallback: loginFallback,
        ),
        '이메일 또는 비밀번호가 올바르지 않아요.',
      );
    });

    test('이메일 미인증은 별도 안내 문구', () {
      expect(
        mapServerErrorMessage(
          joined('email_not_confirmed', 'Email not confirmed'),
          whitelist: authServerErrors,
          fallback: loginFallback,
        ),
        '아직 메일 인증이 안 끝났어요. 가입할 때 보내드린 메일에서 인증 링크를 눌러주세요.',
      );
    });

    test('가입 중복은 코드형(user_already_exists)·문구형 모두 같은 문구', () {
      const expected = '이미 가입된 이메일이에요. 로그인해주세요.';
      expect(
        mapServerErrorMessage(joined('user_already_exists', ''),
            whitelist: authServerErrors, fallback: signupFallback),
        expected,
      );
      expect(
        mapServerErrorMessage(
          joined(null,
              'A user with this email address has already been registered'),
          whitelist: authServerErrors,
          fallback: signupFallback,
        ),
        expected,
      );
    });

    test('약한 비밀번호 / 길이 미달을 구분해 안내한다', () {
      expect(
        mapServerErrorMessage(joined('weak_password', 'Password is too weak'),
            whitelist: authServerErrors, fallback: signupFallback),
        '비밀번호가 너무 단순해요. 다른 비밀번호로 다시 시도해주세요.',
      );
      expect(
        mapServerErrorMessage(
          joined(null, 'Password should be at least 6 characters'),
          whitelist: authServerErrors,
          fallback: signupFallback,
        ),
        '비밀번호가 조건에 맞지 않아요. 6자 이상으로 다시 입력해주세요.',
      );
    });

    test('rate limit 계열은 상황별 문구로 나뉜다', () {
      expect(
        mapServerErrorMessage(
          joined('over_email_send_rate_limit', 'email rate limit exceeded'),
          whitelist: authServerErrors,
          fallback: signupFallback,
        ),
        '인증 메일을 너무 자주 보냈어요. 잠시 후 다시 시도해주세요.',
      );
      expect(
        mapServerErrorMessage(
          joined(null,
              'For security purposes, you can only request this after 40 seconds.'),
          whitelist: authServerErrors,
          fallback: loginFallback,
        ),
        '요청이 많아요. 잠시 후 다시 시도해주세요.',
      );
    });

    test('표에 없는 auth 메시지는 화면별 폴백으로 덮인다 (원문 비노출)', () {
      expect(
        mapServerErrorMessage(
          joined('validation_failed', 'Something GoTrue-specific and raw'),
          whitelist: authServerErrors,
          fallback: loginFallback,
        ),
        loginFallback,
      );
    });
  });
}
