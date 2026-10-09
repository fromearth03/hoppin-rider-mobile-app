import 'package:flutter/material.dart';

import 'colors.dart';

/// One theme per mode, built from tokens. Widgets read the theme, never
/// AppColors directly, except where a semantic colour has no theme slot.
class AppTheme {
  AppTheme._();

  /// Building a theme also points [AppColors]' adaptive tokens at its mode, so
  /// asking for a theme is all it takes to put the whole app in that mode.
  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    border: AppColors.lightBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    border: AppColors.darkBorder,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    AppColors.mode = brightness;
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      // Text buttons, focus rings and progress bars are drawn in `primary`.
      // The brand indigo is too deep to see on a dark page, so dark mode
      // hands them the light violet instead; fills that must stay indigo use
      // AppColors.primary directly.
      primary: dark ? AppColors.brand : AppColors.primary,
      onPrimary: dark ? const Color(0xFF1B1140) : Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.negative,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // The design pack's face — the rounded geometric type every frame is
      // set in. Bundled, not fetched: the app renders identically offline
      // and in tests. Weights 400/500/600/700 are declared in pubspec.yaml.
      fontFamily: 'Poppins',
      fontFamilyFallback: const ['NotoNaskhArabic', 'NotoSansDevanagari'],
      scaffoldBackgroundColor: background,
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        // The design floats every label on the field's top border, including
        // on empty fields — the label is the field's name, not a placeholder,
        // and the hint carries the example value underneath it.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(fontSize: 14, color: textSecondary),
        floatingLabelStyle: TextStyle(fontSize: 14, color: textPrimary),
        hintStyle: TextStyle(fontSize: 16, color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.negative),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: AppColors.fill,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.fill.withValues(alpha: 0.55),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
            fontFamilyFallback: ['NotoNaskhArabic', 'NotoSansDevanagari'],
          ),
        ),
      ),
    );
  }
}
