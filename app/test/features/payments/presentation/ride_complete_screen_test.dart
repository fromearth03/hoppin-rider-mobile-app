import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/data/receipts_repository.dart';
import 'package:hoppin_rider/features/payments/presentation/ride_complete_screen.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';

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
            // A Completer that is never completed keeps the provider in
            // AsyncLoading without leaving a pending Timer behind for
            // flutter_test to complain about at teardown.
            _ => Completer<Receipt>().future,
          };
        }),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const RideCompleteScreen(rideId: _rideId),
      ),
    );

Receipt _receipt({
  int? farePence = 1000,
  int? waitingPence = 0,
  int? totalPence = 1238,
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
      const ApiException('NOT_FOUND', 'Receipt not found', 404),
      StackTrace.empty,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Receipt not found'), findsOneWidget);
  });

  testWidgets('renders the total fare and distance for a charged ride',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      totalPence: 1238,
      distanceMiles: 4.7,
    ))));
    await tester.pumpAndSettle();

    expect(find.text('Ride Completed'), findsOneWidget);
    // The design repeats the total in both the Journey Summary stat and the
    // Total Fare card, so two matches is correct here.
    expect(find.text('£12.38'), findsNWidgets(2));
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
    // Shown once in the summary stat and once in the fare card, same as the
    // charged case above.
    expect(find.textContaining('Not charged'), findsNWidgets(2));
  });

  testWidgets('hides the waiting charge when it is zero', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      waitingPence: 0,
    ))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Wait'), findsNothing);
  });

  testWidgets('shows the waiting charge when it is non-zero', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      waitingPence: 250,
      totalPence: 1250,
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

  testWidgets('handles a null pickup/dropoff time without crashing',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      pickupTime: null,
      dropoffTime: null,
    ))));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ride Completed'), findsOneWidget);
  });

  testWidgets('shows a duration when both timestamps are present',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      pickupTime: DateTime.utc(2026, 8, 31, 9, 0),
      dropoffTime: DateTime.utc(2026, 8, 31, 9, 13),
    ))));
    await tester.pumpAndSettle();

    expect(find.text('13 min'), findsOneWidget);
  });

  testWidgets('renders in dark mode without error', (tester) async {
    await tester.pumpWidget(_harness(
      AsyncData(_receipt()),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ride Completed'), findsOneWidget);
  });

  testWidgets('shows a Done button', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt())));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(HoppinButton, 'Done'), findsOneWidget);
  });
}
