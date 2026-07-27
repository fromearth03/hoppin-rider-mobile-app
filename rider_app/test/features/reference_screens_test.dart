import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/booking/booking_builder.dart';
import 'package:hoppin_rider/features/booking/place.dart';
import 'package:hoppin_rider/features/profile/profile_screen.dart';
import 'package:hoppin_rider/features/shell/rider_shell.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../support/tile_http_fakes.dart';

/// Fidelity-gate reference screens (08-05 convergence).
///
/// Proves the two gate screens — Book Ride (#8) and Profile (#34) — render in
/// BOTH rider themes, are assembled from the REAL hoppin_ui component set (not
/// the 08-03 placeholder chrome), and leak ZERO stock-Material chrome
/// (`AppBar` / `NavigationBar` / `ListTile`) on either surface. This is the
/// automated backstop under the manual fidelity gate.
void main() {
  // The Book Ride band mounts a real HopMap; serve its OSM tiles a 1x1 PNG
  // from memory so no tile HTTP ever hits the network under flutter_test
  // (the isolation gate forbids importing maplibre_gl into apps/rider).
  setUpAll(() => HttpOverrides.global = TileHttpOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  final themes = <String, ThemeData>{
    'riderLight': HoppinTheme.riderLight(),
    'riderDark': HoppinTheme.riderDark(),
  };

  // ── Book Ride (#8) ──────────────────────────────────────────────────────
  group('Book Ride reference screen', () {
    for (final entry in themes.entries) {
      testWidgets('renders from the real component set — ${entry.key}', (
        tester,
      ) async {
        final h = await _bootBook(tester, entry.value);

        // Real hoppin_ui components — the Figma Book composition.
        expect(find.byType(RideTypeCard), findsWidgets);
        expect(find.byType(FareEstimateCard), findsOneWidget);
        expect(find.byType(LocationField), findsOneWidget);
        // The primary CTA is a HopButton, never a stock FilledButton.
        expect(find.byType(HopButton), findsWidgets);

        // Zero stock-Material chrome leaks on the booking surface.
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(ListTile), findsNothing);

        await _dispose(tester, h);
      });
    }
  });

  // ── Shell chrome (real HopTopBar + HopBottomNav) ────────────────────────
  group('Rider shell chrome', () {
    for (final entry in themes.entries) {
      testWidgets('hosts the real HopTopBar + HopBottomNav — ${entry.key}', (
        tester,
      ) async {
        final h = await _bootShell(tester, entry.value);

        expect(find.byType(RiderShell), findsOneWidget);
        expect(find.byType(HopTopBar), findsOneWidget);
        expect(find.byType(HopBottomNav), findsOneWidget);

        // No stock-Material chrome in the persistent shell.
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);

        await _dispose(tester, h);
      });
    }
  });

  // ── Profile (#34) ───────────────────────────────────────────────────────
  group('Profile reference screen', () {
    for (final entry in themes.entries) {
      testWidgets('renders the HopListRow hub — ${entry.key}', (tester) async {
        final h = await _bootProfile(tester, entry.value);

        expect(find.byKey(ProfileScreenKeys.root), findsOneWidget);
        expect(find.byType(HopTopBar), findsOneWidget);
        expect(find.byType(HopListRow), findsWidgets);

        // Zero stock-Material chrome on Profile.
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(ListTile), findsNothing);

        await _dispose(tester, h);
      });
    }
  });
}

class _Harness {
  _Harness(this.world, this.container);
  final DemoWorld world;
  final ProviderContainer container;
}

DemoWorld _makeWorld() => DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();

/// The scripted Wolverhampton demo places (same maths as the seeded world).
const _pickup = Place(
  label: 'Wolverhampton City Centre',
  lat: 52.5870,
  lng: -2.1288,
);
const _dropoff = Place(
  label: 'Wolverhampton Rail Station',
  lat: 52.5877,
  lng: -2.1200,
);

/// Boots the Book Ride view with places seeded so the fare-estimate + map band
/// resolve — the Figma resting composition.
Future<_Harness> _bootBook(WidgetTester tester, ThemeData theme) async {
  final world = _makeWorld();
  final container = ProviderContainer(overrides: riderDemoOverrides(world));
  container.read(bookingInteractorProvider.notifier)
    ..setPickup(_pickup)
    ..setDropoff(_dropoff);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme, home: const BookingFlow()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
  return _Harness(world, container);
}

/// Boots the full shell via a minimal router so HopTopBar + HopBottomNav mount.
Future<_Harness> _bootShell(WidgetTester tester, ThemeData theme) async {
  final world = _makeWorld();
  final container = ProviderContainer(overrides: riderDemoOverrides(world));

  final router = GoRouter(
    initialLocation: '/book',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RiderShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/book', builder: (_, _) => const BookingFlow()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (_, _) => const Scaffold(body: Text('history')),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/payments',
                builder: (_, _) => const Scaffold(body: Text('payments')),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/support',
                builder: (_, _) => const Scaffold(body: Text('support')),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: theme, routerConfig: router),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
  return _Harness(world, container);
}

Future<_Harness> _bootProfile(WidgetTester tester, ThemeData theme) async {
  final world = _makeWorld();
  final container = ProviderContainer(overrides: riderDemoOverrides(world));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme, home: const ProfileScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return _Harness(world, container);
}

Future<void> _dispose(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  h.container.dispose();
  h.world.reset();
}
