import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/booking/booking_builder.dart';
import 'package:hoppin_rider/features/booking/place.dart';
import 'package:hoppin_rider/features/trip/receipt_screen.dart';
import 'package:hoppin_rider/features/trip/trip_handoff.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Receipt meter-readout acceptance (RIDER-04, RIDER-07): the completed
/// RouteStrip reappears for visual continuity with the live trip, the fare
/// table aligns in Poppins tabular numerals, an applied HOPPIN20 renders
/// as a satisfying negative line with a pence-exact bold total, and the
/// screen degrades gracefully when the capability seam answers null.
void main() {
  testWidgets('completed RouteStrip reappears with journey labels from the '
      'seam', (tester) async {
    final h = await _bootCompleted(tester, promo: true);

    final stripFinder = find.byType(RouteStrip);
    expect(stripFinder, findsOneWidget,
        reason: 'the live-trip strip must reappear on the receipt');
    final strip = tester.widget<RouteStrip>(stripFinder);
    expect(strip.complete, isTrue);
    expect(strip.showCarMarker, isFalse,
        reason: 'no car on a finished journey record');
    expect(strip.progress, 1.0);
    expect(strip.originLabel, 'Wolverhampton Rail Station');
    expect(strip.destinationLabel, 'New Cross Hospital');

    await _cleanup(tester, h);
  });

  testWidgets('fare table is pence-accurate with a satisfying negative promo '
      'line and a bold mono total', (tester) async {
    final h = await _bootCompleted(tester, promo: true);

    // Fare = the pre-discount quote.
    expect(find.text('Fare'), findsOneWidget);
    expect(find.text('£6.39'), findsOneWidget);

    // The promo as a negative line, derived fare + waiting − total.
    expect(find.text('Promo applied'), findsOneWidget);
    final discountText = tester.widget<Text>(find.text('−£1.28'));
    final success =
        HoppinTheme.riderLight().extension<HoppinColors>()!.success;
    expect(discountText.style?.color, success,
        reason: 'the negative line renders in the success colour');

    // Bold pence-exact total in the Poppins numeric style (R1 swapped the
    // rejected GeistMono → the Figma Poppins family; the tabular figures
    // now ride Poppins, never the mono).
    expect(find.text('Total'), findsOneWidget);
    final totalText = tester.widget<Text>(find.text('£5.11'));
    expect(totalText.style?.fontFamily, 'packages/hoppin_ui/Poppins',
        reason: 'amounts render in the Poppins numeric token style');
    expect(totalText.style?.fontWeight, FontWeight.w700,
        reason: 'the total is the bold money moment');

    // All amount cells share the packaged Poppins family (true column feel).
    final fareAmount = tester.widget<Text>(find.text('£6.39'));
    expect(fareAmount.style?.fontFamily, 'packages/hoppin_ui/Poppins');
    expect(discountText.style?.fontFamily, 'packages/hoppin_ui/Poppins');

    await _cleanup(tester, h);
  });

  testWidgets('no promo → no discount line, fare equals total',
      (tester) async {
    final h = await _bootCompleted(tester, promo: false);

    expect(find.text('Promo applied'), findsNothing);
    // £6.39 appears exactly twice: the Fare row and the Total row.
    expect(find.text('£6.39'), findsNWidgets(2));

    await _cleanup(tester, h);
  });

  testWidgets('driver line present and Rebook fires the book nav intent '
      'through the trip family router', (tester) async {
    final h = await _bootCompleted(tester, promo: true);

    // Driver line: initials + name from the seam (below the fold of the
    // lazy list — scroll it into build range first).
    await tester.scrollUntilVisible(find.text('Gurpreet Singh'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Gurpreet Singh'), findsOneWidget);
    expect(find.text('GS'), findsOneWidget);

    // Rebook → the trip family's book intent → /book (riblet rule: the
    // receipt view itself never navigates).
    await tester.scrollUntilVisible(find.text('Rebook this trip'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Rebook this trip'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('book-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('Rebook seeds the booking journey when the handoff matches '
      'this ride', (tester) async {
    final h = await _bootCompleted(tester, promo: false);
    h.container.read(tripHandoffProvider.notifier).state = TripHandoff(
      fareTotalPounds: 6.39,
      durationSeconds: 780,
      rideId: h.rideId,
      pickup: const Place(
        label: 'Wolverhampton Rail Station',
        lat: 52.5877,
        lng: -2.1200,
      ),
      dropoff: const Place(
        label: 'New Cross Hospital',
        lat: 52.6046,
        lng: -2.0930,
      ),
    );

    await tester.scrollUntilVisible(find.text('Rebook this trip'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Rebook this trip'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    final booking = h.container.read(bookingInteractorProvider);
    expect(booking.pickup?.label, 'Wolverhampton Rail Station',
        reason: "'Rebook this trip' must carry the trip, not open a blank "
            'picker');
    expect(booking.dropoff?.label, 'New Cross Hospital');
    expect(find.text('book-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('Rebook with a stale or missing handoff still exits to /book '
      'without seeding', (tester) async {
    final h = await _bootCompleted(tester, promo: false);
    // No handoff set (the reload shape) — rebook degrades to a fresh picker.
    await tester.scrollUntilVisible(find.text('Rebook this trip'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Rebook this trip'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    final booking = h.container.read(bookingInteractorProvider);
    expect(booking.pickup, isNull);
    expect(booking.dropoff, isNull);
    expect(find.text('book-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('Done exits to home — the receipt is never a dead end',
      (tester) async {
    final h = await _bootCompleted(tester, promo: false);

    await tester.scrollUntilVisible(find.text('Done'), 120,
        scrollable: find.byType(Scrollable).first);

    // 🔴 …and then ACTUALLY bring it on screen.
    //
    // `scrollUntilVisible` does NOT do what its name promises. It stops as soon
    // as the finder MATCHES, and a ListView builds its children through a cache
    // extent that reaches ~250px BEYOND the viewport — so the finder starts
    // matching while "Done" is still below the bottom edge. The scroll halts
    // there, the tap lands on empty view, and the assertion fails on a button
    // that the test believes it just pressed.
    //
    // This was luck, not correctness: Done happened to come to rest inside the
    // viewport, so nobody noticed. The moment the chrome above it grew by a
    // couple of dozen pixels the luck ran out — and the failure pointed at the
    // receipt screen, which was innocent. `ensureVisible` scrolls the target
    // fully into view, which is what this test always meant.
    await tester.ensureVisible(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    // 'Done' fires TripNavIntent.home → the Book tab under the 08-03 shell
    // (the old '/' HomeScreen hub is superseded by Book as the home surface).
    expect(find.text('book-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('seam null degrades: fallback labels, hidden driver line, '
      'no crash', (tester) async {
    final world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();
    // A seeded completed ride whose receipt exists, served through a repo
    // whose capability seam answers null (the live-mode shape).
    final rideId = DemoHistory.trips.first.ride.id;
    final container = ProviderContainer(overrides: [
      ridesRepositoryProvider.overrideWithValue(_NullSeamRides(world)),
    ]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: _light,
        routerConfig: _stubRouter(rideId),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    final strip = tester.widget<RouteStrip>(find.byType(RouteStrip));
    expect(strip.originLabel, 'Pickup');
    expect(strip.destinationLabel, 'Destination');
    // The driver line hides — no name, no initials avatar.
    expect(find.text('Amara Okafor'), findsNothing);
    // The fare table still renders pence-accurately from the receipt alone.
    expect(find.text('£7.25'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    container.dispose();
    world.reset();
  });

  // PAY-02: the money formatters that back both the receipt fare table and
  // the wallet transaction list must be pence-exact GBP — integer pence in,
  // "£x.yy" out, with no floating-point drift on the awkward values.
  group('pence-accurate GBP (PAY-02)', () {
    test('formatPence renders integer pence as exact GBP', () {
      expect(formatPence(639), '£6.39');
      expect(formatPence(511), '£5.11');
      expect(formatPence(0), '£0.00');
      expect(formatPence(5), '£0.05');
      expect(formatPence(100000), '£1000.00');
      // The classic float-drift trap: 0.1 + 0.2 territory stays exact.
      expect(formatPence(1030), '£10.30');
    });

    test('formatPounds mirrors formatPence at the pound boundary', () {
      expect(formatPounds(6.39), '£6.39');
      expect(formatPounds(6.39), formatPence(639));
    });
  });
}

/// Null-seam delegate: everything demo-real except the DEMO-07 seam, which
/// answers null exactly as the live repository does.
class _NullSeamRides extends FakeRidesRepository {
  _NullSeamRides(super.world);

  @override
  Future<RideDriverInfo?> driverInfo(String rideId) async => null;
}

// One ThemeData reused across pumps (04-02 test-harness trap).
final _light = HoppinTheme.riderLight();

GoRouter _stubRouter(String rideId) => GoRouter(
      initialLocation: '/trip/$rideId/receipt',
      routes: [
        GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home-stub'))),
        GoRoute(
            path: '/book',
            builder: (_, _) => const Scaffold(body: Text('book-stub'))),
        GoRoute(
          path: '/trip/:id',
          builder: (_, _) => const Scaffold(body: Text('trip-stub')),
          routes: [
            GoRoute(
              path: 'receipt',
              builder: (_, state) =>
                  ReceiptScreen(rideId: state.pathParameters['id']!),
            ),
          ],
        ),
      ],
    );

class _Harness {
  _Harness(
      {required this.world, required this.container, required this.rideId});

  final DemoWorld world;
  final ProviderContainer container;
  final String rideId;
}

/// Boots the exact demo composition, drives the scripted ride to completed
/// (manually tapping the lifecycle like the virtual driver would), then
/// mounts the receipt route.
Future<_Harness> _bootCompleted(WidgetTester tester,
    {required bool promo}) async {
  final world = DemoWorld.riderScenario(
    seed: DemoSeed.seed,
    store: InMemorySnapshotStore(),
  )..restoreOrSeed();
  world.markSignedIn();
  world.submitRideRequest(
    pickupLat: DemoPlaces.railStation.lat,
    pickupLng: DemoPlaces.railStation.lng,
    dropoffLat: DemoPlaces.newCrossHospital.lat,
    dropoffLng: DemoPlaces.newCrossHospital.lng,
  );
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5)); // match beat at ~4.2s
  final rideId = world.rideHistory().first.id;
  if (promo) {
    world.applyPromoCode(rideId: rideId, promoCode: 'HOPPIN20');
  }
  world.markArrived(rideId);
  world.startRide(rideId);
  world.completeRide(rideId);

  final container = ProviderContainer(overrides: riderDemoOverrides(world));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: _light,
      routerConfig: _stubRouter(rideId),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));

  return _Harness(world: world, container: container, rideId: rideId);
}

Future<void> _cleanup(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  h.container.dispose();
  h.world.reset();
}
