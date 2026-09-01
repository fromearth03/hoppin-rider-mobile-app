import 'package:flutter/material.dart';

/// Brand tokens, shared with the driver app so both read as one product.
///
/// Never write a raw `Color()` in a widget. A colour that exists in only one
/// mode is a bug waiting for a rider in a dark cab at night.
class AppColors {
  AppColors._();

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
}
