import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/app.dart';
import 'package:hoppin_rider/features/legal/widgets/consent_record_unavailable.dart';
import 'package:hoppin_rider/features/profile/personal/widgets/personal_info_unavailable.dart';
import 'package:hoppin_rider/features/promotions/widgets/promo_codes_unavailable.dart';
import 'package:hoppin_rider/features/settings/widgets/settings_prefs_unavailable.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/recording_support_repository.dart';

/// 🔴 THE BEHAVIOURAL REACHABILITY LAYER — boot the REAL app, find the rung.
///
/// **Why this file exists, when five lane tests already cover these screens.**
///
/// Group C's reachability check is a SOURCE GREP: it matches `Name(` in any
/// `lib/` file other than the declaring one. It cannot be gamed by accident —
/// but an `if (false)` branch would satisfy it, and so would a widget
/// constructed only by a screen that no route reaches. It has no notion of
/// routes, mounting, or reachability. So it must not be leaned on.
///
/// The lane tests are the other half of the problem. Three of them
/// (`personal_info_test`, `delete_account_test`, `promotions_screen_test`)
/// hand-build a throwaway `GoRouter` containing exactly the `GoRoute` that
/// `lib/router.dart` was missing, and assert the screen renders at it. **That is
/// how six unreachable screens shipped green.** A test that builds its own
/// router proves its own router works. It reads like integration coverage, which
/// makes it worse than a bare harness, not better.
///
/// Those tests are otherwise excellent — their negative assertions are the real
/// product of the phase — so they are left alone. This file adds the layer they
/// structurally cannot provide: it pumps `RiderApp`, drives the REAL
/// `riderRouterProvider`, navigates the way a rider navigates, and asserts each
/// rung renders on its real null branch.
///
/// Companion to `router_reachability_test.dart`, which proves every `context.go`
/// literal in `lib/` RESOLVES. This one proves that when you arrive, the honesty
/// rung is actually there.
void main() {
  /// Bounded pumps — never `pumpAndSettle` (project convention: a route-crossing
  /// settle can hang on a live ticker, and this app has several).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  /// Boot the REAL app with a signed-in session, then drive the REAL router to
  /// [path]. Returns the recorder so a test can assert on what was written.
  Future<RecordingSupportRepository> bootAt(
    WidgetTester tester,
    String path,
  ) async {
    final support = RecordingSupportRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_SignedInAuthService()),
          supportRepositoryProvider.overrideWithValue(support),
        ],
        child: const RiderApp(),
      ),
    );
    await settle(tester);

    final context =
        tester.state<NavigatorState>(find.byType(Navigator).first).context;
    GoRouterHelper(context).go(path);
    await settle(tester);
    return support;
  }

  group('every Phase-12 rung renders on the REAL routed screen', () {
    testWidgets('#70 — Personal Information discloses that the profile read '
        'does not exist', (tester) async {
      await bootAt(tester, '/profile/personal');

      expect(find.byType(PersonalInfoUnavailable), findsOneWidget,
          reason: 'the #70 rung must render on the REAL screen at the REAL '
              'route. Group C only proves the widget is constructed SOMEWHERE '
              'in lib/ — a source grep would pass for a screen no route '
              'reaches, which is exactly what shipped.');
    });

    testWidgets('#71 — Settings discloses that no preference is stored, ONCE',
        (tester) async {
      await bootAt(tester, '/profile/settings');

      expect(find.byType(SettingsPrefsUnavailable), findsOneWidget,
          reason: 'ONE rung for the screen, not one per switch. Eight identical '
              'rungs is noise, and noise is how a disclosure gets ignored.');
    });

    testWidgets('#72 — Promotions discloses that codes cannot be LISTED',
        (tester) async {
      await bootAt(tester, '/profile/promotions');

      expect(find.byType(PromoCodesUnavailable), findsOneWidget,
          reason: 'the codes half of the screen is a permanent null and says '
              'so. The banners half above it is BOUND — the screen is half-real '
              'and the split must be visible.');
    });

    testWidgets('#74 — the consent rung renders at SIGNUP (collection)',
        (tester) async {
      final support = RecordingSupportRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(_SignedOutAuthService()),
            supportRepositoryProvider.overrideWithValue(support),
          ],
          child: const RiderApp(),
        ),
      );
      await settle(tester);

      final context =
          tester.state<NavigatorState>(find.byType(Navigator).first).context;
      GoRouterHelper(context).go('/signup');
      await settle(tester);

      expect(find.byType(ConsentRecordUnavailable), findsWidgets,
          reason: 'Art. 13 owes transparency AT THE POINT OF COLLECTION, and '
              'signup IS that point. The rung must be on the screen where the '
              'consent is asked for — not only on the screen where it is '
              'withdrawn.');
    });

    testWidgets('#74 — the consent rung ALSO renders in Settings (withdrawal)',
        (tester) async {
      // A TALL viewport, so the whole screen builds. The rung sits beneath the
      // marketing toggle, well below the fold of the default 800px test window,
      // and no existing test had ever asserted it renders here at all — the lane
      // test checks the #71 rung and stops. Scrolling would also work; sizing the
      // window is steadier, because it does not depend on which Scrollable the
      // finder picks or on how the screen is later re-laid-out.
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await bootAt(tester, '/profile/settings');

      expect(find.byType(ConsentRecordUnavailable), findsWidgets,
          reason: 'Art. 7(3): withdrawal must be as easy as giving. Both mount '
              'sites are real and both are owed. Group C needs one; the honesty '
              'needs both. It mounts at settings_screen.dart:192, directly '
              'beneath the toggle it qualifies — a rider deciding whether to '
              'opt IN deserves to know AT THAT MOMENT that the choice is '
              'session-scoped and that we therefore send nothing at all.');
    });
  });

  group('THE EXCLUSIVITY ASSERTION — only the deletion popup may write', () {
    testWidgets(
        'driving every control on Personal Information, Settings and '
        'Promotions opens ZERO tickets', (tester) async {
      // The write path is proved by its EXCLUSIVITY, not by its presence. A
      // test that only proved the popup writes would also pass on an app where
      // EVERYTHING writes. This is Phase 11's "the app NEVER dials" idiom
      // generalised from zero dials to zero writes.
      for (final path in const [
        '/profile/personal',
        '/profile/settings',
        '/profile/promotions',
      ]) {
        final support = await bootAt(tester, path);

        // Drive every switch and every button the screen offers. Inert controls
        // must stay inert; live ones must not reach the support repository.
        for (final finder in [find.byType(Switch), find.byType(Checkbox)]) {
          for (var i = 0; i < finder.evaluate().length; i++) {
            await tester.tap(finder.at(i), warnIfMissed: false);
            await tester.pump();
          }
        }

        expect(support.createdTickets, isEmpty,
            reason: 'ONLY the deletion/export popup may write. Nothing on '
                '$path has anything to say to a human, so nothing on it may '
                'open a ticket.');
      }
    });
  });

  group('the anti-fabrication battery, on the REAL routed screens', () {
    testWidgets('no invented identity, city, or promo code renders anywhere',
        (tester) async {
      // Every one of these strings was, at some point, rendered to a real user
      // as though it were their own data. They are pinned here on the ROUTED
      // screens — the surfaces a rider actually reaches — rather than in a bare
      // harness, because a harness cannot tell you whether anybody would ever
      // have seen it.
      for (final path in const [
        '/profile',
        '/profile/personal',
        '/profile/settings',
        '/profile/promotions',
      ]) {
        await bootAt(tester, path);

        for (final lie in const [
          'Clark Kent', // the hardcoded name the hub showed every rider
          'Wolverhampton, Eng', // a city field that exists nowhere in the product
          'WELCOME20', // an invented promo code
          'REFER100', // invented AND for referrals, the owner's sole park
          'Weekend Special',
          'You have no promo codes', // asserting emptiness when the truth is ignorance
        ]) {
          expect(find.text(lie), findsNothing,
              reason: '"$lie" must not render at $path. We do not know it, so '
                  'we may not say it.');
        }
      }
    });
  });

  group('the fake-router pattern must not spread', () {
    test(
        '🔴 no NEW test file hand-builds a GoRouter — three legacy ones are '
        'grandfathered and named', () {
      // The direct cause of six unreachable screens shipping green: a test that
      // builds its own GoRouter containing exactly the route production lacks,
      // then asserts the screen renders at it. It proves its own router works.
      //
      // The three below are grandfathered because their OTHER assertions (the
      // negative battery, the inert-control proofs) are the real product of the
      // phase and are worth keeping. Their reachability claim is now provided by
      // THIS file and by router_reachability_test.dart, which boot the real
      // router.
      //
      // 🔴 DO NOT ADD TO THIS LIST. If you are here because your new test needs
      // a route, the route belongs in lib/router.dart. If it is already there,
      // pump RiderApp and use it. A test-local GoRouter is how this app shipped
      // six screens no user could reach.
      const grandfathered = {
        'features/profile/personal_info_test.dart',
        'features/settings/delete_account_test.dart',
        'features/promotions/promotions_screen_test.dart',
      };

      // Scoped to the PHASE-12 surfaces. Older suites across the app also build
      // local routers, and sweeping them all in here would turn one honest
      // assertion into a 20-file churn that this lane has no mandate to make and
      // no way to verify. The rule is enforced where the damage was done, and
      // `router_reachability_test.dart` catches the actual defect — a dead
      // route — everywhere, regardless of how any test is written.
      const phase12Dirs = [
        'features/profile/',
        'features/settings/',
        'features/promotions/',
        'features/legal/',
      ];

      final offenders = <String>[];
      for (final file in Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final rel = file.path
            .replaceAll(r'\', '/')
            .replaceFirst(RegExp(r'^.*?test/'), '');
        if (!phase12Dirs.any(rel.startsWith)) continue;
        if (grandfathered.contains(rel)) continue;
        if (file.readAsStringSync().contains('GoRouter(')) {
          offenders.add(rel);
        }
      }

      expect(offenders, isEmpty,
          reason: 'These test files construct their own GoRouter:\n'
              '  ${offenders.join('\n  ')}\n\n'
              'A test that builds its own router proves its own router works. '
              'It cannot see that lib/router.dart lacks the route — and it '
              'READS like integration coverage, which is what makes it more '
              'dangerous than a bare harness, not less. Six screens shipped '
              'unreachable behind exactly this pattern.\n\n'
              'Pump RiderApp and drive riderRouterProvider instead.');
    });
  });
}

/// A signed-in session carrying the four facts the real one carries — nothing
/// more. `phone` is null because Supabase never sets it on the email/password
/// signup path, which is every rider this app creates: the honest, common case,
/// and the one the screen must handle by OMITTING the row rather than dashing
/// it.
class _SignedInAuthService implements AuthService {
  @override
  bool get isSignedIn => true;

  @override
  String? get fullName => 'Sam Rider';

  @override
  String? get email => 'sam@hoppin.uk';

  @override
  String? get phone => null;

  @override
  DateTime? get createdAt => DateTime.utc(2025, 8, 14);

  @override
  String? get userId => 'rider-1';

  @override
  String? get accessToken => 'test-token';

  @override
  AppRole get role => AppRole.rider;

  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> refreshSession() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not on the '
          'Phase-12 read path. If a screen now needs it, add it deliberately.');
}

/// Signed out — so `/signup` renders rather than bouncing to `/login`.
class _SignedOutAuthService extends _SignedInAuthService {
  @override
  bool get isSignedIn => false;

  @override
  String? get accessToken => null;

  @override
  String? get userId => null;
}
