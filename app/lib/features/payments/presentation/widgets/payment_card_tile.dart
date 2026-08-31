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
                Text(card.displayLabel, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text('Expires $_expiry', style: theme.textTheme.bodyMedium),
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
              child: const Text('Make default'),
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
