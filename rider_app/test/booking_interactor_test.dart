import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/booking/booking_builder.dart';
import 'package:hoppin_rider/providers.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_rider/features/booking/booking_interactor.dart';
import 'package:hoppin_rider/features/booking/booking_state.dart';
import 'package:hoppin_rider/features/booking/place.dart';
import 'package:hoppin_rider/features/trip/trip_handoff.dart';

/// Interactor unit layer (riblet testing contract, DOCS/05) for the booking
/// riblet brain. The proven booking-controller contract — id-diff match
/// detection, generation guard, ACTIVE_TRIP_EXISTS adoption — is replayed
/// against the REAL demo world under FakeAsync, plus the 04-04 additions:
/// wall-clock staged matching copy, pending promo applied post-match, and
/// the TripHandoff write at the match beat.
void main() {
  test('id-diff match flow preserved: estimate, request, poll, matched', () {
    FakeAsync().run((async) {
      final h = _Harness();

      h.interactor.setPickup(_railStation);
      h.interactor.setDropoff(_newCross);
      async.flushMicrotasks();
      expect(h.state.phase, BookingPhase.estimated);
      expect(h.state.estimate, isNotNull);
      expect(
        h.state.estimate!.estimate.total,
        6.39,
        reason: 'the scripted Rail Station → New Cross quote is £6.39',
      );

      unawaited(h.interactor.requestRide());
      async.flushMicrotasks();
      expect(h.state.phase, BookingPhase.searching);

      // DemoScript (seed 42): the ride row appears ~3.6–4.8s after the
      // request; the 3s poll cadence discovers it on the second poll (6s).
      async.elapse(const Duration(milliseconds: 6300));
      expect(h.state.phase, BookingPhase.matched);
      expect(h.state.rideId, isNotNull);
      expect(
        h.state.rideId,
        h.world.rideHistory().first.id,
        reason: 'the unseen ride discovered by id-diff is the new one',
      );

      h.dispose();
    });
  });

  test('staged matching copy advances on the clock, not on ticks', () {
    FakeAsync().run((async) {
      final h = _Harness()..driveToSearching(async);

      expect(h.state.searchStartedAt, isNotNull);
      expect(h.state.matchingStage, 0);

      // Wall-clock thresholds ~0s / 2.5s / 5s from searchStartedAt. The 1s
      // stage timer quantises visibility to the next tick — assert stages
      // after ELAPSING past each threshold, never after counting ticks.
      async.elapse(const Duration(milliseconds: 2400));
      expect(h.state.matchingStage, 0);

      async.elapse(const Duration(milliseconds: 700)); // 3.1s elapsed
      expect(h.state.matchingStage, 1);

      async.elapse(const Duration(milliseconds: 2100)); // 5.2s elapsed
      expect(h.state.matchingStage, 2);
      expect(
        h.state.phase,
        BookingPhase.searching,
        reason: 'stage copy is a searching-only affair',
      );

      h.dispose();
    });
  });

  test('cancelSearch returns to estimated with places intact and the stage '
      'timer stopped', () {
    FakeAsync().run((async) {
      final h = _Harness()..driveToSearching(async);

      async.elapse(const Duration(milliseconds: 1200));
      h.interactor.cancelSearch();

      expect(
        h.state.phase,
        BookingPhase.estimated,
        reason:
            'cancel is a designed exit back to the estimate, '
            'never a dead end',
      );
      expect(h.state.pickup!.label, 'Wolverhampton Rail Station');
      expect(h.state.dropoff!.label, 'New Cross Hospital');
      expect(h.state.estimate, isNotNull);
      expect(h.state.searchStartedAt, isNull);
      expect(h.state.matchingStage, 0);

      // The stage timer is dead: nothing mutates the state ever again.
      async.elapse(const Duration(seconds: 10));
      expect(h.state.phase, BookingPhase.estimated);
      expect(h.state.matchingStage, 0);

      h.dispose();
    });
  });

  test('pending promo applies after match and rides the handoff', () {
    FakeAsync().run((async) {
      final h = _Harness();

      h.interactor.setPickup(_railStation);
      h.interactor.setDropoff(_newCross);
      async.flushMicrotasks();

      unawaited(h.interactor.setPendingPromo('  hoppin20 '));
      async.flushMicrotasks(); // staging now awaits the entry-check seam
      expect(
        h.state.pendingPromoCode,
        'HOPPIN20',
        reason: 'codes normalise to trimmed upper-case',
      );

      unawaited(h.interactor.requestRide());
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 6300));

      expect(h.state.phase, BookingPhase.matched);
      expect(
        h.world.eventLog.any((e) => e.contains('promoApplied')),
        isTrue,
        reason: 'the API can only apply a promo once the ride id exists',
      );
      final promo = h.state.appliedPromo;
      expect(promo, isNotNull);
      expect(promo!.newFare, lessThan(promo.originalFare));

      final handoff = h.container.read(tripHandoffProvider);
      expect(handoff, isNotNull);
      expect(handoff!.appliedPromo, isNotNull);
      expect(handoff.appliedPromo!.promoCode, 'HOPPIN20');
      expect(
        handoff.fareTotalPounds,
        promo.newFare,
        reason: 'the handoff fare is post-promo (04-01 contract)',
      );

      h.dispose();
    });
  });

  test('a bogus pending code leaves matched intact with a non-fatal '
      'promoError (live shape: entry check unavailable)', () {
    FakeAsync().run((async) {
      // Live shape: the entry seam answers null, so the bogus code stages
      // and only the match-beat applyPromo exposes it — the exact path a
      // real backend takes.
      final world = DemoWorld.riderScenario(
        seed: DemoSeed.seed,
        store: InMemorySnapshotStore(),
      )..restoreOrSeed();
      final container = ProviderContainer(overrides: [
        ridesRepositoryProvider.overrideWithValue(_NullPromoSeamRepo(world)),
      ]);
      final sub = container.listen(bookingInteractorProvider, (_, _) {});
      final interactor = container.read(bookingInteractorProvider.notifier);
      BookingState state() => container.read(bookingInteractorProvider);

      interactor.setPickup(_railStation);
      interactor.setDropoff(_newCross);
      async.flushMicrotasks();
      unawaited(interactor.setPendingPromo('BOGUS99'));
      async.flushMicrotasks();
      expect(state().pendingPromoCode, 'BOGUS99');

      unawaited(interactor.requestRide());
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 6300));

      expect(
        state().phase,
        BookingPhase.matched,
        reason: 'a promo failure must never block the match',
      );
      expect(state().rideId, isNotNull);
      expect(state().appliedPromo, isNull);
      expect(state().promoError, 'Promo code not found');

      final handoff = container.read(tripHandoffProvider);
      expect(handoff, isNotNull);
      expect(handoff!.appliedPromo, isNull);
      expect(handoff.fareTotalPounds, state().estimate!.estimate.total);
      expect(handoff.promoError, 'Promo code not found',
          reason: 'the failure must ride the handoff so the trip screen '
              'can say it out loud');

      sub.close();
      container.dispose();
      world.reset();
    });
  });

  test('handoff written on match: fare and duration mirror the estimate', () {
    FakeAsync().run((async) {
      final h = _Harness()..driveToSearching(async);
      final estimate = h.state.estimate!;

      async.elapse(const Duration(milliseconds: 6300));
      expect(h.state.phase, BookingPhase.matched);

      final handoff = h.container.read(tripHandoffProvider);
      expect(handoff, isNotNull);
      expect(handoff!.fareTotalPounds, estimate.estimate.total);
      expect(handoff.durationSeconds, estimate.durationSeconds);
      expect(handoff.appliedPromo, isNull);

      h.dispose();
    });
  });

  test('entry validation: a bad code is rejected with an error and never '
      'staged (demo seam answers)', () {
    FakeAsync().run((async) {
      final h = _Harness();
      h.interactor.setPickup(_railStation);
      h.interactor.setDropoff(_newCross);
      async.flushMicrotasks();

      unawaited(h.interactor.setPendingPromo('BOGUS99'));
      async.flushMicrotasks();
      expect(h.state.pendingPromoCode, isNull,
          reason: 'a code the world rejects must never sit staged looking '
              'accepted');
      expect(h.state.promoError, isNotNull);

      unawaited(h.interactor.setPendingPromo('hoppin20'));
      async.flushMicrotasks();
      expect(h.state.pendingPromoCode, 'HOPPIN20');
      expect(h.state.promoError, isNull,
          reason: 'a good code clears the earlier rejection');

      h.dispose();
    });
  });

  test('entry validation degrades to staging when the seam answers null '
      '(live shape)', () {
    FakeAsync().run((async) {
      final world = DemoWorld.riderScenario(
        seed: DemoSeed.seed,
        store: InMemorySnapshotStore(),
      )..restoreOrSeed();
      final container = ProviderContainer(overrides: [
        ridesRepositoryProvider
            .overrideWithValue(_NullPromoSeamRepo(world)),
      ]);
      final sub = container.listen(bookingInteractorProvider, (_, _) {});
      final interactor = container.read(bookingInteractorProvider.notifier);

      interactor.setPickup(_railStation);
      interactor.setDropoff(_newCross);
      async.flushMicrotasks();

      unawaited(interactor.setPendingPromo('ANYCODE'));
      async.flushMicrotasks();
      final state = container.read(bookingInteractorProvider);
      expect(state.pendingPromoCode, 'ANYCODE',
          reason: 'live cannot pre-check — the code stages and the match '
              'beat owns the truth');
      expect(state.promoError, isNull);

      sub.close();
      container.dispose();
      world.reset();
    });
  });

  test('handoff carries the ride id and journey so the receipt can rebook',
      () {
    FakeAsync().run((async) {
      final h = _Harness()..driveToSearching(async);
      async.elapse(const Duration(milliseconds: 6300));
      expect(h.state.phase, BookingPhase.matched);

      final handoff = h.container.read(tripHandoffProvider);
      expect(handoff, isNotNull);
      expect(handoff!.rideId, h.state.rideId);
      expect(handoff.pickup?.label, _railStation.label);
      expect(handoff.dropoff?.label, _newCross.label);

      h.dispose();
    });
  });

  test('generation guard intact: a late poll result never resurrects '
      'searching or matched', () {
    FakeAsync().run((async) {
      final h = _Harness()..driveToSearching(async);

      // Past the row-appearance window (~3.6–4.8s) but BEFORE the second
      // poll at 6s: the world already holds the unseen ride the next poll
      // would match on.
      async.elapse(const Duration(milliseconds: 4900));
      expect(h.state.phase, BookingPhase.searching);
      h.interactor.cancelSearch();
      expect(h.state.phase, BookingPhase.estimated);

      // If the guard were broken the released poll would discover the ride
      // and clobber the cancelled flow.
      async.elapse(const Duration(seconds: 5));
      expect(h.state.phase, BookingPhase.estimated);
      expect(h.state.rideId, isNull);

      h.dispose();
    });
  });

  test('ACTIVE_TRIP_EXISTS adoption preserved: a 409 re-request adopts the '
      'live ride', () {
    FakeAsync().run((async) {
      final h = _Harness()..driveToSearching(async);
      async.elapse(const Duration(milliseconds: 6300));
      expect(h.state.phase, BookingPhase.matched);
      final liveRideId = h.state.rideId;

      h.interactor.reset();
      h.interactor.setPickup(_railStation);
      h.interactor.setDropoff(_newCross);
      async.flushMicrotasks();
      expect(h.state.phase, BookingPhase.estimated);

      unawaited(h.interactor.requestRide());
      async.flushMicrotasks();
      expect(
        h.state.phase,
        BookingPhase.matched,
        reason: 'the 409 path finds the active ride and goes there',
      );
      expect(h.state.rideId, liveRideId);

      h.dispose();
    });
  });

  test('match invalidates the history cache so home sees the live trip', () {
    FakeAsync().run((async) {
      final h = _Harness();
      // Home keeps historyProvider alive all session (the '/' route never
      // unmounts) — model that with a persistent listener whose first
      // fetch lands BEFORE any ride exists.
      final histSub = h.container.listen(historyProvider, (_, _) {});
      async.flushMicrotasks();
      final before = h.container.read(historyProvider).value;
      expect(before, isNotNull);
      expect(
        before!.where((r) => r.status.isActive),
        isEmpty,
        reason: 'the seeded morning has no live ride before booking',
      );

      h.driveToSearching(async);
      async.elapse(const Duration(milliseconds: 6300));
      expect(h.state.phase, BookingPhase.matched);

      async.flushMicrotasks(); // let the invalidated provider refetch
      final after =
          h.container.read(historyProvider).value ?? const <Ride>[];
      expect(
        after.where((r) => r.status.isActive),
        isNotEmpty,
        reason: "home watches the cached history — the match beat must "
            "invalidate it or the 'Trip in progress' card never appears",
      );

      histSub.close();
      h.dispose();
    });
  });

  group('server geofence on Confirm Pickup (server wins, fail-open)', () {
    // A pickup INSIDE the client polygon (rail station) so the client
    // pre-filter passes and the SERVER check is what decides.
    ProviderContainer containerWith(bool? serverAnswer, DemoWorld world) =>
        ProviderContainer(overrides: [
          ridesRepositoryProvider
              .overrideWithValue(_GeofenceRepo(world, serverAnswer)),
        ]);

    test('a DEFINITIVE out-of-area (false) blocks — server overrides the '
        'client polygon', () {
      FakeAsync().run((async) {
        final world = DemoWorld.riderScenario(
          seed: DemoSeed.seed,
          store: InMemorySnapshotStore(),
        )..restoreOrSeed();
        final container = containerWith(false, world);
        final sub = container.listen(bookingInteractorProvider, (_, _) {});
        final interactor = container.read(bookingInteractorProvider.notifier);
        BookingState state() => container.read(bookingInteractorProvider);

        interactor.setPickup(_railStation); // inside the client ring
        interactor.setDropoff(_newCross);
        async.flushMicrotasks();
        unawaited(interactor.requestRide());
        async.flushMicrotasks();

        expect(state().phase, BookingPhase.outsideArea,
            reason: 'the client ring passed this pickup, but the server said '
                'out-of-area — server wins on a definitive answer');
        sub.close();
        container.dispose();
        world.reset();
      });
    });

    test('a null answer (timeout/error) FAILS OPEN — the booking proceeds', () {
      FakeAsync().run((async) {
        final world = DemoWorld.riderScenario(
          seed: DemoSeed.seed,
          store: InMemorySnapshotStore(),
        )..restoreOrSeed();
        final container = containerWith(null, world); // check could not be made
        final sub = container.listen(bookingInteractorProvider, (_, _) {});
        final interactor = container.read(bookingInteractorProvider.notifier);
        BookingState state() => container.read(bookingInteractorProvider);

        interactor.setPickup(_railStation);
        interactor.setDropoff(_newCross);
        async.flushMicrotasks();
        unawaited(interactor.requestRide());
        async.flushMicrotasks();

        expect(state().phase, BookingPhase.searching,
            reason: 'a failed/slow pre-check must NEVER strand a rider who is '
                'genuinely in-area — POST /rides/request is the real gate');
        expect(state().phase, isNot(BookingPhase.outsideArea));
        sub.close();
        container.dispose();
        world.reset();
      });
    });
  });
}

/// Live-shape delegate: everything demo-real except the promo-check seam,
/// which answers null exactly as the live repository does (no pre-ride
/// promo endpoint on :8080).
class _NullPromoSeamRepo extends FakeRidesRepository {
  _NullPromoSeamRepo(super.world);

  @override
  Future<bool?> isPromoValid(String promoCode) async => null;
}

/// Server geofence returns a scripted answer, so the confirm-pickup check can be
/// driven to each of its three outcomes: `false` (block), `null` (fail-open).
class _GeofenceRepo extends FakeRidesRepository {
  _GeofenceRepo(super.world, this._answer);
  final bool? _answer;

  @override
  Future<bool?> isServiceable(double lat, double lng) async => _answer;
}

// The scripted route: exact preset coordinates so the world's journey-label
// resolution and the £6.39 quote both hold.
const _railStation = Place(
  label: 'Wolverhampton Rail Station',
  lat: 52.5877,
  lng: -2.1200,
);
const _newCross = Place(
  label: 'New Cross Hospital',
  lat: 52.6046,
  lng: -2.0930,
);

/// A seeded rider-scenario world under the full demo composition, with the
/// booking interactor actively listened (Riverpod 3 pauses an unlistened
/// provider) — every test starts from the idle booking state.
class _Harness {
  _Harness() {
    world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();
    container = ProviderContainer(overrides: riderDemoOverrides(world));
    sub = container.listen(bookingInteractorProvider, (_, _) {});
  }

  late final DemoWorld world;
  late final ProviderContainer container;
  late final ProviderSubscription<BookingState> sub;

  BookingState get state => container.read(bookingInteractorProvider);

  BookingInteractor get interactor =>
      container.read(bookingInteractorProvider.notifier);

  /// Places chosen, estimate landed, request submitted — searching.
  void driveToSearching(FakeAsync async) {
    interactor.setPickup(_railStation);
    interactor.setDropoff(_newCross);
    async.flushMicrotasks();
    expect(state.phase, BookingPhase.estimated);
    unawaited(interactor.requestRide());
    async.flushMicrotasks();
    expect(state.phase, BookingPhase.searching);
  }

  void dispose() {
    sub.close();
    container.dispose();
    world.reset();
  }
}
