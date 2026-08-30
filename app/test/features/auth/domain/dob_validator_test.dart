import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/domain/dob_validator.dart';

void main() {
  final now = DateTime(2026, 8, 30);

  group('DobValidator.validate', () {
    test('accepts an adult', () {
      expect(DobValidator.validate(DateTime(1990, 12, 10), now: now), isNull);
    });

    test('accepts someone who turned 13 today', () {
      expect(DobValidator.validate(DateTime(2013, 8, 30), now: now), isNull);
    });

    test('rejects someone who turns 13 tomorrow', () {
      final result = DobValidator.validate(DateTime(2013, 8, 31), now: now);
      expect(result, isNotNull);
      expect(result, contains('13'));
    });

    test('rejects a future date', () {
      expect(DobValidator.validate(DateTime(2027, 1, 1), now: now), isNotNull);
    });

    test('rejects a year before 1900, matching the server', () {
      expect(DobValidator.validate(DateTime(1899, 12, 31), now: now), isNotNull);
    });

    test('rejects null – DOB is required at signup', () {
      expect(DobValidator.validate(null, now: now), isNotNull);
    });

    test('handles a 29 February birthday in a non-leap year', () {
      // Born 2013-02-29 does not exist; 2012-02-29 turns 13 in 2025.
      expect(DobValidator.validate(DateTime(2012, 2, 29), now: now), isNull);
    });
  });

  group('DobValidator.format', () {
    test('pads to YYYY-MM-DD as the API requires', () {
      expect(DobValidator.format(DateTime(1990, 1, 5)), '1990-01-05');
    });
  });
}
