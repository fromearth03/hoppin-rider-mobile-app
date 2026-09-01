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

  /// True while the screen is in the design's "Select" mode. The frame draws
  /// no checkbox, so selection reads as a ring on the card the tile already
  /// draws rather than as new furniture the design does not have.
  final bool selectable;
  final bool selected;

  const NotificationTile({
    super.key,
    required this.item,
    required this.accent,
    this.onTap,
    this.selectable = false,
    this.selected = false,
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
            border: selectable && selected
                ? Border.all(color: accent, width: 2)
                : Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: theme.textTheme.titleMedium,
              ),
              // COALESCE means the server can send a title with no body; the
              // line is dropped rather than reserving empty space for it.
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The frame keys the left bar by what the notification IS: trip updates
/// navy, rating prompts orange, resolutions/refunds green. The endpoint
/// sends no kind field (title + body only), so the kind is read from the
/// title's own words, falling back to a position cycle so unrecognised
/// rows still match the design's alternation.
Color accentForItem(NotificationItem item, int index) {
  final title = item.title.toLowerCase();
  final body = item.body.toLowerCase();
  if (title.contains('rate') || title.contains('rating')) {
    return AppColors.accent;
  }
  if (title.contains('resolved') ||
      title.contains('refund') ||
      body.contains('refunded')) {
    return AppColors.positive;
  }
  if (title.contains('driver') ||
      title.contains('message') ||
      title.contains('ride') ||
      title.contains('trip')) {
    return AppColors.primary;
  }
  const colours = [AppColors.primary, AppColors.accent, AppColors.positive];
  return colours[index % colours.length];
}

/// Kept for callers that only have a position.
Color accentForIndex(int index) {
  const colours = [AppColors.primary, AppColors.accent, AppColors.positive];
  return colours[index % colours.length];
}
