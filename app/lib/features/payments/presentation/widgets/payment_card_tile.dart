import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/payment_methods_repository.dart';

/// One saved card row: brand icon, masked number, expiry, default badge and
/// actions.
///
/// Only a non-default card offers "Make default" — the design draws a badge
/// on every row, but offering to re-default the card that already is one is
/// a no-op action with nothing to press.
class PaymentCardTile extends StatelessWidget {
  final SavedCard card;
  final VoidCallback? onMakeDefault;
  final VoidCallback onRemove;

  const PaymentCardTile({
    super.key,
    required this.card,
    required this.onMakeDefault,
    required this.onRemove,
  });

  String get _expiry {
    final mm = card.expMonth.toString().padLeft(2, '0');
    final yy = (card.expYear % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }

  IconData get _brandIcon => switch (card.brand.toLowerCase()) {
        'visa' || 'mastercard' || 'amex' => Icons.credit_card,
        _ => Icons.credit_card,
      };

  String get _brandName => card.brand.isEmpty
      ? 'Card'
      : card.brand[0].toUpperCase() + card.brand.substring(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(_brandIcon, color: AppColors.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _brandName,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontSize: 15, color: AppColors.navy),
                  // Without this the card details wrap one character per
                  // line on a squeezed row.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
                const SizedBox(height: 2),
                Text(
                  // The frame masks everything but the tail; the expiry
                  // rides along so the rider can still spot a dying card.
                  '**** **** **** ${card.last4}   ·   $_expiry',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ],
            ),
          ),
          // The frame's badge: green scalloped check on the default card, a
          // grey one on the rest — tapping the grey badge makes that card
          // the default.
          if (card.isDefault)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child:
                  Icon(Icons.verified, size: 24, color: AppColors.positive),
            )
          else
            IconButton(
              onPressed: onMakeDefault,
              icon: const Icon(Icons.verified,
                  size: 24, color: AppColors.lightTextDisabled),
              tooltip: 'Make default',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.lightTextSecondary,
            tooltip: 'Remove card',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
