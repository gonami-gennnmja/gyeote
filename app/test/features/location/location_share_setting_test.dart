import 'package:flutter_test/flutter_test.dart';
import 'package:gyeote/features/location/data/models/location_share_setting.dart';

void main() {
  group('LocationShareSetting.isPaused', () {
    test('false when pausedUntil is null', () {
      final setting = LocationShareSetting(
        userId: 'u1',
        relationshipGroupId: 'g1',
        mode: 'precise',
        pausedUntil: null,
      );
      expect(setting.isPaused, isFalse);
    });

    test('true when pausedUntil is in the future', () {
      final setting = LocationShareSetting(
        userId: 'u1',
        relationshipGroupId: 'g1',
        mode: 'precise',
        pausedUntil: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      );
      expect(setting.isPaused, isTrue);
    });

    test('false when pausedUntil is in the past (expired pause)', () {
      final setting = LocationShareSetting(
        userId: 'u1',
        relationshipGroupId: 'g1',
        mode: 'precise',
        pausedUntil: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      expect(setting.isPaused, isFalse);
    });
  });

  group('LocationShareSetting.isOff', () {
    test('true for mode=off', () {
      expect(LocationShareSetting.off(userId: 'u1', relationshipGroupId: 'g1').isOff,
          isTrue);
    });

    test('false for mode=precise/approx', () {
      const precise = LocationShareSetting(
        userId: 'u1',
        relationshipGroupId: 'g1',
        mode: 'precise',
        pausedUntil: null,
      );
      expect(precise.isOff, isFalse);
    });
  });

  group('LocationShareSetting.fromJson', () {
    test('defaults to off when mode is missing', () {
      final setting = LocationShareSetting.fromJson({
        'user_id': 'u1',
        'relationship_group_id': 'g1',
        'paused_until': null,
      });
      expect(setting.mode, 'off');
      expect(setting.pausedUntil, isNull);
    });

    test('parses a paused row', () {
      final setting = LocationShareSetting.fromJson({
        'user_id': 'u1',
        'relationship_group_id': 'g1',
        'mode': 'approx',
        'paused_until': '2026-08-23T13:00:00Z',
      });
      expect(setting.mode, 'approx');
      expect(setting.pausedUntil, DateTime.parse('2026-08-23T13:00:00Z'));
    });
  });
}
