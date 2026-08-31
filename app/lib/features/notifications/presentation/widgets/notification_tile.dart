import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../domain/notification_item.dart';

/// One row on the Notifications screen.
///
/// The design colours a thin left bar per notification (indigo, orange,
/// green) rather than by read state, so the bar is driven by [accent] chosen
/// by the caller from the item's position/kind rather than baked in here.
class NotificationTile extends StatelessWidget {
  final NotificationItem item;
  final Color accent;
  final VoidCallback? onTap;

  const NotificationTile({
    super.key,
    required this.item,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = Theme.of(context).colorScheme.surface;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                item.body,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cycles the three accent colours the design uses down the list, since the
/// placeholder source carries no "kind" field to key off of.
Color accentForIndex(int index) {
  const colours = [
    AppColors.primary,
    AppColors.accent,
    AppColors.positive,
  ];
  return colours[index % colours.length];
}
