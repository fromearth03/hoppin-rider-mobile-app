import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/geo.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/fare_confirm_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockFareRepository extends Mock implements FareRepository {}

const _pickup = LatLng(52.586, -2.128);
const _dropoff = LatLng(52.593, -2.110);

const _standard = VehicleCategory(
  id: 'a',
  name: 'Standard',
  seats: 4,
  bags: 2,
  priceMultiplier: 1.0,
);
const _estate = VehicleCategory(
  id: 'b',
  name: 'Estate',
  seats: 5,
  bags: 4,
  priceMultiplier: 1.3,
);

FareEstimate _singleLegEstimate({
  int totalPence = 2500,
  int durationSeconds = 300,
}) =>
    FareEstimate(
      totalPence: Pence(totalPence),
      currency: 'GBP',
      distanceMeters: 4000,
      durationSeconds: durationSeconds,
      legs: const [],
      isMultiStop: false,
      stopsCount: 0,
      route: null,
      discountPence: Pence.zero,
      discountPct: 0,
      discountKnown: true,
      etaSource: 'model',
    );

FareEstimate _multiStopEstimate() => const FareEstimate(
      totalPence: Pence(14000),
      currency: 'GBP',
      distanceMeters: 9300,
      durationSeconds: 1380,
      legs: [
        FareLeg(
          seq: 0,
          toLabel: 'Tesco',
          distanceMeters: 1400,
          durationSeconds: 300,
          farePence: Pence(3000),
        ),
        FareLeg(
          seq: 1,
          toLabel: "Mum's",
          distanceMeters: 6100,
          durationSeconds: 720,
          farePence: Pence(9000),
        ),
        FareLeg(
          seq: 2,
          toLabel: 'Dropoff',
          distanceMeters: 1800,
          durationSeconds: 360,
          farePence: Pence(2000),
        ),
      ],
      isMultiStop: true,
      stopsCount: 2,
      route: null,
      discountPence: Pence.zero,
      discountPct: 0,
      discountKnown: false,
      etaSource: 'model',
    );

Widget _harness(
  FareRepository repo, {
  Brightness brightness = Brightness.light,
  List<VehicleCategory> categories = const [_standard],
  List<LatLng> waypoints = const [],
  void Function(VehicleCategory, FareEstimate?)? onConfirm,
}) =>
    ProviderScope(
      overrides: [
        fareRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: FareConfirmScreen(
          pickup: _pickup,
          dropoff: _dropoff,
          waypoints: waypoints,
          categories: categories,
          onConfirm: onConfirm,
        ),
      ),
    );

void main() {
  late _MockFareRepository repo;

  setUpAll(() {
    registerFallbackValue(_pickup);
  });

  setUp(() {
    repo = _MockFareRepository();
  });

  testWidgets('shows a loading indicator while quotes are in flight',
      (tester) async {
    when(() => repo.estimate(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return Ok(_singleLegEstimate());
    });

    await tester.pumpWidget(_harness(repo));
    await tester.pump();

    // The redesigned sheet quotes invisibly until a vehicle is selected;
    // the in-flight state shows on the fare card once one is.
    await tester.tap(find.text('Standard'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Drain the pending timer so the widget tree has nothing outstanding
    // when the test tears down.
    await tester.pump(const Duration(seconds: 1));
  });

  group('populated', () {
    testWidgets('renders a card per vehicle category with its fare',
        (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: 'a',
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_singleLegEstimate(totalPence: 2500)));
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: 'b',
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_singleLegEstimate(totalPence: 3250)));

      await tester.pumpWidget(_harness(repo, categories: const [_standard, _estate]));
      await tester.pumpAndSettle();

      // Both categories render as cards; each one's REAL quote appears on
      // the fare card as it is selected (`Ride Details.png` shows one fare
      // at a time, for the chosen vehicle).
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Estate'), findsOneWidget);

      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();
      expect(find.text(Pence(2500).format()), findsOneWidget);

      await tester.tap(find.text('Estate'));
      await tester.pumpAndSettle();
      expect(find.text(Pence(3250).format()), findsOneWidget);
    });

    testWidgets('shows seats and bags on each card', (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_singleLegEstimate()));

      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('4 Seats 2 Bags'), findsOneWidget);
    });

    testWidgets('shows the selected category\'s real total', (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_singleLegEstimate()));

      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();

      expect(find.text('Total'), findsOneWidget);
      expect(find.text(Pence(2500).format()), findsOneWidget);
    });

    testWidgets('the primary button confirms a booking, never a driver pick',
        (tester) async {
      // The critical decision: dispatch assigns exactly one driver via a
      // Hungarian match. There is no candidate-driver endpoint, so this
      // screen must never imply a driver marketplace. (The cancellation
      // policy legitimately mentions driver ASSIGNMENT — the thing that must
      // not exist is a choice.)
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_singleLegEstimate()));

      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Booking'), findsOneWidget);
      expect(find.textContaining('Choose a driver'), findsNothing);
      expect(find.textContaining('Choose your driver'), findsNothing);
    });

    testWidgets('tapping Confirm invokes onConfirm with the selected category',
        (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_singleLegEstimate()));

      VehicleCategory? confirmed;
      await tester.pumpWidget(
          _harness(repo, onConfirm: (c, _) => confirmed = c));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();
      // Open the collapsible sheet fully, then scroll ITS list (the
      // vehicle grid is also a Scrollable, so target the sheet's own).
      await tester.drag(
          find.text('Ride Details'), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Confirm Booking'), 80,
          scrollable: find
              .descendant(
                  of: find.byType(DraggableScrollableSheet),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.text('Confirm Booking'));
      await tester.pumpAndSettle();

      expect(confirmed, _standard);
    });

    testWidgets('never shows a numeric waiting-time figure', (tester) async {
      // Waiting time is not in the estimate and accrues live — the screen
      // must not display a number it cannot know.
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_singleLegEstimate()));

      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.textContaining('Waiting'), findsWidgets);
      // "may apply" language only — never a minute/penny figure attached to it.
      final waitingTexts = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').toLowerCase().contains('wait'));
      for (final t in waitingTexts) {
        expect(t.data, contains('may'));
      }
    });
  });

  group('multi-stop', () {
    testWidgets('shows a per-leg fare line for each leg', (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_multiStopEstimate()));

      await tester.pumpWidget(_harness(
        repo,
        waypoints: const [LatLng(52.580, -2.120), LatLng(52.578, -2.101)],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Tesco'), findsOneWidget);
      expect(find.textContaining("Mum's"), findsOneWidget);
      expect(find.textContaining('Dropoff'), findsOneWidget);
      expect(find.text(Pence(3000).format()), findsOneWidget);
      expect(find.text(Pence(9000).format()), findsOneWidget);
      expect(find.text(Pence(2000).format()), findsOneWidget);
      // Grand total from the API, not a client-side re-sum.
      expect(find.text(Pence(14000).format()), findsOneWidget);
    });

    testWidgets('shows the fees-charged-once explainer near verbatim',
        (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => Ok(_multiStopEstimate()));

      await tester.pumpWidget(_harness(
        repo,
        waypoints: const [LatLng(52.580, -2.120), LatLng(52.578, -2.101)],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Stops are priced per leg and added up. Fees are charged once on the total.'),
        findsOneWidget,
      );
    });
  });

  group('error', () {
    testWidgets('shows an error state with a retry action', (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => const Err(ApiException(
            'INTERNAL', 'Something went wrong on our side. Try again.', 500,
          )));

      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong on our side. Try again.'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });

    testWidgets('a NO_ZONE failure with stops names which stop is affected',
        (tester) async {
      when(() => repo.estimate(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            vehicleCategoryId: any(named: 'vehicleCategoryId'),
            waypoints: any(named: 'waypoints'),
          )).thenAnswer((_) async => const Err(ApiException(
            'NO_ZONE',
            'We do not have pricing for this pickup point yet.',
            422,
          )));

      await tester.pumpWidget(_harness(
        repo,
        waypoints: const [
          LatLng(52.580, -2.120),
          LatLng(52.578, -2.101),
          LatLng(52.560, -2.090),
        ],
      ));
      await tester.pumpAndSettle();

      // With up to five stops the rider cannot guess which one failed, so
      // the message must enumerate them rather than pointing at "this" stop.
      expect(find.textContaining('Stop 1'), findsOneWidget);
      expect(find.textContaining('Stop 2'), findsOneWidget);
      expect(find.textContaining('Stop 3'), findsOneWidget);
    });
  });

  testWidgets('renders in dark mode', (tester) async {
    when(() => repo.estimate(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          vehicleCategoryId: any(named: 'vehicleCategoryId'),
          waypoints: any(named: 'waypoints'),
        )).thenAnswer((_) async => Ok(_singleLegEstimate()));

    await tester.pumpWidget(_harness(repo, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Confirm Booking'), findsOneWidget);
  });

  testWidgets('constructs with no arguments, for the router', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: FareConfirmScreen()),
      ),
    );
    await tester.pump();

    // With no categories supplied there is nothing to quote — an empty
    // state, not a crash.
    expect(tester.takeException(), isNull);
  });
}
