import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Rider lane themes — Figma navy ink on cool-white paper (light) / warm
/// near-black canvas (dark), hand-tuned in hoppin_ui. Drop-in rewire: the
/// exported names are stable so every entrypoint through app.dart boots
/// branded.
final ThemeData hoppinLightTheme = HoppinTheme.riderLight();

/// Rider dark — the derived navy-on-near-black ramp (dark is first-class,
/// Figma draws light only).
final ThemeData hoppinDarkTheme = HoppinTheme.riderDark();
