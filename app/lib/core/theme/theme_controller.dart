import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The rider's light / dark choice.
///
/// Stored on the device, not on the account: it has to be known before the
/// first frame, long before a signed-in request could answer, and it should
/// hold on the login screen too. `main` reads it once and hands it in through
/// [initialBrightnessProvider], so the app never opens light and then flips.
///
/// Light is the default. The app does not follow the phone's own setting: the
/// rider picks, with the Dark mode switch in Settings.
const _themeKey = 'hoppin_theme';

/// Reads the saved choice. Never throws: an unreadable store means light.
Future<Brightness> loadSavedBrightness([
  FlutterSecureStorage storage = const FlutterSecureStorage(),
]) async {
  try {
    return await storage.read(key: _themeKey) == 'dark'
        ? Brightness.dark
        : Brightness.light;
  } catch (_) {
    return Brightness.light;
  }
}

/// What the app starts in. Overridden in `main` with the saved choice.
final initialBrightnessProvider =
    Provider<Brightness>((ref) => Brightness.light);

class ThemeController extends Notifier<Brightness> {
  @override
  Brightness build() => ref.watch(initialBrightnessProvider);

  /// Switches the mode now and remembers it. A failed write only costs the
  /// memory of the choice, never the switch itself.
  Future<void> setDark(bool dark) async {
    state = dark ? Brightness.dark : Brightness.light;
    try {
      await const FlutterSecureStorage()
          .write(key: _themeKey, value: dark ? 'dark' : 'light');
    } catch (_) {}
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, Brightness>(ThemeController.new);
