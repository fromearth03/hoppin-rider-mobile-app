import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/money.dart';

void main() {
  test('renders the symbol whatever casing the API sends', () {
    // Stripe stores currencies lowercase, so a receipt arrives as "gbp".
    // intl's symbol table is keyed on the uppercase code, so it printed the
    // code verbatim — "gbp79.44" on a rider's trip summary.
    expect(const Pence(7944).format(currency: 'gbp'), '£79.44');
    expect(const Pence(7944).format(currency: 'GBP'), '£79.44');
    expect(const Pence(7944).format(currency: ' gbp '), '£79.44');
  });

  test('a missing currency falls back to sterling rather than a bare number', () {
    expect(const Pence(1238).format(currency: ''), '£12.38');
    expect(const Pence(1238).format(), '£12.38');
  });

  test('negatives keep their sign', () {
    expect(const Pence(-500).format(currency: 'gbp'), '-£5.00');
  });
}
