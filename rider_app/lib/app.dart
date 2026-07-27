import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/launch/launch_gate.dart';
import 'router.dart';
import 'theme.dart';

/// Theme mode of the app shell.
///
/// Was a `Provider<ThemeMode>` returning a constant — nothing could change it.
/// Phase 12 (ACCT-03) promotes it to a writable [NotifierProvider], because the
/// Settings screen's theme toggle is the ONE genuinely working control on that
/// screen and it must move REAL state.
///
/// (Riverpod 3 removed `StateProvider`; [Notifier] with a seeded named
/// constructor is this codebase's established idiom for session state — cf.
/// `NotificationFeed.seeded`.)
///
/// Session-scoped ON PURPOSE: the repo carries zero persistence packages, and
/// caching the choice to disk would be exactly the false-persistence signal the
/// owner ruled out. The theme resets when the app reopens, and the settings rung
/// (gap 71) says so plainly.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// The session store behind [themeModeProvider].
///
/// Live builds follow the platform until the rider chooses. The demo entrypoint
/// composes [ThemeModeController.forced] at the root ProviderScope when a
/// `?theme=` query param pins a mode for the two-window stage picture — a
/// provider-level seam, same pattern as `loginPrefillProvider`. Views never
/// branch on demo mode.
class ThemeModeController extends Notifier<ThemeMode> {
  /// The live controller — follows the platform until the rider says otherwise.
  ThemeModeController() : _forced = null;

  /// A pinned controller. DEMO composition only.
  ThemeModeController.forced(ThemeMode mode) : _forced = mode;

  final ThemeMode? _forced;

  @override
  ThemeMode build() => _forced ?? ThemeMode.system;

  /// The rider's explicit choice from Settings. An explicit light choice is
  /// [ThemeMode.light], not a fall back to [ThemeMode.system] — once they have
  /// chosen, the platform no longer decides for them.
  void set(ThemeMode mode) => state = mode;
}

/// The root widget for the rider app. Wires the go_router instance and theme.
class RiderApp extends ConsumerWidget {
  const RiderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(riderRouterProvider);
    return MaterialApp.router(
      title: 'Hoppin',
      debugShowCheckedModeBanner: false,
      theme: hoppinLightTheme,
      darkTheme: hoppinDarkTheme,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      // The launch gate wraps EVERY route (including login): the operator's
      // maintenance / force-update block, resolved from GET /app-status. Fails
      // open — a failed check leaves the app fully usable.
      builder: (context, child) =>
          LaunchGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
