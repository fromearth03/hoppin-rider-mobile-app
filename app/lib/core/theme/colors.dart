import 'package:flutter/material.dart';

/// Brand tokens, shared with the driver app so both read as one product.
///
/// Never write a raw `Color()` in a widget. A colour that exists in only one
/// mode is a bug waiting for a rider in a dark cab at night.
///
/// ## Light and dark
///
/// The fixed tokens below (brand, semantic, the `light*` / `dark*` pairs) are
/// constants. The ADAPTIVE tokens further down ([background], [surface],
/// [ink], [fill] …) are getters that answer for whichever mode is on: a widget
/// writes `AppColors.surface` once and is right in both.
///
/// The mode is one static, [mode], set by `AppTheme.light` / `AppTheme.dark`
/// when a theme is built. It is deliberately not read from a BuildContext:
/// the app was drawn with a few hundred direct `AppColors.x` references, many
/// in helpers with no context in reach, and threading one through every call
/// was a rewrite of every screen. The price is that a widget holding one of
/// these colours is not told when the mode flips, so the app rebuilds its
/// whole tree on a theme change (see `app.dart`), which a settings switch can
/// afford.
class AppColors {
  AppColors._();

  /// Which mode the adaptive tokens answer for. Set by [AppTheme].
  static Brightness mode = Brightness.light;
  static bool get isDark => mode == Brightness.dark;

  // Brand – identical in both modes. The indigo IS Hoppin.
  static const primary = Color(0xFF2E0B78);
  static const primaryDark = Color(0xFF1E0550);
  static const accent = Color(0xFFF07A21);

  /// The dark navy the booking-flow designs use everywhere: filled buttons
  /// ("Confirm Schedule", "Cancel Ride", "Done"), selected chips
  /// ("Suggestion"), card borders and route polylines. Same value as
  /// [logoWord] so the wordmark and the chrome read as one.
  static const navy = Color(0xFF181C39);
  static const navyPressed = Color(0xFF2A2F55);

  /// Primary button fill — the navy from the booking-flow frames.
  static const buttonPrimary = navy;
  static const buttonPrimaryPressed = navyPressed;

  // Logo. The mark is red and the wordmark near-black in both modes — this is
  // a supplied brand asset, not a themed surface.
  static const logoMark = Color(0xFFE23038);
  static const logoWord = Color(0xFF181C39);

  // Semantic – same hue both modes; the surfaces around them change.
  static const positive = Color(0xFF2BA84A);
  static const negative = Color(0xFFD64545);
  static const warning = Color(0xFFE8A33D);
  static const info = Color(0xFF3D7FE8);

  // Light
  static const lightBackground = Color(0xFFF5F5F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE3E3E8);
  static const lightTextPrimary = Color(0xFF1A1A2E);
  static const lightTextSecondary = Color(0xFF6B6B7B);
  static const lightTextDisabled = Color(0xFFA0A0B0);

  // Dark – not inverted light. Surfaces lift off the background rather than
  // sinking into it, which is how depth reads without shadows in dark mode.
  static const darkBackground = Color(0xFF121218);
  static const darkSurface = Color(0xFF1E1E26);
  static const darkBorder = Color(0xFF32323E);
  static const darkTextPrimary = Color(0xFFF2F2F5);
  static const darkTextSecondary = Color(0xFFA8A8B8);
  static const darkTextDisabled = Color(0xFF6B6B7B);

  // ── Adaptive: one name, right in both modes ──────────────────────────────

  /// A one-off colour with its dark counterpart, for the places the frames
  /// use a shade that is not one of the tokens below: the light value is the
  /// frame's own, to the digit, so adding dark mode moved nothing in light.
  static Color pick(Color light, Color dark) => isDark ? dark : light;

  static Color get background => isDark ? darkBackground : lightBackground;
  static Color get surface => isDark ? darkSurface : lightSurface;
  static Color get border => isDark ? darkBorder : lightBorder;
  static Color get textPrimary => isDark ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary =>
      isDark ? darkTextSecondary : lightTextSecondary;
  static Color get textDisabled => isDark ? darkTextDisabled : lightTextDisabled;

  /// The navy the frames use for text, icons and outlines. On dark it is the
  /// light text colour: navy lettering on a dark page cannot be read.
  static Color get ink => isDark ? darkTextPrimary : navy;

  /// The brand indigo as lettering, an icon or an outline. The indigo itself
  /// is too deep to read on a dark page, so on dark it is a light violet. As a
  /// fill, use [primary]: that stays the brand indigo in both modes.
  static Color get brand => isDark ? const Color(0xFFA996FF) : primary;

  /// Navy used as a FILL: buttons, selected chips, switches, anything with
  /// white lettering on it. A navy fill vanishes into a dark page, so on dark
  /// it is the brand indigo raised until it stands out; the lettering on it
  /// stays white in both modes.
  static Color get fill => isDark ? const Color(0xFF4B32B5) : navy;
  static Color get fillPressed =>
      isDark ? const Color(0xFF5B43C4) : navyPressed;

  /// The bottom-sheet and panel grey of the frames (a shade off the page).
  static Color get sheet =>
      isDark ? const Color(0xFF191920) : const Color(0xFFF7F7FA);

  /// A quiet fill for chips, wells, skeletons and unselected controls.
  static Color get subtle =>
      isDark ? const Color(0xFF2A2A35) : const Color(0xFFF1F1F5);

  /// Soft status panels: a tinted background, its outline, and the lettering
  /// that goes on it.
  static Color get positiveSoft =>
      isDark ? const Color(0xFF16301F) : const Color(0xFFEFF7F1);
  static Color get positiveSoftBorder =>
      isDark ? const Color(0xFF2C5A3C) : const Color(0xFFB7DFC6);
  static Color get onPositiveSoft =>
      isDark ? const Color(0xFF7FD79B) : const Color(0xFF0B7A52);
  static Color get warningSoft =>
      isDark ? const Color(0xFF332A14) : const Color(0xFFFDF6E6);
  static Color get warningSoftBorder =>
      isDark ? const Color(0xFF6B5521) : const Color(0xFFF0C36D);
  static Color get onWarningSoft =>
      isDark ? const Color(0xFFEBC66A) : const Color(0xFF8A6D1F);
}
