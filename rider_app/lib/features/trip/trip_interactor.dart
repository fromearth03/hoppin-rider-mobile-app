import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import '../../providers.dart';
import '../notifications/fcm_gateway.dart';
import '../notifications/notification_feed.dart';
import 'route_waypoints.dart';
import 'trip_handoff.dart';
import 'trip_state.dart';

/// THE BRAIN of the trip riblet (riblet anatomy, DOCS/05): polls the ride +
/// the DEMO-07 driver-info seam together every 3s until the ride is
/// terminal, maps status onto the Flighty smart phases, runs the 1Hz
/// wall-clock tick for the ETA hero and the RouteStrip fill, and owns every
/// promo/cancel/rating action. Zero Flutter widget imports; navigation
/// leaves ONLY as one-shot [TripNavIntent]s the router listener consumes.
///
/// Timing rules (Chrome timer throttling, DEMO-04):
/// - The ETA is a CLOCK DELTA — each poll with a non-null `etaSeconds`
///   re-aims `_etaDeadline = now + etaSeconds`, and the tick recomputes
///   `max(0, deadline − now)`. Ticks are never accumulated, so a throttled
///   tab still renders the right value on its next frame.
/// - All waits are cancellable [Timer]s cancelled in `ref.onDispose` —
///   nothing can strand a pending timer in flutter_test.
class TripInteractor extends Notifier<TripState> {
  TripInteractor(this.rideId);

  /// The family argument: which ride this riblet instance tracks.
  final String rideId;

  /// Bumped on dispose/rebuild; in-flight async work from an older
  /// generation discards its result instead of clobbering fresh state
  /// (the booking interactor's generation-guard pattern).
  int _generation = 0;

  Timer? _pollTimer;
  Timer? _ticker;
  Timer? _ratingTimer;
  DateTime? _etaDeadline;
  DateTime? _onRoadSince;
  bool _receiptFetched = false;
  bool _ratingTimerArmed = false;

  /// True once a LIVE (non-terminal) phase was observed. A completed ride
  /// mounted directly (history, deep link) never saw one — it must not
  /// replay the celebration or re-prompt for a rating.
  bool _sawLivePhase = false;

  static const _pollEvery = Duration(seconds: 3);
  static const _tickEvery = Duration(seconds: 1);

  /// The quiet beat between the arrival bloom and the rating sheet — the
  /// sheet slides up AFTER the moment, never over it (RIDER-05).
  static const _ratingPromptDelay = Duration(milliseconds: 1200);

  RidesRepository get _rides => ref.read(ridesRepositoryProvider);

  @override
  TripState build() {
    final gen = ++_generation;
    _etaDeadline = null;
    _onRoadSince = null;
    _receiptFetched = false;
    _ratingTimerArmed = false;
    _sawLivePhase = false;

    ref.onDispose(() {
      _generation++;
      _stopPolling();
      _stopTicker();
      _ratingTimer?.cancel();
      _ratingTimer = null;
    });

    _pollTimer = Timer.periodic(_pollEvery, (_) => unawaited(_poll(gen)));
    // First fetch immediately — the await inside yields, so the initial
    // state below is returned before any state write happens.
    unawaited(_poll(gen));

    // The booking flow hands over fare context at the match beat; null
    // after a reload is valid (consumers hide the fixed-fare reminder).
    final handoff = ref.read(tripHandoffProvider);
    return TripState(appliedPromo: handoff?.appliedPromo);
  }

  // ── Poll loop ─────────────────────────────────────────────────────────

  Future<void> _poll(int gen) async {
    if (gen != _generation) return;
    try {
      // Ride + driver info polled TOGETHER (one beat, both started before
      // either await) so phase and telemetry never disagree for a frame.
      final rideFuture = _rides.getRide(rideId);
      final infoFuture = _rides.driverInfo(rideId);
      final ride = await rideFuture;
      final info = await infoFuture;
      if (gen != _generation) return;
      _absorb(gen, ride, info);
    } on Exception catch (e) {
      if (gen != _generation) return;
      if (state.ride == null) {
        // Nothing ever loaded — a designed error state (with exits) beats
        // an eternal placeholder. The poll keeps retrying underneath.
        state = state.copyWith(
          phase: TripPhase.error,
          error: friendlyErrorMessage(e),
        );
      }
      // Otherwise: transient failure — keep the last shown state and retry
      // on the next tick (the old stream idiom's semantics).
    }
  }

  void _absorb(int gen, Ride ride, RideDriverInfo? info) {
    final previousPhase = state.phase;
    final driver = _mergeDriver(state.driver, info);

    // ETA re-sync: every poll that carries a countdown re-aims the deadline
    // at the world's truth; the 1Hz tick only ever reads it back.
    final etaSeconds = info?.etaSeconds;
    if (etaSeconds != null) {
      _etaDeadline = clock.now().add(Duration(seconds: etaSeconds));
    }

    final phase = _phaseFor(ride.status, etaSeconds);
    if (phase == TripPhase.onRoad) {
      _onRoadSince ??= clock.now();
    }
    if (!ride.status.isTerminal && phase != TripPhase.error) {
      _sawLivePhase = true;
    }

    final remaining = switch (phase) {
      TripPhase.driverEnRoute => _remainingSeconds(),
      TripPhase.arrivingNow => 0,
      _ => null,
    };
    final progress = switch (phase) {
      TripPhase.onRoad => _onRoadProgress(),
      TripPhase.completed => 1.0,
      _ => 0.0,
    };

    state = state.copyWith(
      phase: phase,
      ride: ride,
      driver: driver,
      etaSecondsRemaining: remaining,
      stripProgress: progress,
      activeWaypoint:
          phase == TripPhase.onRoad ? _waypointAt(progress, driver) : null,
      error: null,
    );

    // A genuine phase change is the rider-facing event the notification
    // centre is meant to carry. The FCM feed has no live producer (the
    // default gateway is the no-op), so without this the bell/centre stay
    // permanently empty. Emit the same titles a real push would.
    if (phase != previousPhase) {
      _notifyPhase(phase);
    }

    if (ride.status.isTerminal) {
      _stopPolling();
      _stopTicker();
      // The session-long history cache still holds this ride as live —
      // refresh it so home's card and recent rows flip with the ride.
      ref.invalidate(historyProvider);
      if (phase == TripPhase.completed) {
        _fetchReceiptOnce(gen);
        _armRatingPrompt(gen);
      }
    } else {
      _syncTicker(phase);
    }
  }

  /// Maps a trip phase to the notification a real push would carry and drops
  /// it into the session feed. Titles mirror fcm_gateway's _titleFor so a
  /// local event and a real push read identically. Non-milestone phases emit
  /// nothing.
  void _notifyPhase(TripPhase phase) {
    final (String, PushType)? event = switch (phase) {
      TripPhase.driverEnRoute =>
        ('Your driver is on the way', PushType.driverAssigned),
      TripPhase.arrivingNow =>
        ('Your driver is arriving', PushType.driverArriving),
      TripPhase.driverArrived =>
        ('Your driver has arrived', PushType.driverArrived),
      TripPhase.onRoad => ('Your trip has started', PushType.tripStarted),
      TripPhase.completed =>
        ('Your trip is complete', PushType.tripCompleted),
      TripPhase.cancelled =>
        ('Your trip was cancelled', PushType.tripCancelled),
      _ => null,
    };
    if (event == null) return;
    ref.read(notificationFeedProvider.notifier).addLocal(
          title: event.$1,
          rideId: rideId,
          type: event.$2,
        );
  }

  /// Status → smart phase (world semantics): accepted splits on the seam's
  /// countdown — a floored ETA is the calm "Arriving now" hold.
  TripPhase _phaseFor(RideStatus status, int? etaSeconds) => switch (status) {
        RideStatus.requested ||
        RideStatus.matching ||
        RideStatus.assigned =>
          TripPhase.finding,
        RideStatus.accepted => (etaSeconds != null && etaSeconds <= 0)
            ? TripPhase.arrivingNow
            : TripPhase.driverEnRoute,
        RideStatus.arriving => TripPhase.driverArrived,
        RideStatus.started => TripPhase.onRoad,
        RideStatus.completed => TripPhase.completed,
        RideStatus.cancelled => TripPhase.cancelled,
        RideStatus.unknown => TripPhase.error,
      };

  /// Keeps the identity through seam gaps and keeps the last known journey
  /// labels once the world archives the ride and drops them (04-01 caveat) —
  /// completion copy stays place-real.
  RideDriverInfo? _mergeDriver(RideDriverInfo? old, RideDriverInfo? incoming) {
    if (incoming == null) return old;
    if (old == null) return incoming;
    return incoming.copyWith(
      originLabel: incoming.originLabel ?? old.originLabel,
      destinationLabel: incoming.destinationLabel ?? old.destinationLabel,
    );
  }

  // ── 1Hz tick (ETA hero + strip fill) ──────────────────────────────────

  void _syncTicker(TripPhase phase) {
    final wanted =
        phase == TripPhase.driverEnRoute || phase == TripPhase.onRoad;
    if (wanted && _ticker == null) {
      _ticker = Timer.periodic(_tickEvery, (_) => _onTick());
    } else if (!wanted) {
      _stopTicker();
    }
  }

  void _onTick() {
    if (state.phase == TripPhase.driverEnRoute) {
      final remaining = _remainingSeconds();
      if (remaining != state.etaSecondsRemaining) {
        state = state.copyWith(etaSecondsRemaining: remaining);
      }
    } else if (state.phase == TripPhase.onRoad) {
      final progress = _onRoadProgress();
      state = state.copyWith(
        stripProgress: progress,
        activeWaypoint: _waypointAt(progress, state.driver),
      );
    }
  }

  /// `max(0, deadline − now)` in whole seconds (ceil, matching the world's
  /// own countdown math). Never negative; null when no countdown runs.
  int? _remainingSeconds() {
    final deadline = _etaDeadline;
    if (deadline == null) return null;
    final ms = deadline.difference(clock.now()).inMilliseconds;
    return math.max(0, (ms / 1000).ceil());
  }

  /// Perceptual continuous fill (Deliveroo/JET tracker pattern): the strip
  /// always moves, claims no precision the app doesn't have, is mode-blind
  /// (pure clock elapsed, no demo timings), and stays honest at the edge —
  /// it caps at 0.95 and only the REAL completion event pins 1.0. The
  /// exponential gives a confident start that eases as the trip settles;
  /// the scripted 75s trip reaches ~0.83.
  double _onRoadProgress() {
    final since = _onRoadSince;
    if (since == null) return 0.05;
    final elapsed = clock.now().difference(since).inMilliseconds / 1000.0;
    final p = 0.05 + 0.90 * (1 - math.exp(-elapsed / 45.0));
    return math.min(p, 0.95);
  }

  /// The word waypoint for [progress]: thresholds walk the Wolverhampton
  /// list; null before the first landmark or when the route is unknown.
  String? _waypointAt(double progress, RideDriverInfo? driver) {
    final words = waypointsFor(driver?.originLabel, driver?.destinationLabel);
    if (words.isEmpty) return null;
    const thresholds = [0.15, 0.40, 0.65, 0.85];
    String? current;
    for (var i = 0; i < words.length && i < thresholds.length; i++) {
      if (progress >= thresholds[i]) current = words[i];
    }
    return current;
  }

  // ── Completion ────────────────────────────────────────────────────────

  void _fetchReceiptOnce(int gen) {
    if (_receiptFetched) return;
    _receiptFetched = true;
    unawaited(() async {
      try {
        final receipt = await _rides.receipt(rideId);
        if (gen != _generation) return;
        state = state.copyWith(receipt: receipt);
      } on Exception {
        // The view degrades (headline without the paid line) — polling has
        // stopped, so there is no retry path to confuse.
      }
    }());
  }

  /// Arms the one-shot post-bloom beat, after which the view presents the
  /// rating sheet exactly once. Rides mounted already-complete (history,
  /// deep links) never saw a live phase and never prompt.
  void _armRatingPrompt(int gen) {
    if (!_sawLivePhase || _ratingTimerArmed) return;
    _ratingTimerArmed = true;
    _ratingTimer = Timer(_ratingPromptDelay, () {
      if (gen != _generation) return;
      state = state.copyWith(ratingPromptDue: true);
    });
  }

  /// The view reports the sheet was presented; it will never re-open.
  void markRatingPromptShown() {
    state = state.copyWith(ratingPromptShown: true);
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// Applies [code] to the live ride. Success stores the [PromoResult] for
  /// the animate-down money moment; failure surfaces a display-ready reason
  /// (the PROMO_* codes are already human copy) without touching the phase.
  Future<void> applyPromo(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || state.promoBusy) return;
    final gen = _generation;
    state = state.copyWith(promoBusy: true, promoError: null);
    try {
      final result =
          await _rides.applyPromo(rideId: rideId, promoCode: trimmed);
      if (gen != _generation) return;
      state = state.copyWith(appliedPromo: result, promoBusy: false);
    } on Exception catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        promoBusy: false,
        promoError: friendlyErrorMessage(e),
      );
    }
  }

  /// Cancels with the seeded default reason ("Changed my mind").
  ///
  /// Rationale: the locked decision wants reasons asked AFTER cancellation
  /// (skippable survey), but `PATCH /rides/:id/cancel` REQUIRES a valid
  /// `reason_id` at cancel time — the seeded default id satisfies the API,
  /// the post-cancel survey satisfies the rider. Returns true on success;
  /// forces an immediate re-poll so the cancelled state renders without
  /// waiting for the next tick.
  Future<bool> cancelWithDefaultReason() async {
    final gen = _generation;
    final userId = ref.read(authServiceProvider).userId;
    if (userId == null) {
      state = state.copyWith(error: 'You need to be signed in to cancel.');
      return false;
    }
    // Fetch the REAL seeded reasons from the backend and pick a rider-actor
    // one — the app's old fabricated placeholder id 400'd every cancel (gap
    // #1). Prefer a no-penalty rider reason; fall back to the first rider
    // reason, then any reason.
    final String reasonId;
    try {
      final reasons = await _rides.cancellationReasons();
      final riderReasons =
          reasons.where((r) => r.actorType == 'rider').toList();
      final pick = riderReasons.firstWhere(
        (r) => !r.appliesPenaltyFee,
        orElse: () => riderReasons.isNotEmpty ? riderReasons.first : reasons.first,
      );
      reasonId = pick.id;
    } on Exception catch (e) {
      if (gen != _generation) return false;
      state = state.copyWith(error: friendlyErrorMessage(e));
      return false;
    }
    try {
      await _rides.cancel(
        rideId: rideId,
        reasonId: reasonId,
        canceledByUserId: userId,
        actorType: 'rider',
      );
      if (gen != _generation) return false;
      await _poll(gen);
      return true;
    } on ApiException catch (e) {
      if (gen != _generation) return false;
      // WAVE-0: on live this is the EXPECTED path, not the exceptional one.
      // The reason_id we send is a fabricated placeholder (no endpoint lists
      // the real ones — gap #1), so the server rejects it with
      // VALIDATION_FAILED and cancellation fails 100% of the time. A generic
      // "something went wrong" leaves the rider trapped in a ride they are
      // being charged for, with no idea what to do. Name the failure and give
      // them a way out that actually works.
      final rejectedReason = e.code == 'VALIDATION_FAILED';
      state = state.copyWith(
        error: rejectedReason
            ? "We couldn't cancel this ride — cancellation isn't working yet. "
                'Please contact support and we will sort it out for you.'
            : friendlyErrorMessage(e),
      );
      return false;
    } on Exception catch (e) {
      if (gen != _generation) return false;
      state = state.copyWith(error: friendlyErrorMessage(e));
      return false;
    }
  }

  /// `POST /rides/:id/rating` — score 1-5 plus optional comments.
  Future<bool> submitRating(int score, String? comments) async {
    final gen = _generation;
    try {
      await _rides.rate(rideId: rideId, score: score, comments: comments);
      return true;
    } on Exception catch (e) {
      if (gen == _generation) {
        state = state.copyWith(error: friendlyErrorMessage(e));
      }
      return false;
    }
  }

  // ── Navigation intents (consumed by TripNavigationHost) ──────────────

  void requestReceipt() => _setIntent(TripNavIntent.receipt);
  void requestChat() => _setIntent(TripNavIntent.chat);

  /// The masked-voice-call entry (#45). Distinct from [requestChat] on purpose:
  /// Wave 0 deleted a phone affordance that opened chat. This one opens the
  /// call surface, which discloses that masked calling is not live yet.
  void requestCall() => _setIntent(TripNavIntent.call);
  void requestSafety() => _setIntent(TripNavIntent.safety);
  void requestHome() => _setIntent(TripNavIntent.home);
  void requestBook() => _setIntent(TripNavIntent.book);

  /// Minimises the trip screen back to the Book tab without touching trip
  /// state. The rider re-enters via the live-trip banner on the Book tab.
  void requestMinimize() => _setIntent(TripNavIntent.minimize);

  /// The router listener acknowledges the intent it just navigated for.
  void consumeNavIntent() {
    if (state.navIntent != null) {
      state = state.copyWith(navIntent: null);
    }
  }

  void _setIntent(TripNavIntent intent) {
    state = state.copyWith(navIntent: intent);
  }

  // ── Timer hygiene ─────────────────────────────────────────────────────

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }
}
