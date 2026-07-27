import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/wallet/coming_soon_sheet.dart';
import 'package:hoppin_rider/features/wallet/wallet_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'support/fake_payments_repository.dart';

/// PAY-01 (gated): tapping Add card while the payment service is off
/// (`503 PAYMENTS_DISABLED`) must show the designed "card payments coming
/// soon" state — NEVER a fake success, NEVER a crash, and NOT the old
/// "Almost there" AlertDialog. The add-card button stays VISIBLE (honest
/// gated state, per the no-holes DoD).
void main() {
  final theme = HoppinTheme.riderLight();

  Future<RecordingPaymentsRepository> pumpWallet(
    WidgetTester tester,
    RecordingPaymentsRepository repo,
  ) async {
    // A phone-sized surface so the modal sheet has room while it animates in.
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [paymentsRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: theme, home: const WalletScreen()),
      ),
    );
    // Bounded pump: let the autoDispose futures settle (never pumpAndSettle).
    await tester.pump(const Duration(milliseconds: 100));
    return repo;
  }

  testWidgets('Add card is visible even while payments are gated', (
    tester,
  ) async {
    await pumpWallet(tester, RecordingPaymentsRepository());
    expect(
      find.text('Add card'),
      findsOneWidget,
      reason: 'the add-card button stays visible — honest gated state',
    );
  });

  testWidgets('tapping Add card on a 503 shows the designed Coming-Soon state, '
      'not a fake success and not a crash', (tester) async {
    final repo = await pumpWallet(tester, RecordingPaymentsRepository());

    await tester.tap(find.text('Add card'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // The real backend call was attempted (BOUND, not faked).
    expect(
      repo.createSetupIntentCalls,
      1,
      reason: 'the gate is driven by a real createSetupIntent → 503',
    );

    // The designed unavailable-state renders …
    expect(
      find.byType(ComingSoonSheet),
      findsOneWidget,
      reason: 'the 503 must land on the designed Coming-Soon state',
    );
    expect(
      find.textContaining('coming soon', findRichText: true),
      findsWidgets,
    );

    // … and it is NOT the old "Almost there" dialog, NOT a fake success tick.
    expect(
      find.text('Almost there'),
      findsNothing,
      reason: 'the "Almost there" AlertDialog is retired',
    );
    expect(
      find.byIcon(Icons.check_circle),
      findsNothing,
      reason: 'no fake success tick — the card was never added',
    );
    expect(tester.takeException(), isNull, reason: 'no crash on the gate');
  });
}
