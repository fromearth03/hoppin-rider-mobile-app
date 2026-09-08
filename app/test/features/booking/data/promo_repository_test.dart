import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/booking/data/promo_repository.dart';

void main() {
  group('AppliedPromo.tryFromJson', () {
    test('reads a real discount', () {
      final p = AppliedPromo.tryFromJson({
        'promo_code': 'SUMMER25',
        'discount_type': 'flat_amount',
        'original_fare': 14.66,
        'discount_amount': 5.0,
        'new_fare': 9.66,
      });
      expect(p, isNotNull);
      expect(p!.code, 'SUMMER25');
      expect(p.discountAmount, 5.0);
      expect(p.newFare, 9.66);
    });

    test('rejects a response with no code', () {
      // Nothing to show and nothing to remove — rendering it would claim a
      // discount the rider cannot see on their fare.
      expect(AppliedPromo.tryFromJson({'discount_amount': 5.0}), isNull);
      expect(AppliedPromo.tryFromJson({'promo_code': '  ', 'discount_amount': 5.0}),
          isNull);
    });

    test('rejects a promo that took nothing off', () {
      // A "successful" apply that moved the fare by zero is not a success. It
      // would tell the rider they had saved money they have not.
      expect(
          AppliedPromo.tryFromJson(
              {'promo_code': 'DUD', 'discount_amount': 0}),
          isNull);
      expect(
          AppliedPromo.tryFromJson(
              {'promo_code': 'DUD', 'discount_amount': -2}),
          isNull);
    });

    test('accepts numbers sent as strings', () {
      final p = AppliedPromo.tryFromJson({
        'promo_code': 'TENOFF',
        'discount_amount': '2.27',
        'new_fare': '12.39',
      });
      expect(p, isNotNull);
      expect(p!.discountAmount, closeTo(2.27, 0.001));
      expect(p.newFare, closeTo(12.39, 0.001));
    });
  });
}
