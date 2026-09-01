import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/data/payment_methods_repository.dart';
import 'package:hoppin_rider/features/payments/presentation/widgets/payment_card_tile.dart';

const _card = SavedCard(
  paymentMethodId: 'pm_1',
  brand: 'Mastercard',
  last4: '4242',
  expMonth: 4,
  expYear: 2030,
  isDefault: false,
);

Widget _wrap(Widget child, {double width = 430}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  group('PaymentCardTile', () {
    testWidgets('keeps the card number on one line beside its action',
        (tester) async {
      // Rendering caught this: "Make default" is wider than the default
      // badge, so on a non-default row it squeezed the details column to
      // almost nothing and the card number wrapped one character per line —
      // an unreadable vertical stack of digits. No widget test saw it,
      // because every assertion still passed.
      await tester.pumpWidget(_wrap(
        PaymentCardTile(
          card: _card,
          onMakeDefault: () {},
          onRemove: () {},
        ),
      ));

      expect(tester.takeException(), isNull);

      final label = find.text('Mastercard');
      expect(label, findsOneWidget);

      // The details column must keep a usable share of the row rather than
      // collapsing to a sliver.
      final labelWidth = tester.getSize(label).width;
      expect(labelWidth, greaterThan(80),
          reason: 'the card number was crushed to a vertical stack');
    });

    testWidgets('renders at a narrow width without overflowing',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PaymentCardTile(
          card: _card,
          onMakeDefault: () {},
          onRemove: () {},
        ),
        width: 320,
      ));

      expect(tester.takeException(), isNull);
    });

    testWidgets('a default card shows a badge and no re-default action',
        (tester) async {
      // Offering to re-default the card that already is one is a no-op with
      // nothing to press.
      await tester.pumpWidget(_wrap(
        PaymentCardTile(
          card: SavedCard(
            paymentMethodId: _card.paymentMethodId,
            brand: _card.brand,
            last4: _card.last4,
            expMonth: _card.expMonth,
            expYear: _card.expYear,
            isDefault: true,
          ),
          onMakeDefault: null,
          onRemove: () {},
        ),
      ));

      // The frame's badge: the green verified check marks the default card;
      // there is no re-default affordance on it.
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(find.text('Make default'), findsNothing);
    });
  });
}
