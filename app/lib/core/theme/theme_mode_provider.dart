import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The rider's chosen appearance for this session.
///
/// Backed by nothing but process memory: `shared_preferences` is not a
/// dependency of this app and this pass may not add one, so there is no
/// place to persist a choice across restarts. Defaulting to
/// [ThemeMode.system] and holding the choice in a provider is honest about
/// that -- the picker sheet does not claim to remember anything past the
/// current session, and nothing in the UI says otherwise.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
