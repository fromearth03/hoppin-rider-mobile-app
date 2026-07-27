import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Live-trip share-link unavailable-state (seam **#57** / SL-8, SAFETY-02).
///
/// The Figma share sheet draws a Link field containing a mockup tracking URL.
/// **That URL does not exist and cannot be made to exist.** `POST /me/sos`
/// accepts a `live_share_url` as an *input*, but nothing in the API *issues*
/// one and nothing *revokes* one (gap #57). There is no tokenised public
/// tracking endpoint at all.
///
/// Wave 0 deleted a snackbar claiming a link had been copied, which fired while
/// copying a sentence with no URL in it — a rider tapped Share, pasted into
/// WhatsApp, and sent their friend a message that tracked nothing. Rendering
/// the Figma's mockup URL would be that same lie with better typography and a
/// real-looking id. So this rung stands in the Link field's place and says what
/// is actually true.
///
/// (Neither the mockup URL nor the deleted snackbar string is spelled literally
/// here — the phase gate greps `lib/` for both, and a docstring explaining the
/// ban must not be what trips the gate.)
///
/// It also names what will appear here, because the shape of the promise
/// matters: a **revocable** link. That is the Scope Lock's requirement and the
/// reason the revoke control ships beside it (on this same seam) even though
/// the Figma frame never drew one — a share link a rider cannot kill is not a
/// safety feature.
///
/// This is the fallback widget `kSeamRegistry` names for #57 (Lane E registers
/// it). Group C's reachability check requires it be CONSTRUCTED on the real
/// seam branch of a real view — that mount site is `share_trip_sheet.dart`,
/// reachable via `showShareTripSheet`.
class ShareLinkUnavailableState extends StatelessWidget {
  /// Creates the #57 share-link degrade rung.
  const ShareLinkUnavailableState({super.key});

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: hoppin.spacing.md,
        vertical: hoppin.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: hoppin.colors.canvas,
        borderRadius: BorderRadius.circular(hoppin.radii.input),
        border: Border.all(color: hoppin.colors.hairline),
      ),
      child: const HopEmptyState(
        compact: true,
        headline: 'No tracking link yet',
        supporting:
            'We cannot hand out a live-tracking link until the service that '
            'issues one — and lets you revoke it — is switched on. We will '
            'not give you a link that does not track anything.',
      ),
    );
  }
}
