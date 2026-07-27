import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/booking/widgets/fee_disclosure.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// CANCEL-01 — the pre-booking cancellation-fee DISCLOSURE (SL-9, the hard
/// MUST of Scope Lock §4.1: "Penalty rules MUST be clearly displayed to
/// passengers BEFORE booking"). This is MISSING-FE: the endpoint
/// (`GET /me/cancellation-fee-schedule`) does not exist yet, so the figures
/// come from a config stub — but the surface MUST render the REAL number,
/// NEVER a hidden "coming soon" seam. A fee "unavailable" empty state where a
/// number belongs is the exact bug this lane forbids (Pitfall 6).
void main() {
  // A plain config-stub schedule: free-cancel 2 min, £5.00 penalty. The
  // widget is dumb — schedule in, disclosure out.
  const schedule = CancellationFeeSchedule(
    freeCancelWindowSeconds: 120,
    penaltyAmountPounds: 5.00,
    currency: 'GBP',
  );

  Future<void> pump(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? HoppinTheme.riderLight(),
        home: const Scaffold(
          body: FeeDisclosure(schedule: schedule),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders the REAL free-cancel window and penalty figure '
      'pre-confirm — never an empty "unavailable" rung', (tester) async {
    await pump(tester);

    // The free-cancel window is shown as a human minute figure.
    expect(find.textContaining('2 min'), findsWidgets,
        reason: 'the free-cancel window must show the actual number of '
            'minutes, not a placeholder');
    // The penalty amount is a real pence-exact GBP figure.
    expect(find.textContaining('£5.00'), findsWidgets,
        reason: 'the penalty amount is the hard-MUST number — it must render');

    // NEVER a seam empty-state where a number belongs (Pitfall 6).
    expect(find.textContaining('unavailable'), findsNothing);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(find.textContaining('Coming soon'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discloses the figures are indicative (stub source) while still '
      'showing the number', (tester) async {
    await pump(tester);

    // The source is disclosed as indicative/estimated — honest about the
    // config stub — but the number above is still present.
    final indicative = find.textContaining(
      RegExp('indicative|estimate', caseSensitive: false),
    );
    expect(indicative, findsWidgets,
        reason: 'the stub source must be disclosed as indicative, per SL-9');
    // And the disclosure is still showing the real penalty alongside it.
    expect(find.textContaining('£5.00'), findsWidgets);
  });

  testWidgets('expands to the full schedule detail on tap', (tester) async {
    await pump(tester);

    // Collapsed: the plain-English one-liner carries the numbers.
    expect(find.textContaining('£5.00'), findsWidgets);

    // Tapping the disclosure reveals the fuller schedule detail — the
    // free-cancel window is spelled out in the expanded body.
    await tester.tap(find.byType(FeeDisclosure));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Free to cancel'), findsWidgets,
        reason: 'the expanded schedule spells out the free-cancel window');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in dark theme without a crash and keeps the figure',
      (tester) async {
    await pump(tester, theme: HoppinTheme.riderDark());

    expect(find.textContaining('£5.00'), findsWidgets);
    expect(find.textContaining('2 min'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
