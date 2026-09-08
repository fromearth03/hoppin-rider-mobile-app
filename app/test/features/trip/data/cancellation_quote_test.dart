import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/data/ride_actions_repository.dart';

void main() {
  group('CancellationQuote.fromJson', () {
    test('reads a real fee', () {
      final q = CancellationQuote.fromJson({
        'fee_pence': 300,
        'free': false,
        'explain': 'Cancelling now costs £3.00.',
      });
      expect(q.free, isFalse);
      expect(q.feePence, 300);
      expect(q.explain, contains('£3.00'));
    });

    test('a free quote carries no amount', () {
      final q = CancellationQuote.fromJson({'fee_pence': 0, 'free': true});
      expect(q.free, isTrue);
      expect(q.feePence, 0);
      expect(q.explain, isNotEmpty);
    });

    test('"not free" with no amount falls back to free', () {
      // Warning a rider about a charge whose amount we do not have is worse than
      // saying nothing — they cannot act on it and it may not be true.
      final q = CancellationQuote.fromJson({'free': false, 'fee_pence': 0});
      expect(q.free, isTrue);
      expect(q.feePence, 0);
    });

    test('a failed request is free, so the ride stays escapable', () {
      const q = CancellationQuote.free();
      expect(q.free, isTrue);
      expect(q.explain, isNotEmpty);
    });
  });
}
