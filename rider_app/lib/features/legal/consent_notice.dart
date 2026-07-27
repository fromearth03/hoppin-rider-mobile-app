import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The route the bundled privacy notice is served at. It RESOLVES — the app
/// must never render a link that 404s.
const String kPrivacyNoticeRoute = '/legal/privacy';

/// The signup TRANSPARENCY notice (COMPLY-01, Arts. 13/14).
///
/// 🔴 This is NOT a checkbox, NOT a wall, and NOT a gate. It cannot be, and the
/// ICO is the reason:
///
/// > *"Consent is unlikely to be the most appropriate basis for processing
/// > which is necessary to deliver the core service… If you require someone to
/// > agree to processing as a condition of service… in some circumstances it
/// > won't even count as valid consent."*
///
/// Ride processing rests on the **contract basis** (Art. 6(1)(b)): we process
/// the rider's details and location in order to perform the ride they asked us
/// for. Putting a consent wall in front of that would produce **invalid**
/// consent (not freely given — refuse and you get no ride) *while also being
/// the wrong lawful basis*. So we do neither.
///
/// What the contract basis requires INSTEAD is transparency, and that is the
/// entire job of this widget: tell the rider, at the point of collection, who
/// we are, what we do with their data, on what basis, what rights they have,
/// and where the full notice lives. **Transparency is what MAKES the contract
/// basis lawful** — the link below is not decoration, it is the mechanism.
///
/// The app therefore collects LESS than a naïve competitor and is MORE
/// compliant for it. That is a feature, stated affirmatively.
class ConsentNotice extends StatelessWidget {
  /// Creates the transparency notice.
  ///
  /// [onPrivacyTap] overrides the default navigation to [kPrivacyNoticeRoute]
  /// (used by tests and by hosts without a router above them).
  const ConsentNotice({this.onPrivacyTap, super.key});

  /// Optional override for the privacy-notice link's tap intent.
  final VoidCallback? onPrivacyTap;

  void _openPrivacyNotice(BuildContext context) {
    if (onPrivacyTap != null) {
      onPrivacyTap!();
      return;
    }
    GoRouter.maybeOf(context)?.push(kPrivacyNoticeRoute);
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return HopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'How we use your details',
            style: type.bodyMedium.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.sm),
          Text(
            'Hoppin uses your name, contact details and location to book and '
            'run your rides, and to take payment for them. We do that because '
            "it's necessary to provide the service you're asking us for — we "
            "don't ask you to consent to it, because you can't have a ride "
            'without it.',
            style: type.bodySmall.copyWith(color: colors.textMid),
          ),
          SizedBox(height: hoppin.spacing.sm),
          Text(
            'You can ask us for a copy of your data, correct it, or ask us to '
            "delete it — from Profile at any time. If you're unhappy with how "
            'we handle it, you can complain to the Information Commissioner.',
            style: type.bodySmall.copyWith(color: colors.textMid),
          ),
          SizedBox(height: hoppin.spacing.sm),
          // 'Read the full Privacy Notice' overflowed HopButton by 155px at a
          // 356px-wide signup form: the component's Row puts no Flexible around
          // its label, so a label wider than the button cannot shrink — it
          // overflows, and the whole signup screen fails to lay out.
          //
          // Shortened rather than fixing HopButton, because Phase 12 is required
          // to touch ZERO hoppin_ui files (the driver v3.0 milestone is editing
          // that package in parallel, and the small collision surface is what has
          // kept four phases merging clean). The unflexed label is a real
          // component defect and is logged for the driver milestone to fix; it
          // does not need to be fixed from here to make this link honest.
          HopButton.ghost(
            key: const Key('consent_privacy_link'),
            label: 'Privacy Notice',
            onPressed: () => _openPrivacyNotice(context),
          ),
        ],
      ),
    );
  }
}
