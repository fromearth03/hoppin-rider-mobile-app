import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/booking/widgets/payment_method_row.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// C-1 — the FABRICATED PAYMENT CARD on the money path.
///
/// The confirm screen used to render a `const` widget hardcoding
/// "Visa Classic / **** **** **** 1234 / Default". It read no provider and took
/// no argument: every rider was told, on the last screen before committing
/// money, that a card they may never have owned would be charged. Meanwhile the
/// Wallet — reading the REAL `paymentMethodsProvider` — could say "No saved
/// cards yet" in the same session, and on live today all four payment endpoints
/// answer `503 PAYMENTS_DISABLED`, so no default card can exist at all.
///
/// These tests pin the fix:
///   • the fabricated literals cannot come back (source grep over apps/rider/lib);
///   • an EMPTY card list shows the honest rung and NO card;
///   • a REAL card renders its REAL brand + last4;
///   • `503 PAYMENTS_DISABLED` names the disabled service;
///   • an unknown read failure says "we can't check" — it never asserts
///     emptiness out of ignorance.
void main() {
  final theme = HoppinTheme.riderLight();

  const visa = PaymentMethod(
    paymentMethodId: 'pm_visa_4242',
    brand: 'visa',
    last4: '4242',
    expMonth: 8,
    expYear: 2029,
    isDefault: true,
  );

  Future<void> pumpRow(
    WidgetTester tester,
    PaymentsRepository repo,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [paymentsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: PaymentMethodRow()),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  group('C-1: the confirm-screen payment row tells the truth', () {
    test('the fabricated card literals are GONE from apps/rider/lib', () {
      final root = Directory('lib');
      expect(
        root.existsSync(),
        isTrue,
        reason: 'the grep must run against the real rider source tree',
      );

      final offenders = <String>[];
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        // A hard literal ban, comments included: the strings must not survive
        // anywhere in the rider source, so no future edit can resurrect them by
        // copy-paste out of a doc comment.
        if (source.contains('Visa Classic')) {
          offenders.add('${entity.path} (Visa Classic)');
        }
        if (source.contains('1234')) {
          offenders.add('${entity.path} (1234)');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'no rider source file may carry the fabricated card literals — a '
            'hardcoded brand or last4 on the money path tells a rider what will '
            'be charged when the app never read a payment method. Offenders: '
            '$offenders',
      );
    });

    testWidgets('an EMPTY card list shows the honest "no payment method" rung '
        'and NO card', (tester) async {
      await pumpRow(tester, _FakePayments(cards: const []));

      expect(
        find.text('No payment method saved'),
        findsOneWidget,
        reason:
            'a rider with no saved card must be told so before they commit '
            'money — never shown a card they do not have',
      );
      expect(
        find.byType(StatusPill),
        findsNothing,
        reason: 'a "Default" pill on an empty account is a fabrication',
      );
      expect(
        find.textContaining('••••'),
        findsNothing,
        reason: 'no masked digits may render when there is no card',
      );
    });

    testWidgets('a REAL default card renders its REAL brand and last4', (
      tester,
    ) async {
      await pumpRow(tester, _FakePayments(cards: const [visa]));

      expect(
        find.text('VISA'),
        findsOneWidget,
        reason: 'the brand must come from the server PaymentMethod, not a '
            'literal in the view',
      );
      expect(
        find.textContaining('4242'),
        findsOneWidget,
        reason: "the rider's real last4 must render — this is the card that "
            'will actually be charged',
      );
      expect(
        find.textContaining('1234'),
        findsNothing,
        reason: 'the fabricated tail must never appear again',
      );
      expect(
        find.text('Default'),
        findsOneWidget,
        reason: 'the Default pill renders because the SERVER flagged this card '
            'default — not because the widget assumed it',
      );
    });

    testWidgets('a card the server did NOT flag default renders without the '
        'Default pill', (tester) async {
      await pumpRow(
        tester,
        _FakePayments(
          cards: const [
            PaymentMethod(
              paymentMethodId: 'pm_mc_5555',
              brand: 'mastercard',
              last4: '5555',
            ),
          ],
        ),
      );

      expect(
        find.textContaining('5555'),
        findsOneWidget,
        reason: 'the only saved card is still the one that would be charged',
      );
      expect(
        find.text('Default'),
        findsNothing,
        reason: 'the app must not crown a card default when the server did not',
      );
    });

    testWidgets('503 PAYMENTS_DISABLED names the disabled service and asserts '
        'no card', (tester) async {
      await pumpRow(
        tester,
        _FakePayments(
          error: const ApiException(
            statusCode: 503,
            message: 'Card payments are temporarily unavailable.',
            code: 'PAYMENTS_DISABLED',
          ),
        ),
      );

      expect(
        find.text("Card payments aren't switched on yet"),
        findsOneWidget,
        reason: 'while the payment service is off no card CAN be charged — the '
            'rider must be told that plainly on the money path',
      );
      expect(
        find.byType(StatusPill),
        findsNothing,
        reason: 'no Default pill may render when payments are disabled',
      );
    });

    testWidgets('an unreadable card list says "we can\'t check" — it never '
        'claims the rider has no cards', (tester) async {
      await pumpRow(tester, _FakePayments(error: Exception('network down')));

      expect(
        find.text("We can't check your payment method"),
        findsOneWidget,
        reason:
            'asserting emptiness when the truth is ignorance is a lie — a read '
            'failure must be distinguished from a genuinely empty wallet',
      );
      expect(
        find.text('No payment method saved'),
        findsNothing,
        reason: 'we do NOT know the wallet is empty; we only know we could not '
            'read it',
      );
      expect(
        find.byType(StatusPill),
        findsNothing,
        reason: 'no card, no brand, no digits, no pill when we cannot read',
      );
    });
  });
}

/// A [PaymentsRepository] whose card read is scripted: a list, or a throw.
class _FakePayments implements PaymentsRepository {
  _FakePayments({this.cards = const [], this.error});

  final List<PaymentMethod> cards;
  final Object? error;

  @override
  Future<List<PaymentMethod>> paymentMethods() async {
    if (error != null) throw error!;
    return cards;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
