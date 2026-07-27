import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_demo/hoppin_demo.dart';

import 'app.dart';
import 'features/location/location_providers.dart';
import 'features/notifications/fake_fcm_gateway.dart';
import 'features/notifications/fcm_gateway.dart';

/// Demo entry point for the Hoppin RIDER app (DEMO-01).
///
/// Boots the full production shell on ZERO backend: no env asserts, no
/// backend client boot, no dart-defines, no network. The demo world seeds
/// deterministically and every repository is a fake driven by [DemoWorld].
///
/// Run:   flutter run -d chrome -t lib/main_demo.dart
/// Build: flutter build web -t lib/main_demo.dart
///
/// Reset (DEMO-06): reload with the query param BEFORE the hash —
///   http://host:PORT/?demo_reset=1#/
/// — which clears the session snapshot so boot lands on the fresh seed.
/// A plain F5 (no param) resumes exactly where the demo was. Phase 6 moves
/// reset into the control drawer via `world.reset()`.
///
/// Theme (DESIGN-02): `?theme=dark` / `?theme=light` forces the window's
/// ThemeMode — the D2 stage picture runs rider LIGHT beside driver DARK on
/// one machine. Absent param = follow the platform, same as live.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = SnapshotStore.forPlatform();
  if (Uri.base.queryParameters.containsKey('demo_reset')) {
    // Explicit reset beat: the presenter reloads with ?demo_reset=1.
    store.clear();
  }

  // Provider-level theme seam: parsed once before runApp, forced value
  // arrives as a root override. Views never branch on demo mode.
  final forcedTheme = switch (Uri.base.queryParameters['theme']) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => null,
  };

  final world = DemoWorld.riderScenario(seed: DemoSeed.seed, store: store)
    ..restoreOrSeed();

  // Same shell as live main.dart — only the overrides differ.
  //
  // ⚠️ These extra overrides go HERE, never into `riderDemoOverrides` —
  // `hoppin_demo` cannot import the rider app (the dependency direction is
  // app → package), and `overrides_test.dart` asserts that list's exact length.
  //
  // ⚠️ Riverpod double-override: `riderDemoOverrides` already holds
  // `profileRepositoryProvider` and `ridesRepositoryProvider`. Never re-override
  // either below. `fcmGatewayProvider` is NOT in it, so it is safe.
  runApp(ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      ...riderDemoOverrides(world),

      // The demo NEVER touches Firebase — this is a pure-Dart scripted stream,
      // not an SDK. It exists so the presenter's notification centre is not
      // empty on stage. The LIVE default stays the no-op.
      fcmGatewayProvider.overrideWithValue(FakeFcmGateway.scripted()),

      // The demo SOS carries plausible GPS without touching the geolocation
      // plugin. The LIVE default stays the real Geolocator-backed service.
      locationServiceProvider.overrideWithValue(const FakeLocationService()),

      // themeModeProvider became writable in Phase 12 (the Settings theme
      // toggle must move real state), so the demo pins it by composing the
      // seeded controller rather than by overriding a constant value.
      if (forcedTheme != null)
        themeModeProvider.overrideWith(
          () => ThemeModeController.forced(forcedTheme),
        ),
    ],
    child: const RiderApp(),
  ));
}
