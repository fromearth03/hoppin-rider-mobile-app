// StateProvider lives in the legacy library in Riverpod 3 — it is the right
// shape for this write-once session seam (booking writes, trip reads).
import 'package:flutter_riverpod/legacy.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import '../booking/place.dart';

/// Session-scoped booking → trip handoff (the wave-2 interface contract).
///
/// The booking flow writes this the moment a ride matches; the trip screen
/// reads it to render the fixed-fare reminder and trip pacing without
/// re-quoting, and the receipt reads the journey to make Rebook carry the
/// trip. It is deliberately NOT persisted: after a reload it is null, and
/// consumers must degrade gracefully (hide the fixed-fare reminder; rebook
/// falls back to a fresh picker).
class TripHandoff {
  const TripHandoff({
    required this.fareTotalPounds,
    required this.durationSeconds,
    this.appliedPromo,
    this.promoError,
    this.rideId,
    this.pickup,
    this.dropoff,
  });

  /// The quoted fixed fare, in pounds — post-promo when one applied.
  final double fareTotalPounds;

  /// The quoted trip duration, in seconds.
  final int durationSeconds;

  /// The promo applied during booking, if any.
  final PromoResult? appliedPromo;

  /// Why the staged promo did NOT apply at the match beat, if it failed —
  /// the trip screen says this out loud so a staged code never vanishes
  /// silently.
  final String? promoError;

  /// The matched ride this handoff belongs to — consumers must compare
  /// before trusting the journey (an older handoff is not this ride's).
  final String? rideId;

  /// The booked journey (the Ride payload carries no coordinates, so this
  /// is the only place the places survive the booking reset).
  final Place? pickup;
  final Place? dropoff;
}

/// Null until the booking flow publishes a match; null again after a reload.
final tripHandoffProvider = StateProvider<TripHandoff?>((_) => null);
