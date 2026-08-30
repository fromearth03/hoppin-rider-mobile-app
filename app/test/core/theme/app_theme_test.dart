import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/core/theme/colors.dart';

void main() {
  group('AppTheme', () {
    test('light and dark are distinct and both defined', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.scaffoldBackgroundColor,
          isNot(AppTheme.dark.scaffoldBackgroundColor));
    });

    test('primary is the Hoppin indigo in both modes', () {
      expect(AppColors.primary, const Color(0xFF2E0B78));
      expect(AppTheme.light.colorScheme.primary, AppColors.primary);
      expect(AppTheme.dark.colorScheme.primary, AppColors.primary);
    });

    test('accent orange drives the primary action colour', () {
      expect(AppColors.accent, const Color(0xFFF07A21));
    });

    test('dark surfaces are darker than their light counterparts', () {
      // Guards against a dark theme that merely reuses light tokens.
      final light = AppColors.lightSurface.computeLuminance();
      final dark = AppColors.darkSurface.computeLuminance();
      expect(dark, lessThan(light));
    });

    test('body text meets 4.5:1 contrast on its own background', () {
      double ratio(Color fg, Color bg) {
        final l1 = fg.computeLuminance(), l2 = bg.computeLuminance();
        final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
        return (hi + 0.05) / (lo + 0.05);
      }

      expect(ratio(AppColors.lightTextPrimary, AppColors.lightBackground),
          greaterThanOrEqualTo(4.5));
      expect(ratio(AppColors.darkTextPrimary, AppColors.darkBackground),
          greaterThanOrEqualTo(4.5));
    });
  });
}
