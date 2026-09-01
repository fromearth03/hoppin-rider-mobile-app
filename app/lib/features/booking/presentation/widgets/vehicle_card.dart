import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';
import '../../data/vehicle_repository.dart';

/// One vehicle class in the picker — `Select Vehicle.png`.
///
/// A white rounded card: car render on the left, name in bold navy with the
/// capacity line under it. The selected card fills light grey, exactly as the
/// frame draws it (no check glyph); selection is still announced to assistive
/// tech via [Semantics].
///
/// Seats and bags come from the API, never from the design. The Figma draws
/// Estate as 4/4, MPV as 6/4 and Minibus as 16/12; live values differ, and
/// rendering the drawn numbers would tell a rider a Minibus seats sixteen
/// when it seats eight.
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

    return Semantics(
      selected: selected,
      button: true,
      label: category.name,
      child: Material(
        color: selected ? const Color(0xFFE4E4E9) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                _Artwork(seats: category.seats),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _titleCase(category.name),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      // A category configured with neither seats nor bags shows
                      // no capacity line rather than "0 Seats 0 Bags", which
                      // would state something false.
                      if (category.hasCapacity)
                        Text(
                          '${category.seats} Seats ${category.bags} Bags',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Capitalises the first letter only — "standard" → "Standard" — while
  /// leaving the rest alone so acronym names survive ("MPV" must not become
  /// "Mpv").
  static String _titleCase(String s) => s.isEmpty
      ? s
      : s
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
}

/// Artwork keyed by CAPACITY, not by name — categories are admin-editable and
/// a new one can appear without an app release, but its seat count always
/// says what kind of vehicle it is: a car up to 5 seats, the minibus up to
/// 10, the coach beyond that.
class _Artwork extends StatelessWidget {
  final int seats;
  const _Artwork({required this.seats});

  String get _asset {
    if (seats > 10) return 'assets/vehicles/car_coach.png';
    if (seats > 5) return 'assets/vehicles/car_minibus.png';
    return 'assets/vehicles/car_white.png';
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      width: 60,
      height: 40,
      fit: BoxFit.contain,
      // If the asset ever fails to decode, fall back to a glyph rather than
      // a broken-image box.
      errorBuilder: (_, __, ___) => const Icon(Icons.directions_car,
          size: 34, color: AppColors.navy),
    );
  }
}
