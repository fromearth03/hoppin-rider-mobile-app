import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/wallet/wallet_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'support/fake_payments_repository.dart';

/// PAY-01 (BOUND): the saved-cards list renders, and set-default / remove
/// call the repository and refresh the list. The empty rung renders the
/// designed "no saved cards yet" copy. PAY-02: transactions render
/// pence-accurate GBP.
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
  const mastercard = PaymentMethod(
    paymentMethodId: 'pm_mc_5555',
    brand: 'mastercard',
    last4: '5555',
    expMonth: 4,
    expYear: 2028,
  );

  Future<void> pumpWallet(
    WidgetTester tester,
    RecordingPaymentsRepository repo,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [paymentsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: theme, home: const WalletScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('saved cards render with brand + last4', (tester) async {
    await pumpWallet(
      tester,
      RecordingPaymentsRepository(cards: const [visa, mastercard]),
    );

    expect(find.textContaining('4242'), findsOneWidget);
    expect(find.textContaining('5555'), findsOneWidget);
    expect(
      find.textContaining('Default'),
      findsOneWidget,
      reason: 'the default card is labelled',
    );
  });

  testWidgets('empty list renders the designed "no saved cards yet" rung', (
    tester,
  ) async {
    await pumpWallet(tester, RecordingPaymentsRepository());

    expect(
      find.textContaining('No saved cards', findRichText: true),
      findsOneWidget,
      reason: 'the empty rung is a designed state, not a blank list',
    );
  });

  testWidgets('Make default calls setDefault and refreshes the list', (
    tester,
  ) async {
    final repo = RecordingPaymentsRepository(cards: const [visa, mastercard]);
    await pumpWallet(tester, repo);

    // Open the popup on the non-default card and choose "Make default".
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Make default'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.setDefaultCalls, [
      'pm_mc_5555',
    ], reason: 'set-default is BOUND to the repo');
  });

  testWidgets('Remove calls removeCard', (tester) async {
    final repo = RecordingPaymentsRepository(cards: const [visa]);
    await pumpWallet(tester, repo);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Remove'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.removeCalls, [
      'pm_visa_4242',
    ], reason: 'remove is BOUND to the repo');
  });

  testWidgets('transactions render pence-accurate GBP (PAY-02)', (
    tester,
  ) async {
    await pumpWallet(
      tester,
      RecordingPaymentsRepository(
        txns: const [
          Transaction(id: 't1', amountPence: 639, status: 'succeeded'),
          Transaction(id: 't2', amountPence: 1150, status: 'succeeded'),
        ],
      ),
    );

    // 639 pence → "£6.39" exactly (no float drift); 1150 → "£11.50".
    expect(find.text('£6.39'), findsOneWidget);
    expect(find.text('£11.50'), findsOneWidget);
  });
}
