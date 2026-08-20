import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/trip/trip_builder.dart';
import 'package:hoppin_rider/providers.dart';
import 'package:hoppin_rider/features/trip/trip_interactor.dart';
import 'package:hoppin_rider/features/trip/trip_state.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// Interactor unit layer (riblet testing contract, DOCS/05) for the trip
/// riblet brain: smart-phase mapping, wall-clock ETA re-sync, strip
/// progress, promo/cancel/rating actions, one-shot nav intents, and the
/// stale-async generation guard — all proven against the REAL demo world
/// under FakeAsync so every scripted beat is exact and clock-honest.
void main() {
  test('maps ride status to smart phases across the scripted lifecycle', () {
    FakeAsync().run((async) {
      final h = _Harness(async);
      expect(h.state.phase, TripPhase.driverEnRoute);
      expect(h.state.ride!.status, RideStatus.accepted);

      // The ETA floors 120s after the match; the next 3s poll lands inside
      // the ~2.5s arriving hold and observes etaSeconds == 0.
      async.elapse(const Duration(milliseconds: 120100));
      async.flushMicrotasks();
      expect(h.world.arrivingNow, isTrue);
      expect(h.state.phase, TripPhase.arrivingNow);
      expect(h.state.etaSecondsRemaining, 0);

      // Driver taps drive the rest — deterministic, no script racing.
      h.world.markArrived(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.phase, TripPhase.driverArrived);

      h.world.startRide(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.phase, TripPhase.onRoad);

      h.world.completeRide(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.phase, TripPhase.completed);
      expect(h.state.stripProgress, 1.0);

      h.dispose();
    });
  });

  test(
    'ETA deadline re-syncs each poll, ticks 1Hz, and never goes negative',
    () {
      FakeAsync().run((async) {
        final h = _Harness(async);
        final first = h.state.etaSecondsRemaining!;
        expect(first, greaterThan(0));

        async.elapse(const Duration(seconds: 1));
        final afterOne = h.state.etaSecondsRemaining!;
        expect(afterOne, first - 1);

        async.elapse(const Duration(seconds: 1));
        expect(h.state.etaSecondsRemaining, first - 2);

        // A 10s jump (throttled-tab shape): the 1Hz tick recomputes from the
        // deadline and the next poll re-syncs to the world's truth — the value
        // snaps to reality instead of drifting by tick count.
        async.elapse(const Duration(seconds: 10));
        final worldRemaining = h.world.etaSecondsRemaining!;
        expect(h.state.etaSecondsRemaining, isNotNull);
        expect(
          (h.state.etaSecondsRemaining! - worldRemaining).abs(),
          lessThanOrEqualTo(1),
          reason: 'interactor ETA must track the world clock-delta, not ticks',
        );
        expect(h.state.etaSecondsRemaining, greaterThanOrEqualTo(0));

        h.dispose();
      });
    },
  );

  test('driver info populates from the seam once accepted', () {
    FakeAsync().run((async) {
      final h = _Harness(async);
      expect(h.state.driver, isNotNull);
      expect(h.state.driver!.plate, 'BK72 WNH');
      expect(h.state.driver!.fullName, 'Gurpreet Singh');
      expect(h.state.driver!.originLabel, 'Wolverhampton Rail Station');
      expect(h.state.driver!.destinationLabel, 'New Cross Hospital');
      h.dispose();
    });
  });

  test(
    'null driver info (pre-assignment / live seam) never crashes the phase',
    () {
      FakeAsync().run((async) {
        final repo = _StubRepo(
          ride: const Ride(
            id: 'ride-x',
            riderId: 'rider-x',
            status: RideStatus.matching,
          ),
        );
        final container = ProviderContainer(
          overrides: [ridesRepositoryProvider.overrideWithValue(repo)],
        );
        final sub = container.listen(
          tripInteractorProvider('ride-x'),
          (_, _) {},
        );
        async.flushMicrotasks();

        final state = container.read(tripInteractorProvider('ride-x'));
        expect(state.phase, TripPhase.finding);
        expect(state.driver, isNull);

        sub.close();
        container.dispose();
      });
    },
  );

  test('strip progress is monotonic on-road and snaps to 1.0 on completed', () {
    FakeAsync().run((async) {
      final h = _Harness(async)..driveToOnRoad(async);

      var last = h.state.stripProgress;
      expect(last, greaterThan(0));
      for (var i = 0; i < 6; i++) {
        async.elapse(const Duration(seconds: 5));
        final next = h.state.stripProgress;
        expect(
          next,
          greaterThanOrEqualTo(last),
          reason: 'the strip must only ever fill forwards',
        );
        expect(next, lessThan(1.0));
        last = next;
      }

      h.world.completeRide(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.stripProgress, 1.0);

      h.dispose();
    });
  });

  test('activeWaypoint walks the Wolverhampton list as progress crosses '
      'thresholds', () {
    FakeAsync().run((async) {
      final h = _Harness(async)..driveToOnRoad(async);

      h.pumpUntil(async, () => h.state.activeWaypoint != null);
      expect(h.state.activeWaypoint, 'Leaving the city centre');

      h.pumpUntil(
        async,
        () => h.state.activeWaypoint != 'Leaving the city centre',
      );
      expect(h.state.activeWaypoint, 'Along Wednesfield Road');

      h.pumpUntil(
        async,
        () => h.state.activeWaypoint != 'Along Wednesfield Road',
      );
      expect(h.state.activeWaypoint, 'Passing Heath Town');

      h.dispose();
    });
  });

  test('completion fetches the receipt once and stops the poll loop', () {
    FakeAsync().run((async) {
      final h = _Harness(async)..driveToOnRoad(async);

      h.world.completeRide(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.phase, TripPhase.completed);
      expect(h.state.receipt, isNotNull);
      expect(h.state.receipt!.totalPence, greaterThan(0));
      expect(h.counting.receiptCalls, 1);

      // Terminal means quiet: no further ride polls, ever.
      final callsAtTerminal = h.counting.getRideCalls;
      async.elapse(const Duration(seconds: 10));
      expect(h.counting.getRideCalls, callsAtTerminal);
      expect(h.counting.receiptCalls, 1);

      h.dispose();
    });
  });

  test('applyPromo success stores the result; unknown code surfaces a '
      'friendly error without changing phase', () {
    FakeAsync().run((async) {
      final h = _Harness(async)..driveToOnRoad(async);

      unawaited(h.interactor.applyPromo('HOPPIN20'));
      async.flushMicrotasks();
      final promo = h.state.appliedPromo;
      expect(promo, isNotNull);
      expect(promo!.promoCode, 'HOPPIN20');
      expect(promo.newFare, lessThan(promo.originalFare));
      expect(h.state.promoError, isNull);

      unawaited(h.interactor.applyPromo('BOGUS99'));
      async.flushMicrotasks();
      expect(h.state.promoError, 'Promo code not found');
      expect(
        h.state.phase,
        TripPhase.onRoad,
        reason: 'a promo failure must never disturb the trip phase',
      );
      expect(
        h.state.appliedPromo,
        isNotNull,
        reason: 'the earlier successful promo survives a failed retry',
      );

      h.dispose();
    });
  });

  test('cancel uses the seeded default reason id and rider actorType', () {
    FakeAsync().run((async) {
      final h = _Harness(async)..signIn(async);
      expect(h.state.phase, TripPhase.driverEnRoute);

      bool? result;
      unawaited(h.interactor.cancelWithDefaultReason().then((v) => result = v));
      async.flushMicrotasks();

      // The world rejects non-seeded reason ids with VALIDATION_FAILED, so a
      // recorded cancellation proves the seeded default id was sent.
      expect(result, isTrue);
      expect(h.world.eventLog, contains('accepted>rideCancelled>idle'));
      expect(
        h.state.phase,
        TripPhase.cancelled,
        reason: 'cancel must force an immediate re-poll',
      );
      expect(h.state.ride!.status, RideStatus.cancelled);

      h.dispose();
    });
  });

  test('started rider trip can cancel and exits the live-trip phase', () {
    FakeAsync().run((async) {
      final h = _Harness(async)..signIn(async);
      h.driveToOnRoad(async);

      bool? result;
      unawaited(h.interactor.cancelWithDefaultReason().then((v) => result = v));
      async.flushMicrotasks();

      expect(result, isTrue);
      expect(h.world.eventLog, contains('inTrip>rideCancelled>idle'));
      expect(h.state.phase, TripPhase.cancelled);
      expect(h.state.ride!.status, RideStatus.cancelled);

      h.dispose();
    });
  });

  test('submitRating records the score in the world', () {
    FakeAsync().run((async) {
      final h = _Harness(async)..driveToOnRoad(async);
      h.world.completeRide(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));

      bool? result;
      unawaited(
        h.interactor.submitRating(5, 'Lovely ride').then((v) => result = v),
      );
      async.flushMicrotasks();
      expect(result, isTrue);
      expect(h.world.eventLog.any((e) => e.contains('rideRated')), isTrue);

      h.dispose();
    });
  });

  test('nav intents are one-shot: set by request, cleared by consume', () {
    FakeAsync().run((async) {
      final h = _Harness(async);

      h.interactor.requestReceipt();
      expect(h.state.navIntent, TripNavIntent.receipt);
      h.interactor.consumeNavIntent();
      expect(h.state.navIntent, isNull);

      h.interactor.requestChat();
      expect(h.state.navIntent, TripNavIntent.chat);
      h.interactor.consumeNavIntent();
      expect(h.state.navIntent, isNull);

      h.dispose();
    });
  });

  test('generation guard: a disposed interactor never polls again and a '
      'fresh one starts clean', () {
    FakeAsync().run((async) {
      final h = _Harness(async);
      expect(h.counting.getRideCalls, greaterThan(0));

      h.sub.close();
      final callsAtDispose = h.counting.getRideCalls;
      async.elapse(const Duration(seconds: 10));
      expect(
        h.counting.getRideCalls,
        callsAtDispose,
        reason: 'disposal must cancel the poll loop outright',
      );

      // Re-create: the family builds a fresh interactor whose state was not
      // clobbered by anything left over from the disposed generation.
      final sub2 = h.container.listen(
        tripInteractorProvider(h.rideId),
        (_, _) {},
      );
      async.flushMicrotasks();
      expect(h.state.phase, TripPhase.driverEnRoute);
      sub2.close();

      h.container.dispose();
    });
  });

  test('completion invalidates the history cache so home rows stay fresh', () {
    FakeAsync().run((async) {
      final h = _Harness(async);
      // Home keeps historyProvider alive all session — model that with a
      // persistent listener whose fetch lands while the ride is live.
      final histSub = h.container.listen(historyProvider, (_, _) {});
      async.flushMicrotasks();
      final before = h.container.read(historyProvider).value ?? const <Ride>[];
      expect(before.where((r) => r.status.isActive), isNotEmpty);

      h.world.markArrived(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      h.world.startRide(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      h.world.completeRide(h.rideId);
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.phase, TripPhase.completed);

      async.flushMicrotasks(); // let the invalidated provider refetch
      final after = h.container.read(historyProvider).value ?? const <Ride>[];
      expect(
        after.where((r) => r.status.isActive),
        isEmpty,
        reason:
            'the completed ride must not read as live on home — the '
            'terminal beat refreshes the session-long history cache',
      );

      histSub.close();
      h.dispose();
    });
  });

  // 🔴 PHASE 11 — THE POLL FLOOR. Non-negotiable, forever.
  //
  // Push is strictly ADDITIVE over the 3s poll. Push may only ever ADD to
  // `notificationFeedProvider`; it may NEVER write `TripState`. If trip
  // correctness ever came to depend on a push arriving, then every gap that
  // blocks delivery (#15 payload schema, #16 lifecycle, #69 device_os has no
  // "web") would become a gap that BREAKS THE TRIP — and those gaps are the
  // backend's to close, on their timeline, not ours.
  //
  // Every phase test above already runs on the DEFAULT `fcmGatewayProvider`
  // (`NoopFcmGateway` — empty streams, no token, no permission). That the whole
  // 8-phase machine drives green with push structurally unreachable IS the
  // proof. This test pins the structural half so no future edit can quietly
  // introduce the dependency.
  group('PHASE 11: the 3s poll is the correctness floor', () {
    test('trip_interactor.dart NEVER reads the FCM gateway', () {
      final source = File(
        'lib/features/trip/trip_interactor.dart',
      ).readAsStringSync();

      expect(
        source.contains('fcmGatewayProvider'),
        isFalse,
        reason:
            'trip_interactor.dart must never read the FCM gateway. The 3s poll '
            'is the correctness floor; push is additive. The moment the trip '
            'machine depends on a push, gaps #15/#16/#69 stop being '
            '"notifications are gated" and start being "the trip is broken".',
      );
      expect(
        source.contains('notificationFeedProvider'),
        isFalse,
        reason:
            'nor may it read the notification feed — the dependency direction '
            'is one-way: push writes the feed, the feed never writes the trip.',
      );
    });
  });
}

/// Boots a rider-scenario world, requests the scripted ride, elapses to the
/// match beat (4.2s at seed 42), and listens to the trip interactor for the
/// live ride — the state every test starts from (driverEnRoute, ETA 120s).
class _Harness {
  _Harness(FakeAsync async) {
    world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();

    world.submitRideRequest(
      pickupLat: DemoPlaces.railStation.lat,
      pickupLng: DemoPlaces.railStation.lng,
      dropoffLat: DemoPlaces.newCrossHospital.lat,
      dropoffLng: DemoPlaces.newCrossHospital.lng,
    );
    async.elapse(const Duration(milliseconds: 4300));
    rideId = world.rideHistory().first.id;

    counting = _CountingRepo(FakeRidesRepository(world));
    auth = DemoAuthService(persona: DemoPersonas.rider, world: world);
    container = ProviderContainer(
      overrides: [
        ridesRepositoryProvider.overrideWithValue(counting),
        authServiceProvider.overrideWithValue(auth),
      ],
    );
    // Keep the interactor actively listened (the view's ref.watch in
    // production) — Riverpod 3 pauses an unlistened provider.
    sub = container.listen(tripInteractorProvider(rideId), (_, _) {});
    async.flushMicrotasks();
  }

  late final DemoWorld world;
  late final String rideId;
  late final _CountingRepo counting;
  late final DemoAuthService auth;
  late final ProviderContainer container;
  late final ProviderSubscription<TripState> sub;

  TripState get state => container.read(tripInteractorProvider(rideId));

  TripInteractor get interactor =>
      container.read(tripInteractorProvider(rideId).notifier);

  /// Signs the demo rider in so `userId` is non-null for cancel calls.
  void signIn(FakeAsync async) {
    unawaited(
      auth.signInWithPassword(
        email: DemoSeed.riderCredentials.email,
        password: DemoSeed.riderCredentials.password,
      ),
    );
    async.flushMicrotasks();
  }

  /// Drives the world to the started trip and waits for the poll to observe.
  void driveToOnRoad(FakeAsync async) {
    world.markArrived(rideId);
    world.startRide(rideId);
    async.elapse(const Duration(milliseconds: 3100));
    expect(state.phase, TripPhase.onRoad);
  }

  /// Elapses in small steps until [predicate] holds (bounded, never settle).
  void pumpUntil(FakeAsync async, bool Function() predicate) {
    for (var i = 0; i < 400; i++) {
      if (predicate()) return;
      async.elapse(const Duration(milliseconds: 250));
    }
    fail('pumpUntil timed out after 100 fake seconds');
  }

  void dispose() {
    sub.close();
    container.dispose();
  }
}

/// Counts repository traffic so poll-stops-at-terminal and fetch-once
/// contracts are provable; everything else delegates to the demo fake.
class _CountingRepo implements RidesRepository {
  _CountingRepo(this._inner);

  final RidesRepository _inner;
  int getRideCalls = 0;
  int receiptCalls = 0;

  @override
  Future<Ride> getRide(String id) {
    getRideCalls++;
    return _inner.getRide(id);
  }

  @override
  Future<Receipt> receipt(String rideId) {
    receiptCalls++;
    return _inner.receipt(rideId);
  }

  @override
  Future<RideDriverInfo?> driverInfo(String rideId) =>
      _inner.driverInfo(rideId);

  @override
  Future<List<Ride>> history({int limit = 50}) => _inner.history(limit: limit);

  @override
  Future<void> cancel({
    required String rideId,
    String? reasonId,
    required String canceledByUserId,
    required String actorType,
  }) => _inner.cancel(
    rideId: rideId,
    reasonId: reasonId,
    canceledByUserId: canceledByUserId,
    actorType: actorType,
  );

  @override
  Future<void> rate({
    required String rideId,
    required int score,
    String? comments,
  }) => _inner.rate(rideId: rideId, score: score, comments: comments);

  @override
  Future<PromoResult> applyPromo({
    required String rideId,
    required String promoCode,
  }) => _inner.applyPromo(rideId: rideId, promoCode: promoCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hand-fed single-ride repository for the graceful null-seam path.
class _StubRepo implements RidesRepository {
  _StubRepo({required this.ride});

  final Ride ride;

  @override
  Future<Ride> getRide(String id) async => ride;

  @override
  Future<RideDriverInfo?> driverInfo(String rideId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
