import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// BOOK-07 (decision A) — the outside-service-area unavailable state.
///
/// When a pickup falls outside the Wolverhampton licensing boundary, the
/// geofence pre-flight (`isInsideServiceArea`) fails fast and the booking
/// action shows THIS screen instead of firing the request. Decision A: only
/// the booking request is blocked — profile, payments and saved places stay
/// reachable, so this state is never a dead end. It ships the required exit
/// affordance back to a usable surface.
///
/// This is the designed unavailable-state widget the geofence seam registers.
/// The pre-flight WIRING into the booking action lands in the convergence plan
/// (09-05); this screen carries no navigation of its own — the caller passes
/// [onExit] so the host decides where "back to a usable surface" goes.
///
/// Token-driven throughout (built from the Phase-8 kit) — no raw pixel values.
class ServiceUnavailableScreen extends StatelessWidget {
  /// Creates the outside-service-area unavailable state.
  const ServiceUnavailableScreen({required this.onExit, super.key});

  /// Fired when the rider taps the exit affordance — the host returns them to
  /// a usable surface (e.g. Home). Never a dead end.
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: HopEmptyState(
        headline: 'Not in your area yet',
        supporting:
            "Hoppin isn't available in your area yet — we currently serve "
            'Wolverhampton. Everything else in the app stays available.',
        actionLabel: 'Back',
        onAction: onExit,
      ),
    );
  }
}
