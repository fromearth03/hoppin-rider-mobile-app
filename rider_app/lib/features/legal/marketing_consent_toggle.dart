import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'consent_notifier.dart';
import 'widgets/consent_record_unavailable.dart';

/// The marketing / analytics consent toggle (COMPLY-01, PECR).
///
/// 🔴 **OFF by default. Un-ticked. A positive act is required.** PECR:
///
/// > *"People must take a positive action to consent, so you must not use
/// > pre-ticked opt-in boxes, silence or inactivity as evidence of consent."*
///
/// The ICO has taken enforcement action specifically on pre-ticked boxes. The
/// Figma agrees (Promotional Offers ships OFF).
///
/// 🔴 **It does NOT gate submit.** A signup that could not complete without a
/// marketing opt-in is precisely the "condition of service" the ICO says
/// produces invalid consent. The 18+ declaration already gates signup and it
/// remains the ONLY gate.
///
/// The choice lands in [marketingConsentProvider] — session-scoped, never
/// written to disk. [ConsentRecordUnavailable] is CONSTRUCTED directly beneath
/// the switch (gap-74 mount site 1, the moment of collection), so the rider is
/// told what the toggle can and cannot do at the moment they use it.
///
/// This same widget's provider drives the Settings "Promotional Offers" row —
/// the SAME consent choice, live, because withdrawal must be as easy as giving
/// (Art. 7(3)). That is gap-74 mount site 2.
class MarketingConsentToggle extends ConsumerWidget {
  /// Creates the OFF-by-default marketing consent toggle.
  const MarketingConsentToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final granted = ref.watch(marketingConsentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Send me offers and product updates',
                    style: type.body.copyWith(color: colors.textHi),
                  ),
                  SizedBox(height: hoppin.spacing.xs),
                  Text(
                    "Optional. Leave it off and nothing changes about your "
                    'rides.',
                    style: type.bodySmall.copyWith(color: colors.textMid),
                  ),
                ],
              ),
            ),
            SizedBox(width: hoppin.spacing.md),
            Switch(
              key: const Key('marketing_consent_switch'),
              value: granted,
              onChanged: (v) => ref
                  .read(marketingConsentProvider.notifier)
                  .set(granted: v),
            ),
          ],
        ),
        SizedBox(height: hoppin.spacing.sm),
        // Gap-74 mount site 1 — the moment of collection. Group C reachability
        // wants the rung CONSTRUCTED in a real view, and honesty wants it
        // exactly here: next to the control whose limits it describes.
        const ConsentRecordUnavailable(),
      ],
    );
  }
}
