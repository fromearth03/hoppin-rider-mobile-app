import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/trip/map/map_builder.dart';
import 'package:hoppin_rider/features/trip/map/map_interactor.dart';
import 'package:hoppin_rider/features/trip/map/map_state.dart';
import 'package:hoppin_rider/features/trip/trip_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Completion + cancel acceptance (RIDER-05, RIDER-06): the arrival bloom
/// fires on the live flip and the rating sheet slides up AFTER the moment
/// (never over it), skippable and addressed to the driver by name; the
/// two-stage cancel-intercept protects the ride first, cancels with the
/// seeded default reason, and surveys AFTER — both flows always landing
/// somewhere navigable.
void main() {
  final ratingTitle = find.text('How was your trip with Gurpreet?');

  testWidgets('completion moment first, rating sheet after — never over it',
      (tester) async {
    final h = await _boot(tester);
    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    await tester.pump(const Duration(milliseconds: 400));

    h.world.completeRide(h.rideId);
    await _pumpUntilFound(
        tester, find.text("You've arrived at New Cross Hospital"));

    // The moment: completed strip, place-real headline, money reassurance.
    final strip = tester.widget<RouteStrip>(find.byType(RouteStrip));
    expect(strip.complete, isTrue);
    final receipt = h.world.receiptFor(h.rideId);
    expect(find.text('${formatPence(receipt.totalPence)} · paid'),
        findsOneWidget);

    // The sheet is NOT on the first completed frame.
    expect(ratingTitle, findsNothing,
        reason: 'the rating sheet must never cover the arrival moment');

    // After the ~1.2s post-bloom beat it slides up exactly once.
    await _pumpUntilFound(tester, ratingTitle, maxPumps: 10,
        step: const Duration(milliseconds: 300));
    expect(ratingTitle, findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('rating sheet: named prompt, 44px+ stars, submit records',
      (tester) async {
    final h = await _boot(tester);
    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    h.world.completeRide(h.rideId);
    await _pumpUntilFound(tester, ratingTitle, maxPumps: 20,
        step: const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final stars = find.byIcon(Icons.star_border);
    expect(stars, findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      final target = find
          .ancestor(of: stars.at(i), matching: find.byType(IconButton))
          .first;
      final size = tester.getSize(target);
      expect(size.height, greaterThanOrEqualTo(44),
          reason: 'star ${i + 1} must be a 44px+ target');
      expect(size.width, greaterThanOrEqualTo(44));
    }

    // Four stars, submit — the world's event log records the rating.
    await tester.tap(find.byIcon(Icons.star_border).at(3));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Submit rating'));
    await tester.tap(find.text('Submit rating'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    expect(h.world.eventLog.any((e) => e.contains('rideRated')), isTrue);
    expect(ratingTitle, findsNothing);
    expect(find.text('Thanks for the feedback!'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('skipping the rating leaves the completed state usable and '
      'never re-prompts', (tester) async {
    final h = await _boot(tester);
    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    h.world.completeRide(h.rideId);
    await _pumpUntilFound(tester, ratingTitle, maxPumps: 20,
        step: const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(ratingTitle, findsNothing);
    expect(find.text('View receipt'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);

    // No re-prompt, ever.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(ratingTitle, findsNothing);

    await _cleanup(tester, h);
  });

  testWidgets('cancel-intercept stage 1 protects the ride: ticking ETA and '
      'a positive keep-option', (tester) async {
    final h = await _boot(tester);
    await _pumpUntilFound(tester, find.text('Cancel trip'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('Cancel trip'));
    await tester.tap(find.text('Cancel trip'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cancel this trip?'), findsOneWidget);
    // The ticking ETA rides a numeric StatusPill ('Arrives in M:SS'); the
    // named reassurance line sits beside it.
    expect(find.text('Gurpreet is on the way to you.'), findsOneWidget);
    final ticking = find.byWidgetPredicate((w) =>
        w is Text &&
        w.data != null &&
        RegExp(r'^Arrives in \d+:\d\d$').hasMatch(w.data!));
    expect(ticking, findsOneWidget);
    final before = tester.widget<Text>(ticking).data!;
    await tester.pump(const Duration(seconds: 1));
    final after = tester.widget<Text>(ticking).data!;
    expect(before == after, isFalse,
        reason: 'the intercept line keeps ticking inside the sheet');

    // The positive primary keeps the ride.
    await tester.tap(find.text('No, keep my ride'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cancel this trip?'), findsNothing);
    expect(h.world.eventLog.any((e) => e.contains('rideCancelled')), isFalse);
    expect(find.text('Gurpreet is on the way'), findsOneWidget,
        reason: 'keeping the ride returns to the untouched en-route state');

    await _cleanup(tester, h);
  });

  testWidgets('confirmed cancel uses the seeded reason and surveys AFTER, '
      'landing on the designed cancelled state', (tester) async {
    final h = await _boot(tester);
    await _pumpUntilFound(tester, find.text('Cancel trip'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('Cancel trip'));
    await tester.tap(find.text('Cancel trip'));
    await tester.pump(); // route installs, entrance starts
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cancel ride'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    // The world only accepts seeded reason ids — a recorded cancellation
    // proves the default 'Changed my mind' id was sent.
    expect(h.world.eventLog.any((e) => e.contains('rideCancelled')), isTrue);

    // Stage 2: the skippable reason survey, AFTER the cancel resolved.
    expect(find.text('Mind telling us why?'), findsOneWidget);
    expect(find.text('Changed my mind'), findsOneWidget);
    expect(find.text('Waiting too long'), findsOneWidget);
    expect(find.text('Booked by mistake'), findsOneWidget);
    expect(find.text('Driver asked me to cancel'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Waiting too long'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Mind telling us why?'), findsNothing);
    expect(find.text('Trip cancelled'), findsOneWidget);
    expect(find.text('Book another ride'), findsOneWidget);

    await _cleanup(tester, h);
  });
}

/// Same boot shape as trip_view_test: scripted match, minimal stub router.
Future<_Harness> _boot(WidgetTester tester) async {
  final world = DemoWorld.riderScenario(
    seed: DemoSeed.seed,
    store: InMemorySnapshotStore(),
  )..restoreOrSeed();
  final container = ProviderContainer(overrides: [
    ...riderDemoOverrides(world),
    // Pin the map riblet to the hidden rung: this suite proves completion/
    // cancel CONTENT in the map-less layout — map-mode composition is
    // proven in test/features/trip/map/map_view_test.dart.
    mapInteractorProvider.overrideWith2((_) => _HiddenMapStub()),
  ]);
  await container.read(authServiceProvider).signInWithPassword(
        email: DemoSeed.riderCredentials.email,
        password: DemoSeed.riderCredentials.password,
      );

  world.submitRideRequest(
    pickupLat: DemoPlaces.railStation.lat,
    pickupLng: DemoPlaces.railStation.lng,
    dropoffLat: DemoPlaces.newCrossHospital.lat,
    dropoffLng: DemoPlaces.newCrossHospital.lng,
  );
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5)); // match beat at ~4.2s
  final rideId = world.rideHistory().first.id;

  final router = GoRouter(
    initialLocation: '/trip/$rideId',
    routes: [
      GoRoute(
          path: '/', builder: (_, _) => const Scaffold(body: Text('home-stub'))),
      GoRoute(
          path: '/book',
          builder: (_, _) => const Scaffold(body: Text('book-stub'))),
      GoRoute(
          path: '/safety',
          builder: (_, _) => const Scaffold(body: Text('safety-stub'))),
      GoRoute(
        path: '/trip/:id',
        builder: (_, state) => TripScreen(rideId: state.pathParameters['id']!),
        routes: [
          GoRoute(
              path: 'receipt',
              builder: (_, _) => const Scaffold(body: Text('receipt-stub'))),
          GoRoute(
              path: 'chat',
              builder: (_, _) => const Scaffold(body: Text('chat-stub'))),
        ],
      ),
    ],
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: _light, routerConfig: router),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));

  return _Harness(world: world, container: container, rideId: rideId);
}

class _Harness {
  _Harness(
      {required this.world, required this.container, required this.rideId});

  final DemoWorld world;
  final ProviderContainer container;
  final String rideId;
}

/// A map riblet pinned to the hidden rung — no seam poll, no timers.
class _HiddenMapStub extends MapInteractor {
  _HiddenMapStub() : super('stub');

  @override
  MapState build() => const MapState();
}

// One ThemeData reused across pumps (04-02 test-harness trap).
final _light = HoppinTheme.riderLight();

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
  Duration step = const Duration(milliseconds: 500),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
  fail('Timed out waiting for $finder after $maxPumps pumps');
}

Future<void> _cleanup(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  h.container.dispose();
  h.world.reset();
}
