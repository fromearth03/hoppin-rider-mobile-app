import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed unavailable-state for the rider's PROMO-CODE LIST (gap 72,
/// SL-13).
///
/// There is no `GET /me/promos` endpoint. The client therefore cannot know
/// which codes a rider holds — and the difference between that and "they hold
/// none" is the whole point of this widget.
///
/// 🔴 It must NEVER read "you have no promo codes". That asserts EMPTINESS.
/// The truth is IGNORANCE: we cannot LIST them. Asserting emptiness when the
/// truth is ignorance is precisely the quiet lie Phase 11 deleted from the
/// notification centre, and it is the same species of lie as a fake unread
/// badge — just a quieter one.
///
/// 🔴 It also FORWARDS. `POST /rides/:id/promo` is BOUND and already wired into
/// the fare panel: a code the rider already holds genuinely works. It simply
/// needs a ride, because no pre-ride validation endpoint exists (seam 46). So
/// the honest sentence is "enter it when you book" — a disclosure that strands
/// the rider is only half-honest (the CallUnavailableState precedent, which
/// offers chat).
///
/// ⚠️ This creates an uncomfortable asymmetry: the rider is told codes work,
/// but the app cannot show them any codes. That is TRUE. The alternative —
/// rendering the Figma frame's invented codes with their Copy buttons — is the
/// thing this project exists to not do.
///
/// It is CONSTRUCTED unconditionally on the codes section of
/// `promotions_screen.dart`: the seam is not "sometimes null", it is ALWAYS
/// null. That mount site is what the Group C reachability check looks for — a
/// declared-but-never-constructed disclosure is dead code wearing a compliance
/// badge.
///
/// Body-swaps to the live list with zero view changes when the endpoint ships.
class PromoCodesUnavailable extends StatelessWidget {
  /// Creates the gap-72 promo-codes disclosure.
  const PromoCodesUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const HopCard(
      child: HopEmptyState(
        compact: true,
        headline: "We can't list your promo codes yet",
        supporting:
            'Your codes will show here once we can load them. You can still '
            'use a code you already have — enter it when you book, and it comes '
            'off your fare there.',
      ),
    );
  }
}
