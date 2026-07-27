import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// App-level data providers shared by several rider screens.
/// (Feature-local providers live next to their feature.)

/// Trip history — `GET /rides`, newest first. Home shows the top few; the
/// History screen shows all. `autoDispose` refetches when nothing watches it.
final historyProvider = FutureProvider.autoDispose<List<Ride>>((ref) {
  return ref.watch(ridesRepositoryProvider).history();
});

/// The rider's saved places — `GET /me/saved-locations`. Invalidate after
/// add/delete so every watcher refreshes.
final savedLocationsProvider =
    FutureProvider.autoDispose<List<SavedLocation>>((ref) {
  return ref.watch(profileRepositoryProvider).savedLocations();
});

/// The rider's current live trip, if any — the id of the first ride whose
/// status is still active (not completed/cancelled/unknown). Null when there
/// is none, or while history is loading/errored (so a transient hiccup never
/// falsely reports a lock).
///
/// Derived synchronously from [historyProvider]'s cached value so the router
/// redirect can read it without awaiting. It refreshes whenever history is
/// invalidated — booking creates a ride, TripInteractor invalidates on a
/// terminal poll — which is exactly when the lock should engage or release.
///
/// This is the single source of truth for the Uber-style active-trip lock:
/// the router redirect (/book → /trip/:id) and the booking-flow backstop both
/// answer "is there a live trip, and which one" from here.
final activeRideIdProvider = Provider.autoDispose<String?>((ref) {
  final rides = ref.watch(historyProvider).value ?? const <Ride>[];
  for (final r in rides) {
    if (r.status.isActive) return r.id;
  }
  return null;
});
