import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show CardField;
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/payments/data/payment_methods_repository.dart';
import 'package:hoppin_rider/features/payments/presentation/payment_methods_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements PaymentMethodsRepository {}

SavedCard _card({
  String id = 'pm_1',
  String brand = 'visa',
  String last4 = '4242',
  int expMonth = 12,
  int expYear = 2030,
  bool isDefault = false,
}) =>
    SavedCard(
      paymentMethodId: id,
      brand: brand,
      last4: last4,
      expMonth: expMonth,
      expYear: expYear,
      isDefault: isDefault,
    );

Widget _harness(PaymentMethodsRepository repo,
        {Brightness brightness = Brightness.light}) =>
    ProviderScope(
      overrides: [
        paymentMethodsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const PaymentMethodsScreen(),
      ),
    );

void main() {
  late _MockRepo repo;

  setUp(() {
    repo = _MockRepo();
    when(() => repo.setDefault(any())).thenAnswer((_) async => const Ok(null));
    when(() => repo.remove(any())).thenAnswer((_) async => const Ok(null));
    when(() => repo.startAddCard()).thenAnswer(
        (_) async => const Ok(SetupIntent('secret_test')));
  });

  group('title and wording', () {
    testWidgets('titles the screen as card management, not a booking choice',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.text('Payment Methods'), findsOneWidget);
      expect(find.textContaining('Select Payment Method'), findsNothing);
    });

    testWidgets('never offers PayPal or Cash — neither exists in the API',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_card()]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.textContaining('PayPal'), findsNothing);
      expect(find.textContaining('Cash'), findsNothing);
    });
  });

  group('loading, empty, error', () {
    testWidgets('shows a loading indicator while the list is in flight',
        (tester) async {
      final completer = Completer<Result<List<SavedCard>>>();
      when(() => repo.list()).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(const Ok([]));
      await tester.pumpAndSettle();
    });

    testWidgets('shows an empty state with no saved cards', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.textContaining('No payment cards'), findsOneWidget);
    });

    testWidgets('shows the server error message on failure', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Err(
          ApiException('INTERNAL', 'Could not load your cards.', 500)));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.text('Could not load your cards.'), findsOneWidget);
    });
  });

  group('populated list', () {
    testWidgets('renders brand, masked last4, expiry and a default badge',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([
            _card(id: 'pm_1', brand: 'visa', last4: '4242', isDefault: true),
          ]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.textContaining('4242'), findsOneWidget);
      expect(find.textContaining('12/30'), findsOneWidget);
      // The frame's badge: green verified check on the default card.
      expect(find.byIcon(Icons.verified), findsOneWidget);
    });

    testWidgets('offers Make default only on non-default cards',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([
            _card(id: 'pm_1', isDefault: true),
            _card(id: 'pm_2', last4: '1111', isDefault: false),
          ]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      // The default card's badge is green and inert; the non-default card
      // carries the tappable grey badge (tooltip 'Make default').
      expect(find.byTooltip('Make default'), findsOneWidget);
    });

    testWidgets('tapping Make default calls the repository and refreshes',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([
            _card(id: 'pm_1', isDefault: true),
            _card(id: 'pm_2', last4: '1111', isDefault: false),
          ]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byTooltip('Make default'));
      await tester.pump();

      verify(() => repo.setDefault('pm_2')).called(1);
    });
  });

  group('remove card', () {
    testWidgets('asks for confirmation before removing', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_card()]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirmation dialog shown, repository not yet called.
      expect(find.byType(AlertDialog), findsOneWidget);
      verifyNever(() => repo.remove(any()));
    });

    testWidgets('removes the card only after confirming', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_card(id: 'pm_1')]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      verify(() => repo.remove('pm_1')).called(1);
    });

    testWidgets('dismissing the dialog leaves the card alone', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_card(id: 'pm_1')]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.remove(any()));
    });
  });

  group('add card', () {
    // These run under a plain `flutter test`, which never injects
    // STRIPE_PUBLISHABLE_KEY - so AppConfig.stripePublishableKey is empty and
    // the screen correctly refuses to start the Stripe flow. That is the
    // "key missing" state from docs/PAYMENTS-STRIPE.md, not a workaround: it
    // proves the screen never silently proceeds without a key. The full
    // CardField hand-off is exercised on-device / in the mobile app, since
    // it renders a real platform view that a widget test cannot drive.
    testWidgets(
        'without a configured key, tapping Add card explains why instead of opening the SDK sheet',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Payment Methods'));
      await tester.pump();

      // No PCI-violating raw card-number entry, ever.
      expect(find.widgetWithText(TextField, 'Card Number'), findsNothing);
      expect(find.text('Card Number'), findsNothing);
      expect(find.byType(CardField), findsNothing);
      expect(find.text('Add a card'), findsOneWidget);
      expect(find.textContaining('unavailable'), findsOneWidget);

      // Nothing was started against the backend.
      verifyNever(() => repo.startAddCard());
    });

    testWidgets('never shows a raw TextField for card number, CVV or expiry anywhere on the screen',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_card()]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      for (final label in ['Card Number', 'CVV', 'CVC', 'Expiry', 'Expiration']) {
        expect(find.widgetWithText(TextField, label), findsNothing);
        expect(find.text(label), findsNothing);
      }
    });
  });

  testWidgets('renders in dark mode', (tester) async {
    when(() => repo.list()).thenAnswer((_) async => Ok([
          _card(isDefault: true),
        ]));

    await tester.pumpWidget(_harness(repo, brightness: Brightness.dark));
    await tester.pump();

    expect(find.text('Payment Methods'), findsOneWidget);
    expect(find.textContaining('4242'), findsOneWidget);
  });

  testWidgets(
      'dark mode: Add card without a key still explains why, never a raw PAN field',
      (tester) async {
    when(() => repo.list()).thenAnswer((_) async => const Ok([]));

    await tester.pumpWidget(_harness(repo, brightness: Brightness.dark));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Payment Methods'));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Card Number'), findsNothing);
    expect(find.byType(CardField), findsNothing);
    expect(find.textContaining('unavailable'), findsOneWidget);
  });
}
