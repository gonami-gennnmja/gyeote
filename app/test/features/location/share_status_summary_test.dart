import 'package:flutter_test/flutter_test.dart';

import 'package:gyeote/features/location/share_status_summary.dart';

void main() {
  group('formatPausedUntil', () {
    // pausedUntil/now를 전부 로컬 DateTime(DateTime(y, m, d, h, min) 생성자,
    // isUtc=false)으로 만든다 — pausedUntil.toLocal()은 이미 로컬인
    // DateTime에는 사실상 아무 변환도 하지 않으므로, 이렇게 하면 이 테스트를
    // 실행하는 머신/CI의 실제 시스템 타임존과 무관하게 항상 같은 결과가
    // 나온다(만약 UTC DateTime을 넣었다면 결과가 실행 환경의 타임존에 따라
    // 달라져서 테스트가 불안정해졌을 것).

    test('오늘 안(오전)이면 날짜 없이 "오전 h:mm까지 일시중지됨"', () {
      final result = formatPausedUntil(
        DateTime(2026, 8, 24, 9, 5),
        now: DateTime(2026, 8, 24, 8, 0),
      );
      expect(result, '오전 9:05까지 일시중지됨');
    });

    test('오늘 안(오후)이면 날짜 없이 "오후 h:mm까지 일시중지됨"', () {
      final result = formatPausedUntil(
        DateTime(2026, 8, 24, 15, 32),
        now: DateTime(2026, 8, 24, 10, 0),
      );
      expect(result, '오후 3:32까지 일시중지됨');
    });

    test('다음날로 넘어가면 "M/d 오후 h:mm까지 일시중지됨" 형태로 날짜가 붙는다', () {
      final result = formatPausedUntil(
        DateTime(2026, 8, 25, 15, 32),
        now: DateTime(2026, 8, 24, 10, 0),
      );
      expect(result, '8/25 오후 3:32까지 일시중지됨');
    });

    test(
      '자정(00:xx)은 "오전 12:xx"로 표시된다(24시간제 0시를 12시간제 12시로 '
      '변환하는 hour12 == 0 분기)',
      () {
        final result = formatPausedUntil(
          DateTime(2026, 8, 24, 0, 15),
          now: DateTime(2026, 8, 24, 0, 0),
        );
        expect(result, '오전 12:15까지 일시중지됨');
      },
    );

    test(
      '정오(12:xx)는 "오후 12:xx"로 표시된다(period 판정이 hour<12 기준이라 '
      '12는 오후로 분류되고, hour12는 그대로 12로 유지되는 분기)',
      () {
        final result = formatPausedUntil(
          DateTime(2026, 8, 24, 12, 0),
          now: DateTime(2026, 8, 24, 10, 0),
        );
        expect(result, '오후 12:00까지 일시중지됨');
      },
    );

    test('분(minute)이 한 자리수면 앞에 0을 채운다', () {
      final result = formatPausedUntil(
        DateTime(2026, 8, 24, 10, 3),
        now: DateTime(2026, 8, 24, 9, 0),
      );
      expect(result, '오전 10:03까지 일시중지됨');
    });

    test(
      '"오늘 안"인지는 날짜(연/월/일)만 보고 판단한다 — 자정을 막 넘겨 몇 시간 '
      '차이 안 나도 날짜가 다르면 날짜 접두어가 붙어야 한다',
      () {
        final result = formatPausedUntil(
          DateTime(2026, 9, 1, 10, 0),
          now: DateTime(2026, 8, 31, 20, 0), // 14시간 차이지만 날짜는 다름
        );
        expect(result, '9/1 오전 10:00까지 일시중지됨');
      },
    );

    test('now를 생략하면 실제 DateTime.now() 기준으로도 예외 없이 문자열을 만든다', () {
      final result = formatPausedUntil(DateTime.now().add(const Duration(hours: 1)));
      expect(result, contains('까지 일시중지됨'));
    });
  });
}
