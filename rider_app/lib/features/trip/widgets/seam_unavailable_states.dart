import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// DS-04 designed unavailable-states for the rider capability seams.
///
/// Every SEAMED feature ships the widget its consumer renders when the seam
/// answers `null` — a designed, token-driven degraded state, NEVER a blank
/// over `null`. These are the fallback widgets `kSeamRegistry` names; the
/// group-C widget test (`apps/rider/test/seam_registry_test.dart`) pumps each
/// and asserts a designed element renders.
///
/// They are typography-led [HopEmptyState]s — no ad-hoc colours, paddings, or
/// strings; the design system owns the look. As the live endpoints ship
/// (gaps #41/#17 driver-location + ride-geo; #46 pre-ride promo) the consuming
/// views promote off these fallbacks to the live path.

/// Live-tracking / ride-geo unavailable-state (seams #41, #17).
///
/// The map degradation ladder's floor rendered as a standalone pane: when
/// neither the driver-location (#41) nor the route-geometry (#17) seam
/// answers, the rider still sees a designed "route only" surface — the pane
/// never collapses to a blank box.
class RouteOnlyMapState extends StatelessWidget {
  /// Creates the route-only unavailable-state.
  const RouteOnlyMapState({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopEmptyState(
      headline: 'Live map unavailable',
      supporting:
          'Showing route only — the live driver position will appear here '
          'once tracking is available for this trip.',
    );
  }
}

/// Driver-info unavailable-state (seam #5).
///
/// The live backend serves no driver-identity read yet
/// ([RidesRepository.driverInfo] answers `null`), so the trip screen's
/// pre-trip phases cannot render the [MatchedDriverCard]'s plate/name/rating.
/// Rather than collapse the card slot to a silent blank — or, worse,
/// fabricate an identity — the trip shows this designed, honest degrade rung:
/// a real-sized [HopCard] carrying a [HopEmptyState] that names the gap and
/// promises the details will fill in once the endpoint (#5) ships.
///
/// This is the fallback widget `kSeamRegistry` names for the #5 seam via
/// `MatchedDriverCard`; the group-C widget test pumps it and asserts a
/// designed element renders (never an empty box).
class DriverUnavailableCard extends StatelessWidget {
  /// Creates the #5 driver-info degrade rung.
  const DriverUnavailableCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopCard(
      child: HopEmptyState(
        compact: true,
        headline: 'Driver details unavailable',
        supporting:
            "Your driver is confirmed — their name, photo and vehicle "
            'details will appear here as soon as the ride service shares '
            'them.',
      ),
    );
  }
}

/// Pre-ride promo unavailable-state (seam #46).
///
/// The live path cannot validate a promo code before a ride exists, so the
/// entry-time check answers `null`. Rather than fake a tick/cross, the booking
/// flow shows this designed state and stages the code for the match beat.
class PromoUnavailableState extends StatelessWidget {
  /// Creates the pre-ride promo unavailable-state.
  const PromoUnavailableState({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopEmptyState(
      compact: true,
      headline: 'Code saved',
      supporting:
          "We'll check this promo when your driver is matched — pre-ride "
          'validation is coming soon.',
    );
  }
}
