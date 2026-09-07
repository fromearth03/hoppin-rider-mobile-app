import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/profile/data/cancellation_rate_repository.dart';
import 'package:hoppin_rider/features/profile/presentation/widgets/cancellation_rate_card.dart';

RiderCancellationRate _rate({
  int total = 10,
  int cancelled = 7,
  double? pct = 70,
  bool over = true,
  bool active = true,
  int minRides = 5,
}) =>
    RiderCancellationRate(
      windowDays: 30,
      ridesTotal: total,
      cancelled: cancelled,
      ratePct: pct,
      overThreshold: over,
      thresholdPct: 60,
      minRides: minRides,
      policyActive: active,
    );

Widget _harness(RiderCancellationRate? rate) => ProviderScope(
      overrides: [
        myCancellationRateProvider.overrideWith((ref) async => rate),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: CancellationRateCard()),
      ),
    );

void main() {
  testWidgets('shows the rate with the counts behind it', (tester) async {
    await tester.pumpWidget(_harness(_rate()));
    await tester.pumpAndSettle();

    expect(find.text('70%'), findsOneWidget);
    // The counts matter: 70% means something very different at 10 bookings
    // than at 200, and the bare percentage invites panic.
    expect(find.textContaining('7 of your last 10 bookings'), findsOneWidget);
  });

  testWidgets('tells a rider over the line how it recovers', (tester) async {
    await tester.pumpWidget(_harness(_rate()));
    await tester.pumpAndSettle();

    // Not just "you are over the limit" — that tells them off without telling
    // them anything they can act on.
    expect(find.textContaining('comes back down as you complete rides'),
        findsOneWidget);
  });

  testWidgets('is hidden entirely for a rider with no rides', (tester) async {
    // A brand-new rider does not need a compliance meter before their first trip.
    await tester.pumpWidget(_harness(_rate(total: 0, cancelled: 0, pct: null)));
    await tester.pumpAndSettle();

    expect(find.text('Your cancellations'), findsNothing);
  });

  testWidgets('says the rate is not counting yet below the minimum',
      (tester) async {
    await tester.pumpWidget(
        _harness(_rate(total: 2, cancelled: 1, pct: 50, over: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining('starts counting once you have 5 bookings'),
        findsOneWidget);
  });

  testWidgets('a failed fetch leaves the profile screen intact',
      (tester) async {
    // The provider degrades to null; this card sits on a screen the rider
    // opened for something else and must not break it.
    await tester.pumpWidget(_harness(null));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Your cancellations'), findsNothing);
  });
}
