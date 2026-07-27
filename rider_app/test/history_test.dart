import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/history/history_screen.dart';
import 'package:hoppin_rider/features/trip/rating_sheet.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// History as an Activity hub (RIDER-05's tail): destination bold via the
/// DEMO-07 seam, short date, price joined from the transactions ledger,
/// status pill — the just-completed session ride landing on top, and every
/// degradation graceful (generic title, blank price, never a raw uuid).
void main() {
  testWidgets('seeded rows read as an Activity hub', (tester) async {
    final h = await _bootHistory(tester);

    final rows = find.byType(RideRow);
    expect(rows, findsNWidgets(7),
        reason: 'the seeded world carries seven completed trips');

    // Row 0 = the newest seeded trip: City Centre → Bentley Bridge.
    final first = rows.first;
    final destination = tester.widget<Text>(find.descendant(
        of: first, matching: find.text('Bentley Bridge Retail Park')));
    expect(destination.style?.fontWeight, FontWeight.w600,
        reason: 'the destination is the BOLD title of the row');

    final ride = DemoHistory.trips.first.ride;
    expect(
      find.descendant(
          of: first,
          matching: find.text(formatShortDateTime(ride.createdAt!))),
      findsOneWidget,
      reason: 'the subtitle carries the short date',
    );
    expect(find.descendant(of: first, matching: find.text('£7.25')),
        findsOneWidget,
        reason: 'the price joins from the seeded transaction row');
    expect(find.descendant(of: first, matching: find.text('Completed')),
        findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('completed session ride lands on top with its discounted price',
      (tester) async {
    final h = await _bootHistory(tester, driveScriptedRide: true);

    final rows = find.byType(RideRow);
    expect(rows, findsNWidgets(8),
        reason: 'the session completion joins the seven seeded rows');

    // Row 0 = the session ride, destination from the seam retained through
    // the archive beat, price = the DISCOUNTED total (HOPPIN20 applied).
    final first = rows.first;
    expect(
        find.descendant(
            of: first, matching: find.text('New Cross Hospital')),
        findsOneWidget);
    expect(find.descendant(of: first, matching: find.text('£5.11')),
        findsOneWidget,
        reason: 'the row price is what was actually charged');
    expect(find.descendant(of: first, matching: find.text('Completed')),
        findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('graceful degradation: null seam renders the generic title, '
      'never a raw uuid, never a crash', (tester) async {
    final world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();
    final container = ProviderContainer(overrides: [
      ridesRepositoryProvider.overrideWithValue(_NullSeamRides(world)),
      paymentsRepositoryProvider
          .overrideWithValue(FakePaymentsRepository(world)),
    ]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: _light, routerConfig: _stubRouter()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RideRow), findsNWidgets(7));
    expect(find.text('Ride'), findsNWidgets(7),
        reason: 'every null-seam row falls back to the generic title');
    // Never a raw uuid on screen.
    expect(find.textContaining('e0000000'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    container.dispose();
    world.reset();
  });

  testWidgets('row navigation preserved: completed rows open the receipt',
      (tester) async {
    final h = await _bootHistory(tester);

    await tester.tap(find.byType(RideRow).first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('receipt-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('row navigation preserved: active rows return to the live trip',
      (tester) async {
    final h = await _bootHistory(tester, requestActiveRide: true);

    final rows = find.byType(RideRow);
    expect(rows, findsNWidgets(8));
    expect(find.descendant(of: rows.first, matching: find.text('Active')),
        findsOneWidget);
    // Active rows carry no settled price.
    expect(find.descendant(of: rows.first, matching: find.text('£5.11')),
        findsNothing);

    await tester.tap(rows.first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('trip-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  // TRIP-04: the rating sheet BINDING — a completed trip's rating submits
  // `POST /rides/:id/rating`. The history hub is the Activity surface a rider
  // rates from; proving the sheet writes the score through the repository
  // closes the history → details → rating loop.
  testWidgets('rating sheet submits POST /rides/:id/rating for a completed '
      'trip', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();
    world.markSignedIn();
    final rideId = DemoHistory.trips.first.ride.id;

    final container = ProviderContainer(overrides: riderDemoOverrides(world));
    addTearDown(() {
      container.dispose();
      world.reset();
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: _light,
        home: _RatingHost(rideId: rideId),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Open rating'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    // Pick 5 stars and submit.
    await tester.tap(find.byTooltip('5 stars'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Submit rating'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    // The score reached the world through the repository's rate() call.
    expect(world.eventLog.any((e) => e.contains('rideRated')), isTrue,
        reason: 'submitting the rating must POST /rides/:id/rating');
    expect(tester.takeException(), isNull);
  });
}

/// A trivial host that opens the rating sheet — mirrors the trip screen's
/// post-trip rating entry without pulling the whole trip riblet in.
class _RatingHost extends StatelessWidget {
  const _RatingHost({required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRatingSheet(context, rideId: rideId),
            child: const Text('Open rating'),
          ),
        ),
      ),
    );
  }
}

/// Null-seam delegate: demo-real rides whose DEMO-07 seam answers null,
/// exactly as the live repository does.
class _NullSeamRides extends FakeRidesRepository {
  _NullSeamRides(super.world);

  @override
  Future<RideDriverInfo?> driverInfo(String rideId) async => null;
}

// One ThemeData reused across pumps (04-02 test-harness trap).
final _light = HoppinTheme.riderLight();

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home-stub'))),
        GoRoute(
            path: '/history', builder: (_, _) => const HistoryScreen()),
        GoRoute(
          path: '/trip/:id',
          builder: (_, _) => const Scaffold(body: Text('trip-stub')),
          routes: [
            GoRoute(
                path: 'receipt',
                builder: (_, _) =>
                    const Scaffold(body: Text('receipt-stub'))),
          ],
        ),
      ],
    );

class _Harness {
  _Harness({required this.world, required this.container});

  final DemoWorld world;
  final ProviderContainer container;
}

/// Boots the history screen over the exact demo composition. Optionally
/// drives the world through a full promo'd scripted ride first (landing it
/// archived on top of history) or leaves a live accepted ride on top.
Future<_Harness> _bootHistory(
  WidgetTester tester, {
  bool driveScriptedRide = false,
  bool requestActiveRide = false,
}) async {
  // Eight Activity-hub rows outgrow the default 800x600 test viewport (the
  // lazy list stops building) — give the hub a phone-tall surface.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final world = DemoWorld.riderScenario(
    seed: DemoSeed.seed,
    store: InMemorySnapshotStore(),
  )..restoreOrSeed();
  world.markSignedIn();

  if (driveScriptedRide || requestActiveRide) {
    world.submitRideRequest(
      pickupLat: DemoPlaces.railStation.lat,
      pickupLng: DemoPlaces.railStation.lng,
      dropoffLat: DemoPlaces.newCrossHospital.lat,
      dropoffLng: DemoPlaces.newCrossHospital.lng,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5)); // match beat at ~4.2s
    if (driveScriptedRide) {
      final rideId = world.rideHistory().first.id;
      world.applyPromoCode(rideId: rideId, promoCode: 'HOPPIN20');
      world.markArrived(rideId);
      world.startRide(rideId);
      world.completeRide(rideId);
      // Let the 3s post-complete beat archive the ride — the row must read
      // its labels through the retained-labels path, not the live route.
      await tester.pump(const Duration(seconds: 4));
    }
    expect(world.rideHistory(), hasLength(8),
        reason: 'the session ride must be in the data before the pump');
  }

  final container = ProviderContainer(overrides: riderDemoOverrides(world));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: _light, routerConfig: _stubRouter()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));

  return _Harness(world: world, container: container);
}

Future<void> _cleanup(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  h.container.dispose();
  h.world.reset();
}
