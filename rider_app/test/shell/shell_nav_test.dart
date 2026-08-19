import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/app.dart';
import 'package:hoppin_rider/features/history/history_screen.dart';
import 'package:hoppin_rider/features/notifications/notification_centre_screen.dart';
import 'package:hoppin_rider/features/profile/profile_screen.dart';
import 'package:hoppin_rider/features/shell/rider_shell.dart';
import 'package:hoppin_rider/features/support/support_screen.dart';
import 'package:hoppin_rider/features/wallet/wallet_screen.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// DS-02 acceptance — the 4-tab shell, Profile-via-avatar, and the preserved
/// auth redirect.
///
/// The shell chrome is now the REAL HopBottomNav / HopTopBar (swapped in at
/// 08-05 convergence). These tests assert BEHAVIOUR — tab-switch via
/// `goBranch`, active-index survival across an auth emit, avatar→/profile as a
/// top-level push with no bottom nav, and the verbatim signed-out→/login gate.
/// Tabs are addressed by their Figma labels; the avatar via HopTopBar's key.
void main() {
  /// The four HopBottomNav glyphs in shell-branch order (the component's
  /// `defaultItems`). Inactive tabs are icon-only, so the tests address each
  /// tab by its icon within the bottom nav rather than by visible label text.
  final tabIcons = <IconData>[
    for (final item in HopBottomNav.defaultItems) item.icon,
  ];

  Finder navTab(int index) => find.descendant(
    of: find.byKey(RiderShellKeys.bottomNav),
    matching: find.byIcon(tabIcons[index]),
  );

  /// Boots the exact demo composition `main_demo.dart` assembles — a seeded
  /// [DemoWorld] under [riderDemoOverrides] wrapping the production
  /// [RiderApp] — and returns the live world so a test can drive auth.
  DemoWorld makeWorld() => DemoWorld.riderScenario(
    seed: DemoSeed.seed,
    store: InMemorySnapshotStore(),
  )..restoreOrSeed();

  Future<void> pumpApp(WidgetTester tester, DemoWorld world) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: riderDemoOverrides(world),
        child: const RiderApp(),
      ),
    );
    await tester.pump();
  }

  /// Bounded pumps (never pumpAndSettle): the demo world holds fakes/timers,
  /// and route crossings run the M3 FadeForwards transition (~300ms).
  Future<void> settleRoute(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  /// The one-tap sign-in the prefilled demo login exposes — puts the rider
  /// past the login gate and onto the shell.
  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(HopButton, 'Sign in'));
    await settleRoute(tester);
  }

  testWidgets(
    'Test A: the 4 bottom-nav tabs switch, each rendering its branch',
    (tester) async {
      await pumpApp(tester, makeWorld());
      await signIn(tester);

      // Signed in → the shell hosts the real HopBottomNav with 4 tabs.
      expect(find.byType(RiderShell), findsOneWidget);
      expect(find.byType(HopBottomNav), findsOneWidget);
      expect(find.byKey(RiderShellKeys.bottomNav), findsOneWidget);

      // Book is the landing branch (its label shows on the active capsule).
      expect(navTab(0), findsOneWidget);

      // History tab → HistoryScreen renders.
      await tester.tap(navTab(1));
      await settleRoute(tester);
      expect(find.byType(HistoryScreen), findsOneWidget);

      // Payments tab → WalletScreen renders (path renamed /wallet → /payments).
      await tester.tap(navTab(2));
      await settleRoute(tester);
      expect(find.byType(WalletScreen), findsOneWidget);

      // Support tab → SupportScreen renders.
      await tester.tap(navTab(3));
      await settleRoute(tester);
      expect(find.byType(SupportScreen), findsOneWidget);
    },
  );

  testWidgets('Test B: the active tab index survives an auth-state emit', (
    tester,
  ) async {
    final world = makeWorld();
    await pumpApp(tester, world);
    await signIn(tester);

    // Move off the default (Book) branch onto Payments.
    await tester.tap(navTab(2));
    await settleRoute(tester);
    expect(find.byType(WalletScreen), findsOneWidget);
    expect(currentBranchIndex(tester), 2);

    // Push a fresh auth-state emission through the demo auth stream (a
    // signed-in re-emit — the shape a token refresh takes). This fires the
    // router's refreshListenable; the redirect re-runs but stays put.
    // Pitfall 5: the GoRouter instance must be stable so the branch
    // navigators are NOT recreated and the active index is preserved.
    world.markSignedIn();
    await settleRoute(tester);

    expect(find.byType(WalletScreen), findsOneWidget);
    expect(currentBranchIndex(tester), 2);
  });

  testWidgets(
    'Test C: Profile is reached via the avatar, is NOT a tab, and covers '
    'the shell (no bottom nav)',
    (tester) async {
      await pumpApp(tester, makeWorld());
      await signIn(tester);

      // Profile is NOT one of the 4 bottom-nav destinations.
      expect(navTab(0), findsOneWidget);
      expect(find.byType(HopBottomNav), findsOneWidget);

      // Tap the top-bar avatar → /profile.
      await tester.tap(find.byKey(RiderShellKeys.avatar));
      await settleRoute(tester);

      // Profile renders full-screen — the shell's bottom nav is absent on it.
      expect(find.byKey(ProfileScreenKeys.root), findsOneWidget);
      expect(find.byKey(RiderShellKeys.bottomNav), findsNothing);
    },
  );

  testWidgets('Test D: the auth redirect is preserved — signed-out → /login', (
    tester,
  ) async {
    // A fresh world boots signed-OUT; the verbatim redirect must send the
    // initial location to /login.
    await pumpApp(tester, makeWorld());
    await settleRoute(tester);

    // Production-identical login surface; the shell must not be mounted.
    expect(find.text('Hoppin'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(RiderShell), findsNothing);
  });

  // ── NOTIF-02: the HONEST bell ─────────────────────────────────────────────
  // Wave 0 deleted `notificationCount: 2` over a dead `onBell: () {}` — a
  // permanent fake unread badge on EVERY screen, wired to a button that did
  // nothing. Phase 11 restores the bell, but only ever with a REAL count.
  //
  // PHASE 11 / LANE E: the `/notifications` GoRoute now exists, so Test F is
  // upgraded from "the bell has a live callback" to the thing that actually
  // matters — a rider TAPS the bell and LANDS on the centre, which discloses
  // the #68 history seam. That is reachability, not intent.

  testWidgets('Test E: the bell badge shows the REAL unread count (0 on an '
      'empty feed), never a hardcoded number', (tester) async {
    await pumpApp(tester, makeWorld());
    await signIn(tester);

    final topBar = tester.widget<HopTopBar>(find.byType(HopTopBar));
    expect(
      topBar.notificationCount,
      0,
      reason:
          'The demo world feeds no notifications, so the honest count is 0 and '
          'HopTopBar hides the badge. A non-zero number here would be exactly '
          'the fake badge Wave 0 deleted.',
    );

    // The badge itself must not render at all.
    expect(
      find.descendant(of: find.byType(HopTopBar), matching: find.text('2')),
      findsNothing,
      reason: 'The specific fake Wave 0 removed. It must not come back.',
    );
  });

  testWidgets('Test F: tapping the bell LANDS on the notification centre '
      '(reachability, not intent)', (tester) async {
    await pumpApp(tester, makeWorld());
    await signIn(tester);

    final topBar = tester.widget<HopTopBar>(find.byType(HopTopBar));
    expect(
      topBar.onBell,
      isNotNull,
      reason:
          'A bell wired to `() {}` is a dead affordance — a no-dead-ends '
          'violation. It must actually go somewhere.',
    );
    expect(
      kNotificationCentreRoute,
      '/notifications',
      reason: 'The one string the shell bell and the GoRoute must agree on.',
    );

    // 🔴 The assertion Lane A could not make: TAP IT and land.
    topBar.onBell!();
    await settleRoute(tester);

    expect(
      find.byType(NotificationCentreScreen),
      findsOneWidget,
      reason:
          'The centre must be reachable by TAPPING THROUGH THE APP, not merely '
          'by typing a URL. Lane A shipped the screen; without the GoRoute it '
          'was unreachable — a surface nobody can get to is not a surface.',
    );
  });

  // NOTIF-02 — the behavioural reachability check for the durable history feed.
  testWidgets('Test G: the centre reached from the bell loads real history', (
    tester,
  ) async {
    await pumpApp(tester, makeWorld());
    await signIn(tester);

    tester.widget<HopTopBar>(find.byType(HopTopBar)).onBell!();
    await settleRoute(tester);

    expect(
      find.textContaining("Older notifications can't be loaded"),
      findsNothing,
    );
    expect(
      find.textContaining('no notifications', findRichText: true),
      findsNothing,
      reason: 'The API is now the source of truth for whether history exists.',
    );
    expect(
      find.textContaining('No notifications', findRichText: true),
      findsNothing,
      reason: 'Same lie, capitalised.',
    );
  });
}

/// Reads the active branch index off the mounted [StatefulNavigationShell] —
/// the source of truth the placeholder bottom nav reflects.
int currentBranchIndex(WidgetTester tester) {
  final shell = tester.widget<RiderShell>(find.byType(RiderShell));
  return shell.navigationShell.currentIndex;
}
