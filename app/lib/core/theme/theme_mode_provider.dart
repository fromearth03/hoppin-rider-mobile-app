import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The rider's chosen appearance for this session.
///
/// Backed by nothing but process memory: `shared_preferences` is not a
/// dependency of this app and this pass may not add one, so there is no
/// place to persist a choice across restarts -- the picker sheet does not
/// claim to remember anything past the current session.
///
/// Defaults to LIGHT, not system: the design pack is light-only, every
/// fidelity comparison is against light frames, and a rider whose OS is
/// dark otherwise meets an unreviewed derived theme as their first
/// impression (Ismail hit exactly this, twice). Dark stays one tap away in
/// Settings > Appearance.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);
