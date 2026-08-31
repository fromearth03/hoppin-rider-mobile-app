import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/scheduling/data/scheduled_rides_repository.dart';
import 'package:hoppin_rider/features/scheduling/presentation/schedule_ride_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockVehicleRepository extends Mock implements VehicleRepository {}

class _MockScheduledRides extends Mock implements ScheduledRidesRepository {}

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
const _mpv = VehicleCategory(
  id: 'c',
  name: 'MPV',
  seats: 7,
  bags: 5,
  priceMultiplier: 1.5,
);
const _minibus = VehicleCategory(
  id: 'd',
  name: 'Minibus',
  seats: 8,
  bags: 6,
  priceMultiplier: 2.0,
);

/// Scheduling is wired to the live `POST/GET/DELETE /scheduled-rides`
/// surface. The "Ride Type" grid reads the same live `GET /vehicle-types`
/// catalogue `Select Vehicle` does, so this harness mocks that repository
/// rather than relying on a hardcoded list, and mocks the scheduled-rides
/// repository the screen's list/policy/submit paths call.
Widget _harness({
  Brightness brightness = Brightness.light,
  VehicleRepository? vehicleRepository,
  ScheduledRidesRepository? scheduledRides,
}) {
  final repo = vehicleRepository ?? _defaultRepo();
  return ProviderScope(
    overrides: [
      vehicleRepositoryProvider.overrideWithValue(repo),
      scheduledRidesRepositoryProvider
          .overrideWithValue(scheduledRides ?? _defaultScheduledRepo()),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: const ScheduleRideScreen(),
    ),
  );
}

ScheduledRidesRepository _defaultScheduledRepo() {
  final repo = _MockScheduledRides();
  when(() => repo.list()).thenAnswer((_) async => const Ok([]));
  when(() => repo.cancellationPolicy())
      .thenAnswer((_) async => const Ok([]));
  return repo;
}

VehicleRepository _defaultRepo() {
  final repo = _MockVehicleRepository();
  when(() => repo.list()).thenAnswer(
      (_) async => const Ok([_standard, _estate, _mpv, _minibus]));
  return repo;
}

/// The sheet's content is a lazily-built scrollable, so anything below the
/// fold in the default 800x600 test surface must be scrolled into the
/// viewport before it can be found or tapped. Scrolls the given finder into
/// view rather than dragging a fixed distance, so it neither undershoots nor
/// scrolls straight past the target.
Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    // The GridView inside the sheet has its own (non-scrolling) Scrollable,
    // so the sheet's real Scrollable is the first descendant match.
    scrollable: find
        .descendant(
          of: find.byKey(const Key('scheduleRideSheetList')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the Schedule Ride heading and subtitle', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Schedule Ride'), findsOneWidget);
    expect(find.text('Book your ride in advance'), findsOneWidget);
  });

  testWidgets('renders From and To fields', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
  });

  testWidgets('renders the Schedule for field', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Schedule for'), findsOneWidget);
  });

  testWidgets('renders all four vehicle categories under Ride Type',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Ride Type'));

    expect(find.text('Ride Type'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Estate'), findsOneWidget);
    expect(find.text('MPV'), findsOneWidget);
    expect(find.text('Minibus'), findsOneWidget);
  });

  testWidgets(
      'the fare card asks for a route before showing any number — nothing '
      'is fabricated', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Fare Estimate'));

    expect(find.text('Fare Estimate'), findsOneWidget);
    expect(find.text('Choose a route to see your fare.'), findsOneWidget);
    expect(find.textContaining('£'), findsNothing);
  });

  testWidgets(
      'Confirm Schedule stays disabled until a route and a time are chosen',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(
        tester, find.widgetWithText(FilledButton, 'Confirm Schedule'));

    final button = find.widgetWithText(FilledButton, 'Confirm Schedule');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull,
        reason: 'submitting with no route or time could only fail — or '
            'worse, silently drop the rider\'s intent');
  });

  testWidgets('renders the cancellation policy with the server\'s own rows',
      (tester) async {
    final repo = _MockScheduledRides();
    when(() => repo.list()).thenAnswer((_) async => const Ok([]));
    when(() => repo.cancellationPolicy()).thenAnswer((_) async => const Ok([
          CancellationScenario(
            actor: 'rider',
            label: 'Cancelling after driver assignment may incur a fee',
            feePence: Pence(300),
            freeCancelSeconds: 120,
          ),
        ]));

    await tester.pumpWidget(_harness(scheduledRides: repo));
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Cancellation Policy'));

    expect(
        find.text('Cancelling after driver assignment may incur a fee'),
        findsOneWidget);
    expect(find.text('£3.00'), findsOneWidget);
  });

  testWidgets('lists upcoming scheduled rides and cancels one', (tester) async {
    final repo = _MockScheduledRides();
    final ride = ScheduledRide(
      id: 'sr-1',
      status: 'scheduled',
      pickup: null,
      dropoff: null,
      requestedPickupTime: DateTime.utc(2026, 9, 2, 14, 30),
      estimatePence: const Pence(850),
      currency: 'GBP',
      vehicleCategory: 'Standard',
      activeRideId: null,
    );
    when(() => repo.list()).thenAnswer((_) async => Ok([ride]));
    when(() => repo.cancellationPolicy())
        .thenAnswer((_) async => const Ok([]));
    when(() => repo.cancel('sr-1')).thenAnswer((_) async => const Ok(null));

    await tester.pumpWidget(_harness(scheduledRides: repo));
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Upcoming rides'));

    expect(find.textContaining('Standard'), findsWidgets);
    expect(find.textContaining('£8.50'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verify(() => repo.cancel('sr-1')).called(1);
  });

  testWidgets('has a close button that pops the screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vehicleRepositoryProvider.overrideWithValue(_defaultRepo()),
          scheduledRidesRepositoryProvider
              .overrideWithValue(_defaultScheduledRepo()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ScheduleRideScreen()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule Ride'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Schedule Ride'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('tapping a vehicle category selects it without crashing',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Estate'));

    await tester.tap(find.text('Estate'));
    await tester.pump();

    // Still on the same screen, nothing thrown.
    expect(find.byType(ScheduleRideScreen), findsOneWidget);
  });

  testWidgets('tapping the schedule-for field opens a date picker',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a date and time'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(find.text('Schedule Ride'), findsOneWidget);

    await _scrollUntilVisible(tester, find.text('Ride Type'));
    expect(find.text('Ride Type'), findsOneWidget);
  });

  testWidgets('has a const constructor taking only a key', (tester) async {
    const screen = ScheduleRideScreen(key: Key('sched'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vehicleRepositoryProvider.overrideWithValue(_defaultRepo()),
          scheduledRidesRepositoryProvider
              .overrideWithValue(_defaultScheduledRepo()),
        ],
        child: const MaterialApp(home: screen),
      ),
    );
    expect(find.byKey(const Key('sched')), findsOneWidget);
  });
}
