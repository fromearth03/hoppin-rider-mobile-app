import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/saved_locations_repository.dart';

/// One saved place row: pin, label, rename and remove actions.
///
/// The star-in-accent-colour treatment matches how `RouteEntryScreen` marks a
/// saved result within its combined suggestion list, so a saved place reads
/// the same wherever it appears in the app.
class SavedPlaceTile extends StatelessWidget {
  final SavedLocation place;
  final VoidCallback? onRename;
  final VoidCallback? onRemove;

  const SavedPlaceTile({
    super.key,
    required this.place,
    required this.onRename,
    required this.onRemove,
  });

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
          const Icon(Icons.star_outline, color: AppColors.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              place.label,
              style: theme.textTheme.bodyLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename this place',
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            color: AppColors.negative,
            tooltip: 'Remove this place',
          ),
        ],
      ),
    );
  }
}
