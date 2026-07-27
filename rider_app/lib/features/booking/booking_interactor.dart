import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import '../../providers.dart';
import '../trip/trip_handoff.dart';
import 'booking_state.dart';
import 'place.dart';

/// THE BRAIN of the booking riblet (riblet anatomy, DOCS/05) — the renamed
/// and relocated booking controller. The proven flow is preserved without
/// algorithmic change: estimate → request → search → match against `:8080`.
///
/// Key backend fact (docs/04): `POST /rides/request` returns a `request_id`,
/// NOT a ride id — dispatch creates the ride row asynchronously. Until push
/// arrives (needs FCM on the backend) we find our ride by snapshotting the
/// ids in `GET /rides` before requesting, then polling for a ride id we
/// haven't seen. Id-set diffing is clock-skew-proof, unlike `created_at`
/// comparisons.
///
/// 04-04 additions around that core:
/// - a pending promo code staged pre-request and applied once the ride id
///   exists (the API cannot apply pre-ride); failure is non-fatal;
/// - the wall-clock staged matching copy (searchStartedAt + a 1s timer that
///   derives the stage from elapsed time, never from tick counts);
/// - the TripHandoff write at the match beat, BEFORE the matched state flips
///   (so the router's navigation always finds it in place).
///
/// Zero Flutter widget imports; navigation stays OUT — the matched state is
/// the signal `BookingNavigationHost` (booking_router.dart) listens for.
class BookingInteractor extends Notifier<BookingState> {
  /// Ride ids that existed before the request — anything new is ours.
  Set<String> _knownRideIds = {};

  /// Bumped on every user action; in-flight async work from an older
  /// generation discards its result instead of clobbering fresh state.
  int _generation = 0;

  /// The staged-copy timer, armed only while searching.
  Timer? _stageTimer;

  /// The disposal-aware pause between polls: the timer completes the
  /// completer; cancel/reset/dispose release it early so no raw
  /// `Future.delayed` can strand a pending timer past the flow's life.
  Timer? _pollDelay;
  Completer<void>? _pollWait;

  static const _searchTimeout = Duration(seconds: 90);
  static const _pollEvery = Duration(seconds: 3);
  static const _stageEvery = Duration(seconds: 1);

  /// Wall-clock thresholds for the staged matching copy (0 → 1 → 2). The
  /// scripted match lands at ~4.2s, comfortably inside stage 1.
  static const _stageOneAt = Duration(milliseconds: 2500);
  static const _stageTwoAt = Duration(seconds: 5);

  @override
  BookingState build() {
    ref.onDispose(() {
      _generation++;
      _stopStageTimer();
      _releasePollWait();
    });
    return const BookingState();
  }

  RidesRepository get _rides => ref.read(ridesRepositoryProvider);

  /// The out-of-area state, built the same way whether the CLIENT polygon or the
  /// SERVER check rejected the pickup — both land the rider on the same
  /// ServiceUnavailableScreen, preserving the estimate + any staged promo.
  BookingState _outsideAreaState(BookingState s, Place pickup, Place dropoff) =>
      BookingState(
        phase: BookingPhase.outsideArea,
        pickup: pickup,
        dropoff: dropoff,
        estimate: s.estimate,
        pendingPromoCode: s.pendingPromoCode,
        promoUnvalidated: s.promoUnvalidated,
      );

  void setPickup(Place place) => _setPlaces(pickup: place);

  void setDropoff(Place place) => _setPlaces(dropoff: place);

  void _setPlaces({Place? pickup, Place? dropoff}) {
    if (state.phase == BookingPhase.searching ||
        state.phase == BookingPhase.requesting) {
      return; // locked while a request is in flight
    }
    _generation++;
    state = BookingState(
      phase: BookingPhase.idle,
      pickup: pickup ?? state.pickup,
      dropoff: dropoff ?? state.dropoff,
      pendingPromoCode: state.pendingPromoCode,
      promoUnvalidated: state.promoUnvalidated,
      selectedCategory: state.selectedCategory,
    );
    unawaited(_estimate());
  }

  /// Choose the ride-type / vehicle category (SL-1 static seam). Sets
  /// [BookingState.selectedCategory] and RE-RUNS the estimate so the fare
  /// reflects the class — exactly like [setPickup]/[setDropoff]. Guarded by
  /// the same in-flight lock: a category change mid-request/search is ignored
  /// so a queued dispatch is never disturbed (mirrors [_setPlaces]).
  void setCategory(String? categoryId) {
    if (state.phase == BookingPhase.searching ||
        state.phase == BookingPhase.requesting) {
      return; // locked while a request is in flight
    }
    if (categoryId == state.selectedCategory) return; // no-op, no re-estimate
    _generation++;
    state = BookingState(
      phase: BookingPhase.idle,
      pickup: state.pickup,
      dropoff: state.dropoff,
      pendingPromoCode: state.pendingPromoCode,
      promoUnvalidated: state.promoUnvalidated,
      selectedCategory: categoryId,
    );
    unawaited(_estimate());
  }

  /// Stages a promo code for the ride about to be requested. Normalised to
  /// trimmed upper-case; null (or blank) clears the staged code. Only
  /// meaningful before the request leaves — idle/estimated.
  ///
  /// Entry-time feedback rides the [RidesRepository.isPromoValid] capability
  /// seam: a definitive `false` rejects the code on the spot (never staged,
  /// [BookingState.promoError] set); `null` — the live shape, no pre-ride
  /// check exists — stages the code and leaves the truth to the match beat.
  ///
  /// #46 disclosure: the `null` branch also raises
  /// [BookingState.promoUnvalidated], which is what the view mounts the
  /// designed `PromoUnavailableState` on. Staging a code the backend never
  /// checked, with no word to the rider, is the silent hole — the rider walks
  /// away believing the code was validated. It was not.
  Future<void> setPendingPromo(String? code) async {
    if (state.phase != BookingPhase.idle &&
        state.phase != BookingPhase.estimated) {
      return;
    }
    final normalised = code?.trim().toUpperCase();
    if (normalised == null || normalised.isEmpty) {
      state = state.copyWith(
        pendingPromoCode: null,
        promoError: null,
        promoUnvalidated: false,
      );
      return;
    }

    final gen = _generation;
    bool? valid;
    try {
      valid = await _rides.isPromoValid(normalised);
    } on Exception {
      valid = null; // a failed check must never block staging
    }
    if (gen != _generation) return; // superseded by reset/re-estimate

    if (valid == false) {
      state = state.copyWith(
        pendingPromoCode: null,
        promoError: "'$normalised' isn't a valid promo code.",
        promoUnvalidated: false,
      );
      return;
    }
    state = state.copyWith(
      pendingPromoCode: normalised,
      promoError: null,
      // The seam answered NOTHING (live) → disclose. A definitive `true`
      // (demo) really was validated → the staged chip alone is honest.
      promoUnvalidated: valid == null,
    );
  }

  /// Re-run the estimate (also the retry action after a failure).
  Future<void> _estimate() async {
    final pickup = state.pickup;
    final dropoff = state.dropoff;
    if (pickup == null || dropoff == null) return;

    final category = state.selectedCategory;
    final gen = ++_generation;
    state = BookingState(
      phase: BookingPhase.estimating,
      pickup: pickup,
      dropoff: dropoff,
      pendingPromoCode: state.pendingPromoCode,
      promoUnvalidated: state.promoUnvalidated,
      selectedCategory: category,
    );
    try {
      final est = await _rides.estimate(
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
        dropoffLat: dropoff.lat,
        dropoffLng: dropoff.lng,
        vehicleCategoryId: category,
      );
      if (gen != _generation) return; // superseded by a newer action
      state = BookingState(
        phase: BookingPhase.estimated,
        pickup: pickup,
        dropoff: dropoff,
        estimate: est,
        pendingPromoCode: state.pendingPromoCode,
        promoUnvalidated: state.promoUnvalidated,
        selectedCategory: category,
      );
    } on Exception catch (e) {
      if (gen != _generation) return;
      // e.g. 422 NO_ZONE (pickup outside every zone) / NO_TARIFF — the
      // ApiException message is display-ready.
      state = BookingState(
        phase: BookingPhase.failed,
        pickup: pickup,
        dropoff: dropoff,
        error: friendlyErrorMessage(e),
        pendingPromoCode: state.pendingPromoCode,
        promoUnvalidated: state.promoUnvalidated,
        selectedCategory: category,
      );
    }
  }

  void retryEstimate() {
    if (state.phase != BookingPhase.failed) return;
    unawaited(_estimate());
  }

  /// Dismiss a booking block (outside-area or needs-verification) back to a
  /// usable booking surface — places and fare intact, ready to re-pick a
  /// pickup or retry once eligible. Never a dead end (decision A).
  void dismissBookingBlock() {
    if (state.phase != BookingPhase.outsideArea &&
        state.phase != BookingPhase.needsVerification) {
      return;
    }
    _generation++;
    state = BookingState(
      phase: state.estimate != null
          ? BookingPhase.estimated
          : BookingPhase.idle,
      pickup: state.pickup,
      dropoff: state.dropoff,
      estimate: state.estimate,
      pendingPromoCode: state.pendingPromoCode,
      promoUnvalidated: state.promoUnvalidated,
    );
  }

  /// `POST /rides/request` — the guarded on-demand entry point, then start
  /// looking for the ride dispatch creates.
  Future<void> requestRide() async {
    final s = state;
    final pickup = s.pickup;
    final dropoff = s.dropoff;
    if (!s.canRequest || pickup == null || dropoff == null) return;

    // ACTIVE-TRIP LOCK (belt-and-suspenders). Before spending a network call —
    // and before the backend's own 409 ACTIVE_TRIP_EXISTS backstop — honour any
    // live trip already visible in the history cache. An Uber-style app never
    // starts a second concurrent ride: if one exists, jump straight to it. The
    // 409 branch below stays the authority for the race where the cache is
    // stale (a trip created out of band since the last GET /rides).
    final existingActive = _activeRideFromCache();
    if (existingActive != null) {
      _generation++;
      state = BookingState(
        phase: BookingPhase.matched,
        pickup: pickup,
        dropoff: dropoff,
        rideId: existingActive.id,
      );
      return;
    }

    // Geofence pre-flight (BOOK-07, Lane D): fast-fail a pickup outside the
    // Wolverhampton licensing boundary BEFORE any network call. The client
    // ring is disclosed-approximate — the server check below (and the
    // `422 OUTSIDE_SERVICE_AREA` on request) stay the enforcement authority.
    if (!isInsideServiceArea(pickup.lat, pickup.lng)) {
      _generation++;
      state = _outsideAreaState(s, pickup, dropoff);
      return;
    }

    // Server-authoritative geofence (`GET /service-areas/check`) — the admin's
    // real licensed areas, which the hardcoded client polygon drifts from. It
    // runs HERE, on Confirm Pickup, because this is the last point before the
    // rider commits and the first point we have their final pickup.
    //
    // 🔴 SERVER WINS, but only on a DEFINITIVE answer. `false` → block. `true`,
    // a timeout, or an error → PROCEED: the client polygon already passed, and
    // `POST /rides/request` re-runs the definitive geofence with the audit log,
    // so a slow/failed pre-check must never strand a rider who is genuinely
    // in-area on flaky data. (`isServiceable` caps the wait at 2s and returns
    // null on timeout/error — see its contract.)
    //
    // Generation-guarded like every other await here: if the rider reset or
    // re-estimated during the check, this result is stale — drop it.
    final checkGen = ++_generation;
    final serverServiceable = await _rides.isServiceable(pickup.lat, pickup.lng);
    if (checkGen != _generation) return;
    if (serverServiceable == false) {
      _generation++;
      state = _outsideAreaState(state, pickup, dropoff);
      return;
    }

    final gen = ++_generation;
    state = BookingState(
      phase: BookingPhase.requesting,
      pickup: pickup,
      dropoff: dropoff,
      estimate: s.estimate,
      pendingPromoCode: s.pendingPromoCode,
      promoUnvalidated: s.promoUnvalidated,
      selectedCategory: s.selectedCategory,
    );

    // Snapshot existing ride ids so the poll can spot the new one.
    try {
      final existing = await _rides.history(limit: 20);
      _knownRideIds = existing.map((r) => r.id).toSet();
    } on Exception {
      _knownRideIds = {}; // non-fatal: worst case we adopt an older ride
    }
    if (gen != _generation) return;

    try {
      await _rides.requestRide(
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
        dropoffLat: dropoff.lat,
        dropoffLng: dropoff.lng,
        vehicleCategoryId: s.selectedCategory,
      );
    } on ApiException catch (e) {
      if (gen != _generation) return;
      if (e.code == 'ACTIVE_TRIP_EXISTS') {
        // Rider already has a live trip (409) — find it and go there instead.
        await _adoptActiveRide(gen);
        return;
      }
      if (e.code == 'ACCOUNT_NOT_ELIGIBLE') {
        // 403 — the account isn't verified/eligible yet. Route to the hard
        // verify wall (AUTH-02), never a bare `failed` dead end. The soft
        // VerifyBanner nags earlier; this is the block at the booking action.
        state = BookingState(
          phase: BookingPhase.needsVerification,
          pickup: pickup,
          dropoff: dropoff,
          estimate: s.estimate,
          pendingPromoCode: s.pendingPromoCode,
          promoUnvalidated: s.promoUnvalidated,
        );
        return;
      }
      if (e.code == 'OUTSIDE_SERVICE_AREA') {
        // 422 — the server (the authoritative boundary) declined the pickup.
        // Land on the same designed outside-area rung as the client pre-flight.
        state = BookingState(
          phase: BookingPhase.outsideArea,
          pickup: pickup,
          dropoff: dropoff,
          estimate: s.estimate,
          pendingPromoCode: s.pendingPromoCode,
          promoUnvalidated: s.promoUnvalidated,
        );
        return;
      }
      // Any other API failure keeps the designed failure card.
      state = BookingState(
        phase: BookingPhase.failed,
        pickup: pickup,
        dropoff: dropoff,
        estimate: s.estimate,
        error: friendlyErrorMessage(e),
        pendingPromoCode: s.pendingPromoCode,
        promoUnvalidated: s.promoUnvalidated,
      );
      return;
    } on Exception catch (e) {
      if (gen != _generation) return;
      state = BookingState(
        phase: BookingPhase.failed,
        pickup: pickup,
        dropoff: dropoff,
        estimate: s.estimate,
        error: friendlyErrorMessage(e),
        pendingPromoCode: s.pendingPromoCode,
        promoUnvalidated: s.promoUnvalidated,
      );
      return;
    }

    if (gen != _generation) return;
    state = BookingState(
      phase: BookingPhase.searching,
      pickup: pickup,
      dropoff: dropoff,
      estimate: s.estimate,
      pendingPromoCode: s.pendingPromoCode,
      promoUnvalidated: s.promoUnvalidated,
      selectedCategory: s.selectedCategory,
      searchStartedAt: clock.now(),
    );
    _startStageTimer(gen);
    unawaited(_pollForRide(gen));
  }

  Future<void> _pollForRide(int gen) async {
    final deadline = clock.now().add(_searchTimeout);
    while (clock.now().isBefore(deadline)) {
      await _pollPause();
      if (gen != _generation || state.phase != BookingPhase.searching) return;

      List<Ride> rides;
      try {
        rides = await _rides.history(limit: 10);
      } on Exception {
        continue; // transient — keep polling
      }
      if (gen != _generation || state.phase != BookingPhase.searching) return;

      for (final r in rides) {
        if (_knownRideIds.contains(r.id)) continue;
        if (r.status == RideStatus.cancelled) {
          // Dispatch exhausted this pass and cancelled it server-side. The
          // backend automatically re-dispatches (BOOK-08, decision 5) — reflect
          // that honestly as the "finding another driver" retry rung, NOT a
          // dead-end failure. The client owns no re-dispatch; it presents the
          // ongoing server retry and keeps a manual exit reachable.
          _enterRetrying();
          return;
        }
        await _publishMatch(gen, r.id);
        return;
      }
    }
    if (gen == _generation && state.phase == BookingPhase.searching) {
      // Search window elapsed with no match — same honest retry presentation
      // (the backend keeps re-dispatching), never a terminal failure card.
      _enterRetrying();
    }
  }

  /// Route the dispatch-exhausted / search-timeout branch to the designed
  /// BOOK-08 retry rung (decision 5). We do NOT change the poll/dispatch logic
  /// — the backend owns re-dispatch; this only swaps the client PRESENTATION
  /// from a dead-end `failed` card to the "finding another driver" rung. A
  /// manual exit stays reachable via [cancelSearch].
  void _enterRetrying() {
    _stopStageTimer();
    state = BookingState(
      phase: BookingPhase.retrying,
      pickup: state.pickup,
      dropoff: state.dropoff,
      estimate: state.estimate,
      pendingPromoCode: state.pendingPromoCode,
      promoUnvalidated: state.promoUnvalidated,
      selectedCategory: state.selectedCategory,
    );
  }

  /// The match beat: apply any pending promo (the API needs a ride id),
  /// write the TripHandoff, THEN flip matched — the booking router navigates
  /// on matched, so everything the trip screen reads is already in place.
  Future<void> _publishMatch(int gen, String rideId) async {
    final estimate = state.estimate;
    final pending = state.pendingPromoCode;

    PromoResult? applied;
    String? promoError;
    if (pending != null) {
      try {
        applied = await _rides.applyPromo(rideId: rideId, promoCode: pending);
      } on Exception catch (e) {
        // Non-fatal: the match stands, the trip promo row stays available.
        promoError = friendlyErrorMessage(e);
      }
      if (gen != _generation || state.phase != BookingPhase.searching) return;
    }

    if (estimate != null) {
      ref.read(tripHandoffProvider.notifier).state = TripHandoff(
        // Post-promo when one applied (04-01 contract).
        fareTotalPounds: applied?.newFare ?? estimate.estimate.total,
        durationSeconds: estimate.durationSeconds,
        appliedPromo: applied,
        promoError: promoError,
        rideId: rideId,
        pickup: state.pickup,
        dropoff: state.dropoff,
      );
    }

    _stopStageTimer();
    state = BookingState(
      phase: BookingPhase.matched,
      pickup: state.pickup,
      dropoff: state.dropoff,
      estimate: estimate,
      rideId: rideId,
      pendingPromoCode: pending,
      appliedPromo: applied,
      promoError: promoError,
    );
    // A ride now exists that the session-long history cache predates —
    // home's 'Trip in progress' card reads that cache, so refresh it here.
    ref.invalidate(historyProvider);
  }

  /// The rider's live trip from the already-loaded [historyProvider] cache, if
  /// any — the same `GET /rides` read the view's active-trip lock uses. Reads
  /// the cached value only (no await, no fetch trigger): the pre-request lock
  /// must be instant, and the API's 409 backstop covers a stale/empty cache.
  Ride? _activeRideFromCache() {
    final rides = ref.read(historyProvider).value ?? const <Ride>[];
    for (final r in rides) {
      if (r.status.isActive) return r;
    }
    return null;
  }

  Future<void> _adoptActiveRide(int gen) async {
    try {
      final rides = await _rides.history(limit: 10);
      if (gen != _generation) return;
      for (final r in rides) {
        if (r.status.isActive) {
          // Adopted, not freshly quoted: no handoff write — the trip screen
          // degrades gracefully when tripHandoffProvider is null.
          state = BookingState(
            phase: BookingPhase.matched,
            pickup: state.pickup,
            dropoff: state.dropoff,
            rideId: r.id,
          );
          return;
        }
      }
    } on Exception {
      // fall through to the generic message
    }
    if (gen == _generation) {
      state = BookingState(
        phase: BookingPhase.failed,
        pickup: state.pickup,
        dropoff: state.dropoff,
        error: 'You already have an active trip.',
      );
    }
  }

  /// Stop watching for a match. Client-side only: the queued request may
  /// still match server-side — `:8080` has no pre-match cancel endpoint
  /// (documented gap, see CODE-GRAPH.md §6). Returns to the ESTIMATED state
  /// (places and fare intact) — a designed exit, never a dead end. Reachable
  /// from both the first-pass [BookingPhase.searching] beat AND the BOOK-08
  /// [BookingPhase.retrying] rung (the rider's manual escape from the retry).
  void cancelSearch() {
    if (state.phase != BookingPhase.searching &&
        state.phase != BookingPhase.retrying) {
      return;
    }
    _generation++;
    _stopStageTimer();
    _releasePollWait();
    state = BookingState(
      phase: state.estimate != null
          ? BookingPhase.estimated
          : BookingPhase.idle,
      pickup: state.pickup,
      dropoff: state.dropoff,
      estimate: state.estimate,
      pendingPromoCode: state.pendingPromoCode,
      promoUnvalidated: state.promoUnvalidated,
    );
  }

  void reset() {
    _generation++;
    _stopStageTimer();
    _releasePollWait();
    state = const BookingState();
  }

  // ── Staged matching copy (wall-clock derived) ─────────────────────────

  void _startStageTimer(int gen) {
    _stopStageTimer();
    _stageTimer = Timer.periodic(_stageEvery, (_) {
      if (gen != _generation || state.phase != BookingPhase.searching) {
        _stopStageTimer();
        return;
      }
      final startedAt = state.searchStartedAt;
      if (startedAt == null) return;
      final elapsed = clock.now().difference(startedAt);
      final stage = elapsed >= _stageTwoAt
          ? 2
          : elapsed >= _stageOneAt
          ? 1
          : 0;
      if (stage != state.matchingStage) {
        state = state.copyWith(matchingStage: stage);
      }
    });
  }

  void _stopStageTimer() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

  // ── Disposal-aware poll pause ─────────────────────────────────────────

  Future<void> _pollPause() {
    final wait = Completer<void>();
    _pollWait = wait;
    _pollDelay = Timer(_pollEvery, () {
      if (!wait.isCompleted) wait.complete();
    });
    return wait.future;
  }

  /// Cancels the pending pause timer and releases the waiting poll loop —
  /// the generation check right after the await makes it exit cleanly.
  void _releasePollWait() {
    _pollDelay?.cancel();
    _pollDelay = null;
    final wait = _pollWait;
    _pollWait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
  }
}
