import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/booking/widgets/matching_rung.dart';
import 'package:hoppin_rider/features/trip/map/map_builder.dart';
import 'package:hoppin_rider/features/trip/map/map_interactor.dart';
import 'package:hoppin_rider/features/trip/map/map_state.dart';
import 'package:hoppin_rider/features/trip/trip_builder.dart';
import 'package:hoppin_rider/features/trip/trip_handoff.dart';
import 'package:hoppin_rider/features/trip/trip_interactor.dart';
import 'package:hoppin_rider/features/trip/trip_screen.dart';
import 'package:hoppin_rider/features/trip/trip_state.dart';
import 'package:hoppin_rider/features/trip/widgets/matched_driver_card.dart';
import 'package:hoppin_rider/features/trip/widgets/seam_unavailable_states.dart';
import 'package:hoppin_rider/features/trip/widgets/share_link_unavailable_state.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// View layer (riblet testing contract, DOCS/05): the trip screen RECOMPOSES
/// per smart phase — ticking ETA hero, calm arriving hold, meet-your-driver,
/// the on-road RouteStrip with the compact card and money row, the designed
/// cancelled state — with every navigation leaving as an intent that only
/// TripNavigationHost translates. Bounded pumps throughout, never settle.
void main() {
  final etaClock = find.byWidgetPredicate((w) =>
      w is Text && w.data != null && RegExp(r'^\d+:\d\d$').hasMatch(w.data!));

  testWidgets('driverEnRoute: ETA hero ticks and the card is plate-first',
      (tester) async {
    final h = await _boot(tester);

    await _pumpUntilFound(tester, etaClock);
    final first = tester.widget<Text>(etaClock.first).data!;
    await tester.pump(const Duration(seconds: 1));
    final second = tester.widget<Text>(etaClock.first).data!;
    await tester.pump(const Duration(seconds: 1));
    final third = tester.widget<Text>(etaClock.first).data!;
    expect({first, second, third}.length, greaterThan(1),
        reason: 'the mm:ss hero must visibly tick across 1s pumps');

    expect(find.text('Gurpreet is on the way'), findsOneWidget);
    expect(find.byType(MatchedDriverCard), findsOneWidget);
    expect(find.text('BK72 WNH'), findsOneWidget);
    expect(find.textContaining('Arriving '), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('arrivingNow recomposes: calm headline, ticking clock gone',
      (tester) async {
    final h = await _boot(tester);

    // The ETA floors 120s after the match; the next poll lands inside the
    // ~2.5s hold. ~125s of fake time in bounded steps.
    await _pumpUntilFound(tester, find.text('Arriving now'), maxPumps: 260);
    await tester.pump(const Duration(milliseconds: 400)); // switcher settles

    expect(find.text('Arriving now'), findsOneWidget);
    expect(etaClock, findsNothing,
        reason: 'the hold is calm — no ticking mm:ss remains');
    expect(find.text('Meet Gurpreet at Wolverhampton Rail Station'),
        findsOneWidget);
    expect(find.byType(MatchedDriverCard), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('driverArrived: meet-your-driver state with the plate reminder',
      (tester) async {
    final h = await _boot(tester);

    h.world.markArrived(h.rideId);
    // Poll observes within 3s; assert before the scripted trip start (4s).
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Gurpreet is here'), findsOneWidget);
    expect(find.text('BK72 WNH'), findsOneWidget);
    expect(find.byType(MatchedDriverCard), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets(
      'onRoad: RouteStrip, compact card, fixed-fare reminder, promo row',
      (tester) async {
    final h = await _boot(
      tester,
      handoff: const TripHandoff(fareTotalPounds: 6.39, durationSeconds: 780),
    );

    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    await tester.pump(const Duration(milliseconds: 400));

    final strip = tester.widget<RouteStrip>(find.byType(RouteStrip));
    expect(strip.destinationLabel, 'New Cross Hospital');
    expect(strip.complete, isFalse);
    expect(find.text('On your way to New Cross Hospital'), findsOneWidget);

    final card =
        tester.widget<MatchedDriverCard>(find.byType(MatchedDriverCard));
    expect(card.compact, isTrue,
        reason: 'on-road shows the mini-card, not the full matched beat');

    expect(find.text('£6.39 fixed'), findsOneWidget);
    expect(find.text('Add promo code'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('a promo that failed at match is said out loud, never silent',
      (tester) async {
    final h = await _boot(
      tester,
      handoff: const TripHandoff(
        fareTotalPounds: 6.39,
        durationSeconds: 780,
        promoError: 'Promo code not found',
      ),
    );

    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(HopBanner), findsOneWidget,
        reason: 'a staged code that failed at match must never vanish '
            'silently');
    expect(find.textContaining('Promo code not found'), findsOneWidget);
    expect(find.text('Add promo code'), findsOneWidget,
        reason: 'the rider can still stage a working code');

    await _cleanup(tester, h);
  });

  testWidgets('fixed-fare reminder hides when the handoff is null (reload)',
      (tester) async {
    final h = await _boot(tester); // no handoff written

    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('fixed'), findsNothing);

    await _cleanup(tester, h);
  });

  testWidgets('promo animate-down: HOPPIN20 strikes the old total and ticks '
      'to the new one', (tester) async {
    final h = await _boot(tester);
    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    // Wait for the ON-ROAD state (the promo row exists en-route too).
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Add promo code'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'HOPPIN20');
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1200)); // ticker lands

    // Same maths as the world: 20% off the scripted route's quote.
    final estimate = estimateBetween(
      pickupLat: DemoPlaces.railStation.lat,
      pickupLng: DemoPlaces.railStation.lng,
      dropoffLat: DemoPlaces.newCrossHospital.lat,
      dropoffLng: DemoPlaces.newCrossHospital.lng,
    );
    final promo = promoResultFor(
        code: 'HOPPIN20', originalFare: estimate.estimate.total)!;

    expect(find.text('HOPPIN20 · 20% off'), findsOneWidget);
    final struck = find.byWidgetPredicate((w) =>
        w is Text &&
        w.data == formatPounds(promo.originalFare) &&
        w.style?.decoration == TextDecoration.lineThrough);
    expect(struck, findsOneWidget,
        reason: 'the old total must be struck through, not erased');
    expect(find.byType(MoneyTicker), findsOneWidget);
    expect(find.text(formatPounds(promo.newFare)), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('promo failure explains why without changing the trip',
      (tester) async {
    final h = await _boot(tester);
    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    // Wait for the ON-ROAD state (the promo row exists en-route too).
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Add promo code'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'BOGUS99');
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Promo code not found'), findsOneWidget);
    expect(find.byType(RouteStrip), findsOneWidget,
        reason: 'a promo failure never disturbs the on-road state');

    await _cleanup(tester, h);
  });

  testWidgets('cancelled: designed end state with a book-again affordance, '
      'no timeline corpse', (tester) async {
    final h = await _boot(tester);

    h.world.cancelRide(
      rideId: h.rideId,
      reasonId: DemoSeed.cancellationReasonIds.first,
      canceledByUserId: DemoSeed.riderId,
      actorType: 'rider',
    );
    await _pumpUntilFound(tester, find.text('Trip cancelled'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Trip cancelled'), findsOneWidget);
    expect(find.byType(RouteStrip), findsNothing);
    expect(find.text('Driver on the way'), findsNothing,
        reason: 'no dead status-timeline survives the cancelled state');
    expect(find.byType(MatchedDriverCard), findsNothing);

    // Book again flows through the intent → TripNavigationHost → router.
    await tester.tap(find.text('Book another ride'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('book-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  testWidgets('navigation leaves ONLY as intents: safety tap lands on the '
      'safety route via the host', (tester) async {
    final h = await _boot(tester);
    h.world.markArrived(h.rideId);
    h.world.startRide(h.rideId);
    await _pumpUntilFound(tester, find.byType(RouteStrip));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('Safety'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500)); // route settles

    expect(find.text('safety-stub'), findsOneWidget);
    expect(find.byType(TripScreen), findsNothing,
        reason: 'the host consumed the intent and moved the route');

    await _cleanup(tester, h);
  });

  testWidgets('the Message button on the matched card routes to chat via intent',
      (tester) async {
    final h = await _boot(tester);
    await _pumpUntilFound(tester, find.text('Message'));

    await tester.tap(find.text('Message'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('chat-stub'), findsOneWidget);

    await _cleanup(tester, h);
  });

  // ── PHASE 11 — the convergence assertions. These boot the REAL trip screen
  // and prove the lanes' surfaces are REACHABLE BY TAPPING, not merely
  // constructible in a harness. Wave 0 exists because four registered
  // "disclosures" passed a bare-harness check while no view ever mounted them.
  group('PHASE 11 — call / share / chat-gate reachability', () {
    // 🔴 COMMS-02 (#45). Wave 0 deleted a phone icon that opened CHAT. The
    // fix is not to hide calling; it is to make Call a button of its own that
    // leads somewhere honest ABOUT CALLING. This is the assertion that the
    // lie stays dead: the phone affordance must land on /trip/:id/call and
    // NEVER on /trip/:id/chat.
    testWidgets('the on-road PHONE affordance routes to the CALL screen — '
        'never to chat (the deleted Wave-0 lie)', (tester) async {
      final h = await _boot(tester);
      h.world.markArrived(h.rideId);
      h.world.startRide(h.rideId);
      await _pumpUntilFound(tester, find.byType(RouteStrip));
      await tester.pump(const Duration(milliseconds: 400));

      // Chat and Call are two DISTINCT icons with two DISTINCT destinations.
      expect(find.byTooltip('Message driver'), findsOneWidget,
          reason: 'chat keeps its own affordance (BOUND)');
      expect(find.byTooltip('Call driver'), findsOneWidget,
          reason: 'the #45 call seam gets an affordance of its OWN — the whole '
              'point of killing the phone-icon-opens-chat lie');

      await tester.tap(find.byTooltip('Call driver'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('call-stub'), findsOneWidget,
          reason: 'the phone affordance must reach the CALL surface');
      expect(find.text('chat-stub'), findsNothing,
          reason: 'a phone icon that opens chat is the exact lie Wave 0 '
              'deleted — it must never come back');

      await _cleanup(tester, h);
    });

    testWidgets('the on-road CHAT affordance still routes to chat',
        (tester) async {
      final h = await _boot(tester);
      h.world.markArrived(h.rideId);
      h.world.startRide(h.rideId);
      await _pumpUntilFound(tester, find.byType(RouteStrip));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip('Message driver'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('chat-stub'), findsOneWidget,
          reason: 'chat stays BOUND and reachable — splitting the affordances '
              'must not cost the rider the working one');

      await _cleanup(tester, h);
    });

    // 🔴 SAFETY-02 (#57). The DoD never enforced the old "copied" snackbar, so
    // the share path was untested at trip-screen level. It is now.
    testWidgets('the matched-card SHARE affordance opens the sheet and renders '
        'the #57 rung — no fake URL, no clipboard write', (tester) async {
      final clipboardWrites = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardWrites.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final h = await _boot(tester);
      await _pumpUntilFound(tester, find.text('Share trip'));

      await tester.tap(find.text('Share trip'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShareLinkUnavailableState), findsOneWidget,
          reason: 'the share affordance must open the DESIGNED sheet and '
              'render the #57 rung where the link would be');
      expect(find.text('Link copied'), findsNothing,
          reason: 'the Wave-0 "copied" lie must stay dead — there is no link');
      expect(clipboardWrites, isEmpty,
          reason: 'nothing may be written to the clipboard: there is no '
              'tokenised tracking URL to copy (#57), so copying anything at '
              'all would be copying a claim we cannot keep');

      await _cleanup(tester, h);
    });

    testWidgets('the ON-ROAD share affordance opens the same sheet (both share '
        'sites re-pointed, neither left on the deleted stub)', (tester) async {
      final h = await _boot(tester);
      h.world.markArrived(h.rideId);
      h.world.startRide(h.rideId);
      await _pumpUntilFound(tester, find.byType(RouteStrip));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byTooltip('Share trip'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShareLinkUnavailableState), findsOneWidget,
          reason: 'the second share site must open the sheet too — a half '
              're-pointed affordance would leave one path on the deleted lie');

      await _cleanup(tester, h);
    });

    // COMMS-01 client mirror. The server 409 CHAT_CLOSED stays the AUTHORITY;
    // this is the UX half — the rider is never handed an entry into a channel
    // that will reject them.
    testWidgets('the chat entry is DISABLED in a terminal phase (completed / '
        'cancelled) — the client mirror of the server chat window',
        (tester) async {
      for (final phase in [TripPhase.completed, TripPhase.cancelled]) {
        expect(_stateFor(phase).chatOpen, isFalse,
            reason: '$phase is terminal — chat is closed');
      }
      // ...and open exactly where the server allows it.
      for (final phase in [
        TripPhase.driverEnRoute,
        TripPhase.arrivingNow,
        TripPhase.driverArrived,
        TripPhase.onRoad,
      ]) {
        expect(_stateFor(phase).chatOpen, isTrue,
            reason: '$phase has a driver on an active trip — chat is open');
      }
      // NOT a copy of `cancellable`: chat is closed while finding (no driver
      // to message) and open on-road (where cancelling is not).
      expect(_stateFor(TripPhase.finding).chatOpen, isFalse,
          reason: 'there is no driver to message yet while finding');
      expect(_stateFor(TripPhase.finding).cancellable, isTrue,
          reason: 'the two windows are the INVERSE of one another at this end');
      expect(_stateFor(TripPhase.onRoad).chatOpen, isTrue);
      expect(_stateFor(TripPhase.onRoad).cancellable, isFalse,
          reason: '...and at the other. chatOpen is not a copy of cancellable.');

      // The view honours it: the on-road icon row disables Message when the
      // mirror says the window is shut.
      await _bootStub(
        tester,
        _stateFor(TripPhase.completed, driver: _fakeDriver),
      );
      expect(find.byTooltip('Message driver'), findsNothing,
          reason: 'the completed phase does not render the on-road icon row at '
              'all — there is no live chat entry to disable');
    });

    testWidgets('the matched card disables Message when the chat window is '
        'shut, without disabling Call', (tester) async {
      // A driverEnRoute state (chat OPEN) renders a live Message row.
      await _bootStub(
        tester,
        _stateFor(TripPhase.driverEnRoute, driver: _fakeDriver),
      );
      final card =
          tester.widget<MatchedDriverCard>(find.byType(MatchedDriverCard));
      expect(card.onContact, isNotNull,
          reason: 'chat is OPEN on driverEnRoute — the entry must be live');
      expect(card.onCall, isNotNull,
          reason: 'Call is a separate affordance on the #45 seam — it is NOT '
              'gated on the chat window');
      expect(identical(card.onContact, card.onCall), isFalse,
          reason: 'Message and Call must never be the same callback — that '
              'identity WAS the Wave-0 lie');
    });
  });

  testWidgets('dark theme smoke: driverEnRoute renders without exceptions',
      (tester) async {
    final h = await _boot(tester, theme: _dark);

    await _pumpUntilFound(tester, etaClock);
    expect(find.text('Gurpreet is on the way'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _cleanup(tester, h);
  });

  // ── TRIP-01: every lifecycle phase recomposes to its OWN designed layout,
  // not one static shell with swapped labels. Each assertion pins a
  // phase-DISTINCTIVE element so a regression that collapses two states
  // together fails RED. Driven through a fixed-state stub interactor so the
  // rarely-reached phases (loading / error) are exercised deterministically.
  group('TRIP-01: 8 phases recompose to designed layouts', () {
    final cases = <TripPhase, String>{
      TripPhase.loading: 'Getting your trip…',
      TripPhase.finding: 'Confirming your driver…',
      TripPhase.driverEnRoute: 'is on the way',
      TripPhase.arrivingNow: 'Arriving now',
      TripPhase.driverArrived: 'is here',
      TripPhase.onRoad: 'On your way to',
      TripPhase.completed: "You've arrived at",
      TripPhase.cancelled: 'Trip cancelled',
      TripPhase.error: 'Something went wrong',
    };

    cases.forEach((phase, marker) {
      testWidgets('$phase renders its distinctive copy', (tester) async {
        await _bootStub(tester, _stateFor(phase));
        expect(find.textContaining(marker), findsWidgets,
            reason: '$phase must recompose to its own designed layout');
      });
    });

    testWidgets('error phase offers a real exit, not a dead end',
        (tester) async {
      await _bootStub(tester, _stateFor(TripPhase.error));
      expect(find.text('Back to home'), findsOneWidget);
    });
  });

  // ── TRIP-03: the #5 driver-info seam. Identity when present; a DESIGNED
  // degrade rung (never blank, never fabricated) when driverInfo is null.
  group('TRIP-03: matched-driver card + #5 degrade', () {
    testWidgets('renders identity when driverInfo present', (tester) async {
      await _bootStub(
        tester,
        _stateFor(TripPhase.driverEnRoute, driver: _fakeDriver),
      );
      expect(find.byType(MatchedDriverCard), findsOneWidget);
      expect(find.text('BK72 WNH'), findsOneWidget);
    });

    testWidgets('degrades to a designed rung when driverInfo is null (#5)',
        (tester) async {
      await _bootStub(
        tester,
        _stateFor(TripPhase.driverEnRoute), // driver: null
      );
      // No fabricated identity.
      expect(find.byType(MatchedDriverCard), findsNothing);
      // A designed, honest degrade surface fills the card slot instead of
      // a silent blank.
      expect(find.byType(DriverUnavailableCard), findsOneWidget);
      final size = tester.getSize(find.byType(DriverUnavailableCard));
      expect(size.height, greaterThan(48),
          reason: 'the #5 degrade is a real-sized surface, not blank');
    });
  });

  // ── BOOK-08: the "finding another driver" retry rung is a designed state
  // DISTINCT from a terminal failure, and never claims a driver was found.
  group('BOOK-08: MatchingRung retry state', () {
    Widget host(Widget child) => MaterialApp(
          theme: _light,
          home: Scaffold(body: child),
        );

    testWidgets('renders a "finding another driver" retry state',
        (tester) async {
      await tester.pumpWidget(host(MatchingRung(onExit: () {})));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('another driver'), findsWidgets,
          reason: 'the retry rung reflects the ongoing re-dispatch');
      // Never a fake success.
      expect(find.textContaining('found'), findsNothing);
      expect(find.textContaining('Driver assigned'), findsNothing);
    });

    testWidgets('is visually distinct from a terminal failure state',
        (tester) async {
      await tester.pumpWidget(host(MatchingRung(onExit: () {})));
      await tester.pump(const Duration(milliseconds: 300));

      // The retry rung is a LIVE search, not the dead-end failure card.
      expect(find.text("We couldn't get you moving"), findsNothing);
      expect(find.text('Try again'), findsNothing,
          reason: 'retry leads; it is not the manual dead-end');
    });

    testWidgets('keeps a manual exit reachable', (tester) async {
      var exits = 0;
      await tester.pumpWidget(host(MatchingRung(onExit: () => exits++)));
      await tester.pump(const Duration(milliseconds: 300));

      final exit = find.byType(TextButton);
      expect(exit, findsWidgets,
          reason: 'an escape hatch stays available under the retry');
      await tester.tap(exit.first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(exits, 1);
    });
  });
}

// ── Fixed-state stub interactor: drives TripScreen to an exact phase with
// zero timers so every lifecycle state (incl. loading / error) is
// deterministic. Never touches _phaseFor — it sets the resolved phase
// directly, exactly what the proven machine would have produced.
class _StubTripInteractor extends TripInteractor {
  _StubTripInteractor(this._fixed) : super('stub');

  final TripState _fixed;

  @override
  TripState build() => _fixed;
}

const _fakeDriver = RideDriverInfo(
  fullName: 'Gurpreet Singh',
  rating: 4.9,
  ratingCount: 12,
  tripsCount: 1480,
  vehicleMake: 'Toyota',
  vehicleModel: 'Prius',
  vehicleColour: 'Silver',
  plate: 'BK72 WNH',
  etaSeconds: 120,
  originLabel: 'Wolverhampton Rail Station',
  destinationLabel: 'New Cross Hospital',
);

TripState _stateFor(TripPhase phase, {RideDriverInfo? driver}) => TripState(
      phase: phase,
      driver: driver,
      etaSecondsRemaining: phase == TripPhase.driverEnRoute ? 120 : null,
      error: phase == TripPhase.error ? 'We could not load this trip.' : null,
    );

/// Mounts TripScreen with a fixed-phase stub interactor (map pinned hidden).
Future<void> _bootStub(WidgetTester tester, TripState state) async {
  final container = ProviderContainer(overrides: [
    mapInteractorProvider.overrideWith2((_) => _HiddenMapStub()),
    tripInteractorProvider.overrideWith2((_) => _StubTripInteractor(state)),
  ]);
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/trip/stub',
    routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home-stub'))),
      GoRoute(
        path: '/trip/:id',
        builder: (_, state) => TripScreen(rideId: state.pathParameters['id']!),
      ),
    ],
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: _light, routerConfig: router),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

// One ThemeData per mode, reused across every pump — a fresh instance
// restarts AnimatedTheme + Material implicit animations and pollutes
// assertions (04-02 test-harness trap).
final _light = HoppinTheme.riderLight();
final _dark = HoppinTheme.riderDark();

/// Boots the demo world through the scripted match beat, then pumps the trip
/// screen at /trip/:id inside a minimal test router (stub leaf routes let
/// intent-driven navigation be asserted without the full app shell).
Future<_Harness> _boot(
  WidgetTester tester, {
  ThemeData? theme,
  TripHandoff? handoff,
}) async {
  final world = DemoWorld.riderScenario(
    seed: DemoSeed.seed,
    store: InMemorySnapshotStore(),
  )..restoreOrSeed();
  final container = ProviderContainer(overrides: [
    ...riderDemoOverrides(world),
    // Pin the map riblet to the hidden rung: this suite proves the trip
    // CONTENT in the map-less layout (MAP-03's live-mode rung, still a
    // first-class production state) — map-mode composition is proven in
    // test/features/trip/map/map_view_test.dart.
    mapInteractorProvider.overrideWith2((_) => _HiddenMapStub()),
  ]);

  // The cancel path needs a signed-in userId; the demo auth accepts the
  // seeded credentials outright.
  await container.read(authServiceProvider).signInWithPassword(
        email: DemoSeed.riderCredentials.email,
        password: DemoSeed.riderCredentials.password,
      );
  if (handoff != null) {
    container.read(tripHandoffProvider.notifier).state = handoff;
  }

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
        builder: (_, state) =>
            TripScreen(rideId: state.pathParameters['id']!),
        routes: [
          GoRoute(
              path: 'receipt',
              builder: (_, _) => const Scaffold(body: Text('receipt-stub'))),
          GoRoute(
              path: 'chat',
              builder: (_, _) => const Scaffold(body: Text('chat-stub'))),
          // PHASE 11: the #45 call route. A STUB leaf, deliberately — this
          // suite proves the trip screen ROUTES to call (and never to chat);
          // call_screen_test.dart proves the surface itself is inert and
          // never dials.
          GoRoute(
              path: 'call',
              builder: (_, _) => const Scaffold(body: Text('call-stub'))),
        ],
      ),
    ],
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: theme ?? _light,
      routerConfig: router,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400)); // switcher settles

  return _Harness(world: world, container: container, rideId: rideId);
}

class _Harness {
  _Harness({required this.world, required this.container, required this.rideId});

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

/// Bounded pump-until (never pumpAndSettle — the demo world and the strip
/// pulse hold live tickers that stall settle detection).
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

/// Unmounts the tree (disposing the riblet's timers), then quiets the world
/// so no scripted timer trips the pending-timer invariant on teardown.
Future<void> _cleanup(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  h.container.dispose();
  h.world.reset();
}
