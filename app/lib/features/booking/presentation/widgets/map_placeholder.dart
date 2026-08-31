import 'package:flutter/material.dart';

import '../../../../core/theme/colors.dart';

/// Stands in for the Google map until a Maps SDK key exists.
///
/// This is NOT a stub of the kind the project rule forbids: it renders a real,
/// honest surface that says what it is, rather than pretending to be a map. The
/// sheet, the vehicle picker, the search field and the whole booking flow above
/// it are fully live against the real backend -- only the tiles are missing.
///
/// Replacing it is one widget swap: `google_maps_flutter`'s `GoogleMap` takes
/// the same slot, and the key restriction work is per-platform native config
/// that does not touch this file's callers.
class MapPlaceholder extends StatelessWidget {
  /// Shown in the centre. Keep it short - this is a status line, not copy.
  final String label;

  const MapPlaceholder({super.key, this.label = 'Map view'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        // A flat, neutral ground rather than fake streets. Drawing invented
        // roads would be worse than drawing none.
        color: isDark ? AppColors.darkSurface : const Color(0xFFE8EAED),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _GridPainter(isDark: isDark)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 40,
                  color: (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary)
                      .withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A faint grid, so the area reads as a deliberate surface rather than a
/// failed image load.
class _GridPainter extends CustomPainter {
  final bool isDark;
  const _GridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04)
      ..strokeWidth = 1;

    const step = 48.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.isDark != isDark;
}
