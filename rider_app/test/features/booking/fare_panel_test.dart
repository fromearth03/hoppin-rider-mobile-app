import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/booking/widgets/fare_panel.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Lane C — pricing transparency (§3.4 / BOOK-05 / BOOK-06).
///
/// Two truths are pinned here:
/// - the surge row renders at the ×1.00 baseline with a plain-English "no
///   surge" label — never hidden behind `if (q.surge > 1.0)`. This is the
///   regression guard against re-introducing the §3.4 hiding bug;
/// - the fare is framed as an estimate range that settles at completion,
///   with the full base/distance/time/surge/total breakdown pre-confirm.
void main() {
  group('FarePanel — always-visible surge (BOOK-06)', () {
    testWidgets('surge row renders at ×1.0 baseline with a plain-English '
        'no-surge label', (tester) async {
      // The demo quote is a true ×1.0 baseline (demo world never surges).
      expect(_baselineEstimate.estimate.surge, 1.0);

      await tester.pumpWidget(_panelHarness(estimate: _baselineEstimate));

      // Open the progressive-disclosure breakdown.
      await tester.tap(find.text('Fare breakdown'));
      await tester.pump(const Duration(milliseconds: 300));

      // §3.4: the surge line is visible even at baseline — a rider always
      // sees surge is switched off, it is never silently absent.
      expect(
        find.text('Surge — none right now'),
        findsOneWidget,
        reason:
            'the surge row must render at ×1.0 — the if (q.surge > 1.0) '
            'guard is a §3.4 compliance bug',
      );
    });

    testWidgets('surge row shows the multiplier and a busy label when surge '
        'is active', (tester) async {
      final surged = _surgedEstimate(1.6);

      await tester.pumpWidget(_panelHarness(estimate: surged));
      await tester.tap(find.text('Fare breakdown'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Surge ×1.60 (busy — higher demand)'),
        findsOneWidget,
        reason: 'active surge must name the multiplier in plain English',
      );
      expect(find.text('Surge — none right now'), findsNothing);
    });
  });

  group('FarePanel — estimate-range framing (BOOK-05)', () {
    testWidgets('full breakdown renders and the total is framed as an '
        'estimate that settles at completion', (tester) async {
      await tester.pumpWidget(_panelHarness(estimate: _baselineEstimate));
      final q = _baselineEstimate.estimate;

      // Estimate-range framing sits near the hero total, pre-confirm.
      expect(
        find.text('Estimated — final fare settled at drop-off'),
        findsOneWidget,
        reason:
            'BOOK-05: the total must read as an estimate range that settles '
            'at completion, not a silent fixed number',
      );

      await tester.tap(find.text('Fare breakdown'));
      await tester.pump(const Duration(milliseconds: 300));

      // Full breakdown: base / distance / time / surge / total all present.
      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text(formatPounds(q.base)), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text(formatPounds(q.distance)), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text(formatPounds(q.time)), findsOneWidget);
      expect(find.text('Surge — none right now'), findsOneWidget);
      expect(find.text(formatPounds(q.total)), findsOneWidget);
    });
  });
}

// One ThemeData reused across every pump — a fresh instance restarts
// AnimatedTheme + Material implicit animations (test-harness trap).
final _light = HoppinTheme.riderLight();

/// A true ×1.0 baseline quote (£6.39 Rail Station → New Cross) — the demo
/// world never surges, so this pins the baseline-visible-surge truth.
final _baselineEstimate = estimateBetween(
  pickupLat: 52.5877,
  pickupLng: -2.1200,
  dropoffLat: 52.6046,
  dropoffLng: -2.0930,
);

/// The baseline quote re-priced with an active surge multiplier — freezed
/// copyWith keeps every other figure identical so only the surge display
/// rule is under test.
FareEstimate _surgedEstimate(double surge) => _baselineEstimate.copyWith(
      estimate: _baselineEstimate.estimate.copyWith(surge: surge),
    );

Widget _panelHarness({required FareEstimate estimate}) {
  return MaterialApp(
    theme: _light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: FarePanel(
          estimate: estimate,
          pickupLabel: 'Wolverhampton Rail Station',
          destinationLabel: 'New Cross Hospital',
        ),
      ),
    ),
  );
}
