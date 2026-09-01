import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/data/receipts_repository.dart';
import 'package:hoppin_rider/features/payments/presentation/ride_complete_screen.dart';
import 'package:hoppin_rider/features/payments/presentation/widgets/route_preview.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';
import 'package:hoppin_rider/features/trip/data/ride_actions_repository.dart';
import 'package:hoppin_rider/core/geo.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';
import 'package:mocktail/mocktail.dart';

class _GuardMockReceipts extends Mock implements ReceiptsRepository {}

class _MockActions extends Mock implements RideActionsRepository {}

const _rideId = 'r1';

Widget _harness(
  AsyncValue<Receipt> receiptState, {
  LiveTripInfo? detail,
  RideActionsRepository? actions,
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
        rideCompleteContextProvider(_rideId).overrideWith(
            (ref) => Future.value(detail ?? LiveTripInfo.awaiting(_rideId))),
        if (actions != null)
          rideActionsRepositoryProvider.overrideWithValue(actions),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
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

LiveTripInfo _detail({TripDriver? driver, List<LatLng>? route}) => LiveTripInfo(
      rideId: _rideId,
      status: LiveTripStatus.completed,
      driver: driver,
      baseFarePence: null,
      surgeMultiplier: null,
      surgePence: null,
      totalPence: const Pence(1238),
      currency: 'GBP',
      cancellationPolicy: null,
      waypoints: const [
        TripWaypoint(
            label: 'Hanley',
            distanceLabel: null,
            position: LatLng(53.0, -2.1)),
        TripWaypoint(
            label: 'Keele', distanceLabel: null, position: LatLng(53.1, -2.2)),
      ],
      route: route,
      steps: null,
      destinationLabel: 'Keele',
    );

const _george = TripDriver(
  name: 'George Oliver',
  avatarUrl: null,
  rating: 4.3,
  ratingCount: 1130,
  tripsCompleted: 1130,
  plate: 'RV 20 OZT',
  vehicleType: 'White Toyota Prius',
  seats: 4,
  bags: 2,
);

void main() {
  test('an empty ride id fails without touching the network', () async {
    // Shared by Ride Complete and Ride Details: an empty id only comes from
    // a hand-typed URL, and /rides//receipt is malformed. The provider must
    // throw locally, never call the repository.
    final repo = _GuardMockReceipts();
    final container = ProviderContainer(
      overrides: [receiptsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(rideReceiptProvider('').future),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'RIDE_NOT_FOUND')),
    );
    verifyZeroInteractions(repo);
  });

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

  testWidgets('shows the fare row from the real receipt fare_pence',
      (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt(
      farePence: 1000,
      totalPence: 1238,
    ))));
    await tester.pumpAndSettle();

    expect(find.text('Fare'), findsOneWidget);
    expect(find.text('£10.00'), findsOneWidget);
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

  testWidgets('shows a Done button', (tester) async {
    await tester.pumpWidget(_harness(AsyncData(_receipt())));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(HoppinButton, 'Done'), findsOneWidget);
  });

  group('Your Driver card', () {
    testWidgets('renders name and rating from the ride detail',
        (tester) async {
      await tester.pumpWidget(_harness(
        AsyncData(_receipt()),
        detail: _detail(driver: _george),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Your Driver'), findsOneWidget);
      expect(find.text('George Oliver'), findsOneWidget);
      expect(find.text('4.3'), findsOneWidget);
    });

    testWidgets('is absent when the ride detail carries no driver',
        (tester) async {
      await tester.pumpWidget(_harness(
        AsyncData(_receipt()),
        detail: _detail(driver: null),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Your Driver'), findsNothing);
    });
  });

  group('route preview', () {
    testWidgets('paints when the ride detail carries route points',
        (tester) async {
      await tester.pumpWidget(_harness(
        AsyncData(_receipt()),
        detail: _detail(route: const [
          LatLng(53.0, -2.1),
          LatLng(53.05, -2.15),
          LatLng(53.1, -2.2),
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(RoutePreview), findsOneWidget);
    });

    testWidgets('is absent without route points — no empty box', (tester) async {
      await tester.pumpWidget(_harness(
        AsyncData(_receipt()),
        detail: _detail(route: null),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(RoutePreview), findsNothing);
    });
  });

  group('rating prompt', () {
    testWidgets('tapping the fourth star posts a score of 4', (tester) async {
      final actions = _MockActions();
      when(() => actions.rateRide(any(), any(),
              comments: any(named: 'comments')))
          .thenAnswer((_) async => const Ok(null));

      await tester.pumpWidget(_harness(
        AsyncData(_receipt()),
        actions: actions,
      ));
      await tester.pumpAndSettle();

      expect(find.text('How was your ride?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rate-star-4')));
      await tester.pumpAndSettle();

      verify(() => actions.rateRide(_rideId, 4, comments: '')).called(1);
    });

    testWidgets('a rating can be changed in place — a second tap posts again',
        (tester) async {
      final actions = _MockActions();
      when(() => actions.rateRide(any(), any(),
              comments: any(named: 'comments')))
          .thenAnswer((_) async => const Ok(null));

      await tester.pumpWidget(_harness(
        AsyncData(_receipt()),
        actions: actions,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('rate-star-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rate-star-5')));
      await tester.pumpAndSettle();

      verify(() => actions.rateRide(_rideId, 2, comments: '')).called(1);
      verify(() => actions.rateRide(_rideId, 5, comments: '')).called(1);
    });

    testWidgets('a server rejection surfaces its message', (tester) async {
      final actions = _MockActions();
      when(() => actions.rateRide(any(), any(),
              comments: any(named: 'comments')))
          .thenAnswer((_) async => const Err(ApiException('ILLEGAL_TRANSITION',
              'you can only rate a completed ride', 409)));

      await tester.pumpWidget(_harness(
        AsyncData(_receipt()),
        actions: actions,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('rate-star-3')));
      await tester.pumpAndSettle();

      expect(find.text('you can only rate a completed ride'), findsOneWidget);
    });
  });
}
