import 'package:flutter/foundation.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import 'place.dart';

/// Where the booking flow currently is.
enum BookingPhase {
  /// Choosing locations; nothing in flight.
  idle,

  /// `POST /rides/estimate` in flight.
  estimating,

  /// Estimate shown; ready to request.
  estimated,

  /// `POST /rides/request` in flight.
  requesting,

  /// Request queued to dispatch (202) — polling history for our new ride.
  searching,

  /// Our ride appeared — `rideId` is set; the booking router hands over to
  /// the trip riblet.
  matched,

  /// Dispatch exhausted its first pass (a driver cancelled or none accepted in
  /// window) — the backend automatically re-dispatches (Scope Lock §4.1, BOOK-08).
  /// The view shows the designed "finding another driver" retry rung, NEVER a
  /// dead-end failure; a manual exit stays reachable. The new-driver signal is
  /// SEAMED on the Phase-11 notification plumbing.
  retrying,

  /// The pickup fell outside the service area (client geofence pre-flight, or
  /// the server's `422 OUTSIDE_SERVICE_AREA` authority). The view shows the
  /// designed [ServiceUnavailableScreen]; only booking is blocked (decision A).
  outsideArea,

  /// The account is not yet eligible to book — the server answered
  /// `403 ACCOUNT_NOT_ELIGIBLE` (unverified / under-18 / inactive). The view
  /// shows the hard OTP verify wall; the rest of the app stays reachable.
  needsVerification,

  /// Something failed — `error` holds a display-ready message.
  failed,
}

/// Immutable snapshot of the booking riblet. One class + a phase enum
/// (rather than a sealed hierarchy) to keep it approachable — the
/// BookingState shape the trip riblet copied (DOCS/05).
@immutable
class BookingState {
  const BookingState({
    this.phase = BookingPhase.idle,
    this.pickup,
    this.dropoff,
    this.estimate,
    this.rideId,
    this.error,
    this.pendingPromoCode,
    this.searchStartedAt,
    this.matchingStage = 0,
    this.appliedPromo,
    this.promoError,
    this.selectedCategory,
    this.promoUnvalidated = false,
  });

  final BookingPhase phase;
  final Place? pickup;
  final Place? dropoff;
  final FareEstimate? estimate;

  /// The chosen ride-type / vehicle category id (SL-1 static seam). Null is a
  /// valid, first-class value — the server defaults to Standard when absent,
  /// and Standard itself carries no id until `GET /vehicle-categories` lands.
  /// Threaded into both the estimate and the request so the fare and the
  /// dispatched class reflect the rider's choice.
  final String? selectedCategory;

  /// Set when [phase] == [BookingPhase.matched].
  final String? rideId;

  /// Set when [phase] == [BookingPhase.failed].
  final String? error;

  /// Promo code staged before the request (normalised upper-case). The API
  /// cannot apply a promo pre-ride, so the interactor holds it here and
  /// applies it the moment the ride id exists.
  final String? pendingPromoCode;

  /// Stamped on entering [BookingPhase.searching]; the staged matching copy
  /// derives its stage from wall-clock elapsed since this moment (never
  /// tick-accumulated — throttled tabs must recover, DEMO-04).
  final DateTime? searchStartedAt;

  /// Which staged matching line the view shows: 0 (&lt;2.5s), 1 (&lt;5s),
  /// 2 (after) — three short waits, not one long one.
  final int matchingStage;

  /// The pending promo's result once applied post-match; rides the
  /// TripHandoff into the trip riblet.
  final PromoResult? appliedPromo;

  /// Display-ready reason the pending promo failed to apply — non-fatal,
  /// the match stands and the trip promo row remains available.
  final String? promoError;

  /// TRUE when the staged [pendingPromoCode] was accepted WITHOUT a pre-ride
  /// check — the #46 seam ([RidesRepository.isPromoValid]) answered `null`,
  /// its live shape (no pre-ride promo endpoint exists). The code is staged
  /// and will be validated at the match beat; the rider must be TOLD that,
  /// not left to infer a tick. The booking view mounts the designed
  /// `PromoUnavailableState` on exactly this flag.
  ///
  /// False when the seam answered a definitive `true` (demo path) — there the
  /// staged chip alone is honest, because the code really was validated.
  final bool promoUnvalidated;

  bool get canRequest =>
      phase == BookingPhase.estimated && pickup != null && dropoff != null;

  bool get isBusy =>
      phase == BookingPhase.estimating ||
      phase == BookingPhase.requesting ||
      phase == BookingPhase.searching ||
      phase == BookingPhase.retrying;

  /// Sentinel that lets [copyWith] distinguish "not passed" from "set null".
  static const Object _unset = Object();

  /// Field-level updates (stage ticks, promo staging). Phase TRANSITIONS
  /// deliberately keep explicit constructor calls in the interactor — the
  /// original controller nulled non-carried fields on every transition and
  /// that exact semantics must survive the riblet split.
  BookingState copyWith({
    BookingPhase? phase,
    Object? pickup = _unset,
    Object? dropoff = _unset,
    Object? estimate = _unset,
    Object? rideId = _unset,
    Object? error = _unset,
    Object? pendingPromoCode = _unset,
    Object? searchStartedAt = _unset,
    int? matchingStage,
    Object? appliedPromo = _unset,
    Object? promoError = _unset,
    Object? selectedCategory = _unset,
    bool? promoUnvalidated,
  }) {
    return BookingState(
      phase: phase ?? this.phase,
      pickup: identical(pickup, _unset) ? this.pickup : pickup as Place?,
      dropoff: identical(dropoff, _unset) ? this.dropoff : dropoff as Place?,
      estimate: identical(estimate, _unset)
          ? this.estimate
          : estimate as FareEstimate?,
      rideId: identical(rideId, _unset) ? this.rideId : rideId as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      pendingPromoCode: identical(pendingPromoCode, _unset)
          ? this.pendingPromoCode
          : pendingPromoCode as String?,
      searchStartedAt: identical(searchStartedAt, _unset)
          ? this.searchStartedAt
          : searchStartedAt as DateTime?,
      matchingStage: matchingStage ?? this.matchingStage,
      appliedPromo: identical(appliedPromo, _unset)
          ? this.appliedPromo
          : appliedPromo as PromoResult?,
      promoError: identical(promoError, _unset)
          ? this.promoError
          : promoError as String?,
      selectedCategory: identical(selectedCategory, _unset)
          ? this.selectedCategory
          : selectedCategory as String?,
      promoUnvalidated: promoUnvalidated ?? this.promoUnvalidated,
    );
  }
}
