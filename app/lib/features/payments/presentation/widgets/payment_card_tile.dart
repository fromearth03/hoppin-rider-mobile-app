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
          Icon(_brandIcon, color: theme.colorScheme.onSurface),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.displayLabel,
                  style: theme.textTheme.bodyLarge,
                  // Without this the card details wrap one character per
                  // line: "Make default" is wider than the default badge, so
                  // on a narrow row it squeezed this column to almost nothing
                  // and the number became an unreadable vertical stack.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
                const SizedBox(height: 2),
                Text(
                  'Expires $_expiry',
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ],
            ),
          ),
          if (card.isDefault)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.positive.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle,
                      size: 16, color: AppColors.positive),
                  SizedBox(width: 4),
                  Text('Default',
                      style: TextStyle(
                          color: AppColors.positive,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ],
              ),
            )
          else
            TextButton(
              onPressed: onMakeDefault,
              style: TextButton.styleFrom(
                // Compact, so the action cannot crowd out the card number
                // beside it — the one thing this row exists to show.
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                'Make default',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13),
              ),
            ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            color: AppColors.negative,
            tooltip: 'Remove card',
          ),
        ],
      ),
    );
  }
}
