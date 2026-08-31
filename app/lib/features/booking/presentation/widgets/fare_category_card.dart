import 'package:flutter/material.dart';

import '../../../../core/money.dart';
import '../../../../core/theme/colors.dart';
import '../../data/vehicle_repository.dart';

/// One vehicle category quoted with its own fare — "Pricing Details" /
/// "Choose your driver" in the design pack.
///
/// These are NOT driver cards. Dispatch solves a Hungarian assignment and
/// publishes exactly one match; there is no endpoint returning candidate
/// drivers. Each card is a vehicle category priced by its own
/// `POST /rides/estimate` call, matching the card language of
/// [VehicleCard] on the Select Vehicle screen.
class FareCategoryCard extends StatelessWidget {
  final VehicleCategory category;
  final Pence? farePence;
  final int? durationSeconds;
  final bool selected;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onTap;

  const FareCategoryCard({
    super.key,
    required this.category,
    required this.farePence,
    required this.durationSeconds,
    required this.selected,
    required this.onTap,
    this.isLoading = false,
    this.errorMessage,
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
        onTap: farePence == null ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(category.name), size: 34, color: AppColors.primary),
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
                        if (category.hasCapacity)
                          Text(
                            _subtitle(category, durationSeconds),
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.check_circle,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (isLoading)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (errorMessage != null)
                Text(
                  errorMessage!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.negative),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recommended fare', style: theme.textTheme.bodyMedium),
                    Text(
                      farePence!.format(),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(VehicleCategory category, int? durationSeconds) {
    final capacity = '${category.seats} Seats ${category.bags} Bags';
    if (durationSeconds == null) return capacity;
    final minutes = (durationSeconds / 60).round().clamp(1, 999);
    return '$capacity - $minutes min';
  }

  static const _icons = <String, IconData>{
    'standard': Icons.directions_car,
    'minicar': Icons.directions_car_outlined,
    'estate': Icons.directions_car_filled,
    'mpv': Icons.airport_shuttle_outlined,
    'minibus': Icons.airport_shuttle,
    'minitruck': Icons.local_shipping_outlined,
  };

  static IconData _iconFor(String name) =>
      _icons[name.toLowerCase().replaceAll(' ', '')] ??
      Icons.directions_car_outlined;
}
