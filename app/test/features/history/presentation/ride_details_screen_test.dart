import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/data/receipts_repository.dart';
import 'package:hoppin_rider/features/payments/presentation/ride_complete_screen.dart'
    show rideReceiptProvider;
import 'package:hoppin_rider/features/history/presentation/ride_details_screen.dart';

const _rideId = 'r1';

Widget _harness(
  AsyncValue<Receipt> receiptState, {
  Brightness brightness = Brightness.light,
}) =>
    ProviderScope(
      overrides: [
        rideReceiptProvider(_rideId).overrideWith((ref) {
          return switch (receiptState) {
            AsyncData(:final value) => Future.value(value),
            AsyncError(:final error) => Future<Receipt>.error(error),
            // A Completer that never completes keeps the provider in
            // AsyncLoading without leaving a dangling Timer at teardown.
            _ => Completer<Receipt>().future,
          };
        }),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const RideDetailsScreen(rideId: _rideId),
      ),
    );

Receipt _receipt({
  int? farePence = 500,
  int? waitingPence = 0,
  int? totalPence = 886,
  double? distanceMiles = 4.7,
  String currency = 'GBP',
  String status = 'captured',
  DateTime? pickupTime,
  DateTime? dropoffTime,
}) =>
    Receipt(
      rideId: _rideId,
      rideCategory: 'standard',
      farePence: farePence == null ? null : Pence(farePence),
      waitingPence: waitingPence == null ? null : Pence(waitingPence),
      totalPence: totalPence == null ? null : Pence(totalPence),
      currency: currency,
      status: status,
      distanceMiles: distanceMiles,
      pickupTime: pickupTime,
      dropoffTime: dropoffTime,
      providerPaymentId: 'pi_123',
    );

void main() {
  testWidgets('shows a loading indicator while the receipt is in flight',
      (tester) async {
    await tester.pumpWidget(_harness(const AsyncLoading()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the server error message on failure', (tester) async {
    await tester.pumpWidget(_harness(AsyncError(
      const ApiException('NOT_FOUND', 'Ride not found', 404),
      StackTrace.empty,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Ride not found'), findsOneWidget);
  });

  testWidgets('has the Ride Details title', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt())));
    await tester.pumpAndSettle();

    expect(find.text('Ride Details'), findsOneWidget);
  });

  testWidgets('renders the total fare and distance', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      totalPence: 886,
      distanceMiles: 4.7,
    ))));
    await tester.pumpAndSettle();

    // Shown once in the journey-summary stat and once in the fare card, the
    // same layout already used on Ride Complete and Trip Details.
    expect(find.text('£8.86'), findsNWidgets(2));
    expect(find.text('4.7 mi'), findsOneWidget);
  });

  testWidgets('never renders km', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt())));
    await tester.pumpAndSettle();

    expect(find.textContaining('km'), findsNothing);
  });

  testWidgets('a null total renders an honest not-charged state, never £0.00',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      farePence: null,
      waitingPence: null,
      totalPence: null,
      status: 'pending',
    ))));
    await tester.pumpAndSettle();

    expect(find.textContaining('£0.00'), findsNothing);
    expect(find.textContaining('Not'), findsWidgets);
  });

  testWidgets('hides the waiting row when the waiting charge is zero',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(waitingPence: 0))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Wait'), findsNothing);
  });

  testWidgets('shows the waiting row when the waiting charge is non-zero',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      waitingPence: 250,
      totalPence: 1136,
    ))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Wait'), findsOneWidget);
    expect(find.text('£2.50'), findsOneWidget);
  });

  testWidgets('does not render platform commission anywhere', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt())));
    await tester.pumpAndSettle();

    expect(find.textContaining('commission'), findsNothing);
    expect(find.textContaining('Commission'), findsNothing);
  });

  testWidgets('does not fabricate a driver block the receipt has no data for',
      (tester) async {
    // GET /rides/:id/receipt has no driver fields at all. The Figma "Ride
    // Details" frame draws a driver card, rating, plate and vehicle type,
    // but rendering any of that here would be inventing data — omitted per
    // the same reasoning already recorded for Ride Complete.
    await tester.pumpWidget(_harness(AsyncData(_receipt())));
    await tester.pumpAndSettle();

    expect(find.textContaining('Complete Rides'), findsNothing);
    expect(find.textContaining('Vehicle Number'), findsNothing);
  });

  testWidgets('handles null pickup/dropoff timestamps without crashing',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      pickupTime: null,
      dropoffTime: null,
    ))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ride Details'), findsOneWidget);
  });

  testWidgets('renders in dark mode without error', (tester) async {
    await tester.pumpWidget(_harness(
      AsyncData(_receipt()),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ride Details'), findsOneWidget);
  });
}
