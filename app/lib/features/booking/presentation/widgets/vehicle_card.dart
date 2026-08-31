import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/vehicle_repository.dart';

/// One vehicle class in the picker.
///
/// Seats and bags come from the API, never from the design. The Figma draws
/// Estate as 4/4, MPV as 6/4 and Minibus as 16/12; live values are 5/4, 7/5
/// and 8/6, and it omits MiniCar and MiniTruck entirely. Rendering the drawn
/// numbers would tell a rider a Minibus seats sixteen when it seats eight.
class VehicleCard extends StatelessWidget {
  final VehicleCategory category;
  final bool selected;
  final VoidCallback onTap;

  const VehicleCard({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: selected
          ? (isDark ? AppColors.darkBorder : const Color(0xFFE4E4E9))
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              _Artwork(name: category.name),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // A category configured with neither seats nor bags shows
                    // no capacity line rather than "0 Seats 0 Bags", which
                    // would state something false.
                    if (category.hasCapacity)
                      Text(
                        '${category.seats} Seats ${category.bags} Bags',
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Local artwork keyed by category name, with a generic fallback.
///
/// The API has no image field, and categories are admin-editable: a new one
/// can appear at any moment with no illustration. The fallback is therefore a
/// designed state rather than a placeholder -- MiniCar and MiniTruck are live
/// today and the designer never drew them.
class _Artwork extends StatelessWidget {
  final String name;
  const _Artwork({required this.name});

  static const _icons = <String, IconData>{
    'standard': Icons.directions_car,
    'minicar': Icons.directions_car_outlined,
    'estate': Icons.directions_car_filled,
    'mpv': Icons.airport_shuttle_outlined,
    'minibus': Icons.airport_shuttle,
    'minitruck': Icons.local_shipping_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icons[name.toLowerCase().replaceAll(' ', '')] ??
        Icons.directions_car_outlined;

    return Icon(icon, size: 34, color: AppColors.primary);
  }
}
