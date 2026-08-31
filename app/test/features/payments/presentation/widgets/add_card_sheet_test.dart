import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/presentation/widgets/add_card_sheet.dart';

/// [AddCardSheet] is the one place a card is ever collected. These tests
/// pin down the PCI-relevant guarantee: the only card-entry widget on
/// screen is Stripe's own [CardField] — never a TextField this app owns
/// for the number, CVV or expiry.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<String?> Function({required bool makeDefault}) onConfirm,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AddCardSheet.show(
              context,
              clientSecret: 'secret_test',
              onConfirm: onConfirm,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Stripe CardField and no raw PAN/CVV/expiry field',
      (tester) async {
    await pumpSheet(tester, onConfirm: ({required makeDefault}) async => null);

    expect(find.byType(CardField), findsOneWidget);

    for (final label in ['Card Number', 'CVV', 'CVC', 'Expiry', 'Expiration']) {
      expect(find.widgetWithText(TextField, label), findsNothing);
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('Save starts disabled until the card field reports complete',
      (tester) async {
    await pumpSheet(tester, onConfirm: ({required makeDefault}) async => null);

    final saveButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('offers Set as default and a terms line', (tester) async {
    await pumpSheet(tester, onConfirm: ({required makeDefault}) async => null);

    expect(find.text('Set as default'), findsOneWidget);
    expect(find.textContaining('Terms of Service'), findsOneWidget);
  });

  testWidgets('Cancel closes the sheet without saving', (tester) async {
    var confirmCalled = false;
    await pumpSheet(
      tester,
      onConfirm: ({required makeDefault}) async {
        confirmCalled = true;
        return null;
      },
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AddCardSheet), findsNothing);
    expect(confirmCalled, isFalse);
  });

  testWidgets('renders in dark mode with the same Stripe-only card entry',
      (tester) async {
    await pumpSheet(
      tester,
      onConfirm: ({required makeDefault}) async => null,
      brightness: Brightness.dark,
    );

    expect(find.byType(CardField), findsOneWidget);
    expect(find.text('Add a card'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Card Number'), findsNothing);
  });
}
