import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import 'scheduled_state.dart';

/// THE BRAIN of the scheduled riblet (riblet anatomy, DOCS/05). Binds the
/// three existing repo methods — `GET /scheduled-rides` (list),
/// `POST /scheduled-rides` (create, ≥30-min floor server-enforced),
/// `GET /scheduled-rides/:id` (one) — to a phase-driven snapshot.
///
/// Zero widget imports; navigation stays OUT (the `/scheduled` route wiring is
/// convergence's job, 10-05). Every read/write wraps its failure in
/// [friendlyErrorMessage] so the gap-#22 not-found (which surfaces as a raw
/// `500 INTERNAL` on live) never reaches the rider as-is.
class ScheduledInteractor extends Notifier<ScheduledState> {
  /// Bumped on every user action; a stale async result from an older
  /// generation discards itself instead of clobbering fresh state.
  int _generation = 0;

  @override
  ScheduledState build() {
    ref.onDispose(() => _generation++);
    return const ScheduledState();
  }

  RidesRepository get _rides => ref.read(ridesRepositoryProvider);

  /// `GET /scheduled-rides` — load the rider's upcoming scheduled rides.
  Future<void> load() async {
    final gen = ++_generation;
    state = state.copyWith(phase: ScheduledPhase.loading, error: null);
    try {
      final rides = await _rides.scheduledRides();
      if (gen != _generation) return;
      state = ScheduledState(phase: ScheduledPhase.ready, rides: rides);
    } on Exception catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        phase: ScheduledPhase.error,
        error: friendlyErrorMessage(e),
      );
    }
  }

  /// `POST /scheduled-rides` — book a future ride. The ≥30-min floor is
  /// enforced client-side by the picker AND server-side (VALIDATION_FAILED);
  /// this method binds the call and refreshes the list on success.
  Future<void> create({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required DateTime requestedPickupTime,
    String? estimatedFareId,
    String? vehicleCategoryId,
  }) async {
    final gen = ++_generation;
    state = state.copyWith(phase: ScheduledPhase.loading, error: null);
    try {
      final created = await _rides.createScheduledRide(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
        requestedPickupTime: requestedPickupTime,
        estimatedFareId: estimatedFareId,
        vehicleCategoryId: vehicleCategoryId,
      );
      if (gen != _generation) return;
      // Merge the new ride in without a second round-trip; a subsequent
      // [load] reconciles with the server set.
      state = ScheduledState(
        phase: ScheduledPhase.ready,
        rides: [created, ...state.rides],
      );
    } on Exception catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        phase: ScheduledPhase.error,
        error: friendlyErrorMessage(e),
      );
    }
  }

  /// `GET /scheduled-rides/:id` — one scheduled ride. A not-found surfaces as
  /// a raw `500 INTERNAL` on live (gap #22) whose body is NOT rider-safe, so
  /// this maps a 404/500 to honest plain-English copy rather than passing the
  /// server string through; every other failure defers to
  /// [friendlyErrorMessage]. Either way the rider never sees a 500 or a
  /// stack trace.
  Future<void> fetchOne(String id) async {
    final gen = ++_generation;
    state = state.copyWith(phase: ScheduledPhase.loading, error: null);
    try {
      final ride = await _rides.scheduledRide(id);
      if (gen != _generation) return;
      // Keep it in the current set (dedup by id) so a detail read warms the
      // list too.
      final rest = state.rides.where((r) => r.id != ride.id);
      state = ScheduledState(
        phase: ScheduledPhase.ready,
        rides: [ride, ...rest],
      );
    } on Exception catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        phase: ScheduledPhase.error,
        error: _scheduledLookupMessage(e),
      );
    }
  }

  /// `DELETE /scheduled-rides/:id` — cancel while the row is pending or being
  /// matched. The server rejects converted rows with a 409 so an active ride
  /// cannot be silently removed from the rider's trip history.
  Future<void> cancel(String id) async {
    final gen = ++_generation;
    state = state.copyWith(phase: ScheduledPhase.loading, error: null);
    try {
      await _rides.cancelScheduledRide(id);
      if (gen != _generation) return;
      await load();
    } on Exception catch (e) {
      if (gen != _generation) return;
      state = state.copyWith(
        phase: ScheduledPhase.error,
        error: _scheduledCancelMessage(e),
      );
    }
  }

  /// Gap #22 guard: a not-found scheduled ride surfaces as a raw `500 INTERNAL`
  /// on live whose body ("INTERNAL") must never reach the rider. Map the
  /// known not-found shapes (404, or the mis-typed 500) to honest copy; defer
  /// anything else to the shared [friendlyErrorMessage].
  String _scheduledLookupMessage(Object e) {
    if (e is ApiException &&
        (e.statusCode == 404 ||
            e.code == 'NOT_FOUND' ||
            e.statusCode == 500 ||
            e.code == 'INTERNAL')) {
      return "We couldn't find that scheduled ride. It may have been "
          'cancelled or already started.';
    }
    return friendlyErrorMessage(e);
  }

  String _scheduledCancelMessage(Object e) {
    if (e is ApiException && e.statusCode == 409) {
      return 'This scheduled ride has already started. Open the active trip to cancel it.';
    }
    if (e is ApiException && e.statusCode == 404) {
      return 'That scheduled ride is no longer available.';
    }
    return friendlyErrorMessage(e);
  }
}
