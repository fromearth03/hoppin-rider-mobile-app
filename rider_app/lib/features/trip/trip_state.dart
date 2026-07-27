import 'package:flutter/foundation.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// Which smart state the trip screen composes (Flighty pattern: the screen
/// RECOMPOSES per phase — never one static layout with changing labels).
enum TripPhase {
  /// First fetch in flight; nothing known yet.
  loading,

  /// requested / matching / assigned — a driver is being confirmed
  /// (direct-URL edge case; the booking flow owns the matching beat).
  finding,

  /// accepted with a live countdown — the ticking ETA hero state.
  driverEnRoute,

  /// accepted with the ETA floored at zero — the calm "Arriving now" hold.
  arrivingNow,

  /// arriving — the driver is at the pickup, meet-your-driver state.
  driverArrived,

  /// started — the RouteStrip fills through the word waypoints.
  onRoad,

  /// completed — arrival bloom, payment reassurance, then the rating sheet.
  completed,

  /// cancelled — a designed end state with a book-again affordance.
  cancelled,

  /// The ride could not be loaded at all.
  error,
}

/// One-shot navigation intents. The interactor SETS them; ONLY
/// `TripNavigationHost` (trip_router.dart) translates them into `context.go`
/// and consumes them — no other trip code navigates (riblet rule, DOCS/05).
enum TripNavIntent { receipt, chat, call, safety, home, book, minimize }

/// Immutable snapshot of the trip riblet. One class + a phase enum, the
/// BookingState shape — no controllers, contexts, or repositories inside.
@immutable
class TripState {
  const TripState({
    this.phase = TripPhase.loading,
    this.ride,
    this.driver,
    this.etaSecondsRemaining,
    this.stripProgress = 0.0,
    this.activeWaypoint,
    this.receipt,
    this.appliedPromo,
    this.promoError,
    this.promoBusy = false,
    this.ratingPromptDue = false,
    this.ratingPromptShown = false,
    this.navIntent,
    this.error,
  });

  /// The smart state the view composes for.
  final TripPhase phase;

  /// The last ride row observed by the poll loop.
  final Ride? ride;

  /// Driver identity + journey labels from the DEMO-07 capability seam.
  /// Null is a VALID state (live mode, pre-assignment) — views degrade.
  final RideDriverInfo? driver;

  /// Wall-clock seconds until pickup, recomputed at 1Hz from the deadline
  /// the poll re-syncs. Never negative; null when no countdown runs.
  final int? etaSecondsRemaining;

  /// RouteStrip fill fraction 0..1 while on-road; snaps to 1.0 on completed.
  final double stripProgress;

  /// The current word waypoint ("Passing Heath Town"); null between words.
  final String? activeWaypoint;

  /// Fetched exactly once when the ride completes.
  final Receipt? receipt;

  /// The promo applied on-trip (or carried over from booking via handoff).
  final PromoResult? appliedPromo;

  /// Display-ready reason the last promo attempt failed.
  final String? promoError;

  /// True while a promo request is in flight (double-tap guard).
  final bool promoBusy;

  /// True once the post-completion beat has elapsed and the rating sheet
  /// should be presented (the interactor owns the delay timer).
  final bool ratingPromptDue;

  /// True once the view has presented the rating sheet — it never re-opens.
  final bool ratingPromptShown;

  /// Pending one-shot navigation intent; consumed by the router listener.
  final TripNavIntent? navIntent;

  /// Display-ready message when [phase] == [TripPhase.error] (or a failed
  /// action worth surfacing).
  final String? error;

  /// Sentinel that lets [copyWith] distinguish "not passed" from "set null".
  static const Object _unset = Object();

  TripState copyWith({
    TripPhase? phase,
    Ride? ride,
    RideDriverInfo? driver,
    Object? etaSecondsRemaining = _unset,
    double? stripProgress,
    Object? activeWaypoint = _unset,
    Receipt? receipt,
    PromoResult? appliedPromo,
    Object? promoError = _unset,
    bool? promoBusy,
    bool? ratingPromptDue,
    bool? ratingPromptShown,
    Object? navIntent = _unset,
    Object? error = _unset,
  }) {
    return TripState(
      phase: phase ?? this.phase,
      ride: ride ?? this.ride,
      driver: driver ?? this.driver,
      etaSecondsRemaining: identical(etaSecondsRemaining, _unset)
          ? this.etaSecondsRemaining
          : etaSecondsRemaining as int?,
      stripProgress: stripProgress ?? this.stripProgress,
      activeWaypoint: identical(activeWaypoint, _unset)
          ? this.activeWaypoint
          : activeWaypoint as String?,
      receipt: receipt ?? this.receipt,
      appliedPromo: appliedPromo ?? this.appliedPromo,
      promoError:
          identical(promoError, _unset) ? this.promoError : promoError as String?,
      promoBusy: promoBusy ?? this.promoBusy,
      ratingPromptDue: ratingPromptDue ?? this.ratingPromptDue,
      ratingPromptShown: ratingPromptShown ?? this.ratingPromptShown,
      navIntent: identical(navIntent, _unset)
          ? this.navIntent
          : navIntent as TripNavIntent?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  /// The phases in which the rider may still cancel (mirrors the backend's
  /// cancellable status set — matching/accepted/arriving, never started).
  bool get cancellable => switch (phase) {
        TripPhase.finding ||
        TripPhase.driverEnRoute ||
        TripPhase.arrivingNow ||
        TripPhase.driverArrived =>
          true,
        _ => false,
      };

  /// Client-side mirror of the server's active-trip-only chat window. The
  /// server `409 CHAT_CLOSED` remains the AUTHORITY — this is UX, so the
  /// rider never types into a channel that will reject them.
  ///
  /// NOT a copy of [cancellable], and deliberately so: chat is CLOSED while
  /// [TripPhase.finding] (there is no driver to message yet) and OPEN on
  /// [TripPhase.onRoad] (where cancelling is not). The two windows are the
  /// inverse of one another at both ends.
  bool get chatOpen => switch (phase) {
        TripPhase.driverEnRoute ||
        TripPhase.arrivingNow ||
        TripPhase.driverArrived ||
        TripPhase.onRoad =>
          true,
        _ => false,
      };
}
