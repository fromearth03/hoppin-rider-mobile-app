import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The designed GATED "card payments coming soon" state.
///
/// Shown when Add card hits `503 PAYMENTS_DISABLED` — the payment service is
/// off, so there is no honest way to attach a card yet. This is the seam's
/// designed unavailable-state (registered by 09-05 against the Stripe gateway
/// gate). It is deliberately NOT a success: no green tick, no "card added" —
/// just an honest, well-crafted explanation with a single dismiss action.
///
/// This is the sheet CONTENT — [showComingSoonSheet] wraps it in a [HopSheet]
/// surface. Token-driven (`context.hoppin`), light/dark clean.
class ComingSoonSheet extends StatelessWidget {
  const ComingSoonSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final spacing = hoppin.spacing;

    // Scroll-safe so the sheet never overflows on short viewports.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A calm "in build" badge — the positive semantic (success token),
          // NOT a success tick. It signals "coming", never "done".
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.successSubtle,
              borderRadius: BorderRadius.circular(hoppin.radii.control),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.credit_card_outlined,
              size: 28,
              color: colors.success,
            ),
          ),
          SizedBox(height: spacing.lg),
          Text(
            'Card payments coming soon',
            textAlign: TextAlign.center,
            style: hoppin.type.section.copyWith(color: colors.textHi),
          ),
          SizedBox(height: spacing.sm),
          Text(
            'Adding a card needs our secure payment service, which is being '
            'switched on. Your saved cards, trip payments and receipts all '
            'work today — new card entry is the one piece still on the way.',
            textAlign: TextAlign.center,
            style: hoppin.type.meta.copyWith(color: colors.textMid),
          ),
          SizedBox(height: spacing.xl),
          HopButton.primary(
            label: 'Got it',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// Presents the [ComingSoonSheet] modally over the scrim. Returns when the
/// rider dismisses it.
Future<void> showComingSoonSheet(BuildContext context) {
  return HopSheet.show<void>(context, builder: (_) => const ComingSoonSheet());
}
