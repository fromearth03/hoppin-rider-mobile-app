import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/colors.dart';
import '../../domain/promotion_item.dart';

/// One card on the Promotional screen: a status pill, title, description and
/// a valid-until line, matching the design.
class PromotionCard extends StatelessWidget {
  final PromotionItem item;

  const PromotionCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusPill(status: item.status),
          const SizedBox(height: 16),
          Text(item.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(item.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          Text(
            'Valid Until: ${DateFormat('dd MMMM, yyyy').format(item.validUntil)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final PromotionStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      PromotionStatus.active => ('Active', AppColors.positive),
      PromotionStatus.availed => ('Availed', AppColors.primary),
      PromotionStatus.expired => ('Expire', AppColors.negative),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
