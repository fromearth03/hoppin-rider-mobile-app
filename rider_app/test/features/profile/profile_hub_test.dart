import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/app.dart';
import 'package:hoppin_rider/features/legal/privacy_notice_screen.dart';
import 'package:hoppin_rider/features/legal/terms_screen.dart';
import 'package:hoppin_rider/features/profile/personal/personal_info_screen.dart';
import 'package:hoppin_rider/features/profile/profile_screen.dart';
import 'package:hoppin_rider/features/promotions/promotions_screen.dart';
import 'package:hoppin_rider/features/settings/settings_screen.dart';
import 'package:hoppin_rider/features/support/help/help_support_screen.dart';
import 'package:hoppin_rider/features/support/support_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/recording_support_repository.dart';

/// ACCT-01 — the Profile hub finally reaches real screens, through the REAL
/// router.
///
/// These tests boot `riderRouterProvider` itself rather than a hand-built
/// stand-in. That matters: the thing under test IS the route table and the
/// signed-out allowlist. A test that builds its own little router proves its own
/// little router works.
///
/// Three defects are pinned here, in ascending order of how long they hid:
///
/// 1. **Three rows opened an apology sheet** instead of a screen (Wave 0's
///    honest interim for `onTap: null`). The screens now exist.
/// 2. 🔴 **"Help & Support" went to the WRONG SCREEN** — `/support`, the ticket
///    tab — for the app's entire life. The frame the hub promises (Figma #38) is
///    FAQ + Contact + Legal, with no tickets on it, and it had **never been
///    built**. Nobody noticed **because the row LOOKED wired**: it navigated, so
///    it read as done. A row that goes to the wrong place hides better than a row
///    that goes nowhere.
/// 3. The hub card fell back to `onTap: ... ?? () {}` — a full tap ripple over a
///    silent no-op. The type is now non-nullable, so a future dead row will not
///    compile.
void main() {
  /// A signed-in session, so the router's redirect lets us onto `/profile/*`.
  /// The tests below that check the BOUNCE use [_SignedOut] instead — both
  /// directions matter, and a test that only proves the gate lets people IN
  /// would also pass on a router with no gate at all.
  final signedIn = _FakeAuthService(signedIn: true);
  final signedOut = _FakeAuthService(signedIn: false);

  Widget harness(AuthService auth, RecordingSupportRepository support) {
    return ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        supportRepositoryProvider.overrideWithValue(support),
      ],
      child: const RiderApp(),
    );
  }

  /// Bounded settle — never `pumpAndSettle` (project convention). Route changes
  /// need a few frames to build the destination.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  /// Boot the app, navigate to the hub, and hand back the recorder.
  Future<RecordingSupportRepository> bootHub(WidgetTester tester) async {
    final support = RecordingSupportRepository();
    await tester.pumpWidget(harness(signedIn, support));
    await settle(tester);

    final router = tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .context;
    // Drive the hub the way the rider does: through the router, not by pumping
    // the widget directly.
    GoRouterHelper(router).go('/profile');
    await settle(tester);

    expect(find.byKey(ProfileScreenKeys.root), findsOneWidget,
        reason: 'the Profile hub must be reachable at /profile');
    return support;
  }

  /// Tap a hub row by its visible label and settle the route change.
  Future<void> tapRow(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  group('ACCT-01 — every hub row reaches a REAL screen', () {
    testWidgets('Personal Information lands on the ACCT-02 screen',
        (tester) async {
      await bootHub(tester);
      await tapRow(tester, 'Personal Information');

      expect(find.byType(PersonalInfoScreen), findsOneWidget,
          reason: 'the row must reach the real screen — it used to open an '
              'apology sheet, because the screen did not exist');
    });

    testWidgets('Promotions lands on the ACCT-04 screen', (tester) async {
      await bootHub(tester);
      await tapRow(tester, 'Promotions');

      expect(find.byType(PromotionsScreen), findsOneWidget,
          reason: 'the row must reach the real promotions centre');
    });

    testWidgets('Settings lands on the ACCT-03 screen', (tester) async {
      await bootHub(tester);
      await tapRow(tester, 'Settings');

      expect(find.byType(SettingsScreen), findsOneWidget,
          reason: 'the row must reach the real settings screen');
    });

    testWidgets(
        '🔴 Help & Support lands on the FAQ/contact/legal screen — NOT the '
        'ticket tab it wrongly pointed at for the whole project', (tester) async {
      await bootHub(tester);
      await tapRow(tester, 'Help & Support');

      expect(find.byType(HelpSupportScreen), findsOneWidget,
          reason: 'the hub promises Figma #38 (FAQ + Contact + Legal). This '
              'screen had NEVER been built, and nobody noticed, because the row '
              'navigated somewhere — just somewhere WRONG.');
      expect(find.byType(SupportScreen), findsNothing,
          reason: 'the ticket TAB is a different screen with a different job. '
              'Sending the rider there when they asked for help is the defect, '
              'and it is the one that hid the missing screen.');
    });
  });

  group('the signed-out gate — /profile/* is authenticated, /legal/* is not',
      () {
    testWidgets('a signed-out rider is bounced from /profile/settings to /login',
        (tester) async {
      await tester.pumpWidget(harness(signedOut, RecordingSupportRepository()));
      await settle(tester);

      final context = tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .context;
      GoRouterHelper(context).go('/profile/settings');
      await settle(tester);

      expect(find.byType(SettingsScreen), findsNothing,
          reason: 'Settings is an AUTHENTICATED surface — a signed-out visit '
              'must not render it. Phase 12 added four new /profile/* routes and '
              'none of them may leak into the signed-out allowlist.');
    });

    testWidgets(
        '🔴 the privacy notice IS readable signed-out — the consent notice '
        'links to it FROM SIGNUP, before the account exists', (tester) async {
      await tester.pumpWidget(harness(signedOut, RecordingSupportRepository()));
      await settle(tester);

      final context = tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .context;
      GoRouterHelper(context).go('/legal/privacy');
      await settle(tester);

      expect(find.byType(PrivacyNoticeScreen), findsOneWidget,
          reason: 'Art. 13 owes transparency AT THE POINT OF COLLECTION, and '
              'signup IS that point. A privacy link that bounces the very person '
              'being asked to trust it to a login wall is the exact defect this '
              'phase exists to kill. Owner ruling, 2026-07-13. It is static '
              'bundled content: no personal data, no endpoint, nothing to leak.');
    });

    testWidgets('the terms are readable signed-out too', (tester) async {
      await tester.pumpWidget(harness(signedOut, RecordingSupportRepository()));
      await settle(tester);

      final context = tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .context;
      GoRouterHelper(context).go('/legal/terms');
      await settle(tester);

      expect(find.byType(TermsScreen), findsOneWidget,
          reason: 'same reasoning as the privacy notice — the signup screen '
              'links to both');
    });
  });

  group('the interim apology sheet is GONE', () {
    test('no lib/ source still references the Phase-12 placeholder helper', () {
      // A source assertion, not a widget one: the helper could survive as dead
      // code with no call site, and dead code that apologises for a screen that
      // now exists is a lie waiting to be re-mounted.
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (file.readAsStringSync().contains('_showComingInPhase12')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'the "coming in Phase 12" sheet was the honest interim for '
              'three rows with no screen. The screens exist now. Its own doc '
              'comment said this phase deletes it:\n  ${offenders.join('\n  ')}');
    });

    testWidgets('no hub row opens a sheet instead of navigating',
        (tester) async {
      await bootHub(tester);

      for (final label in const [
        'Personal Information',
        'Promotions',
        'Settings',
        'Help & Support',
      ]) {
        await tester.tap(find.text(label));
        await settle(tester);
        expect(find.byType(BottomSheet), findsNothing,
            reason: '"$label" must navigate to a screen, not apologise in a '
                'sheet');
        // Back to the hub for the next row.
        final context = tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .context;
        GoRouterHelper(context).go('/profile');
        await settle(tester);
      }
    });
  });

  testWidgets('the hub itself writes NOTHING — no row opens a ticket',
      (tester) async {
    final support = await bootHub(tester);

    for (final label in const [
      'Personal Information',
      'My Trips',
      'Promotions',
      'Help & Support',
      'Settings',
    ]) {
      if (find.text(label).evaluate().isEmpty) continue;
      await tester.tap(find.text(label));
      await settle(tester);
      final context =
          tester.state<NavigatorState>(find.byType(Navigator).first).context;
      GoRouterHelper(context).go('/profile');
      await settle(tester);
    }

    expect(support.createdTickets, isEmpty,
        reason: 'ONLY the deletion/export popup may write. Navigating the hub '
            'must never open a support ticket.');
  });
}

/// A minimal signed-in / signed-out [AuthService] for the router redirect.
///
/// The router watches `isSignedIn` and `onAuthStateChange`; nothing else on the
/// hub path touches the service except `fullName`/`email` (the identity block)
/// and `signOut` (the last row).
class _FakeAuthService implements AuthService {
  _FakeAuthService({required bool signedIn}) : _signedIn = signedIn;

  final bool _signedIn;

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get fullName => 'Sam Rider';

  @override
  String? get email => 'sam@hoppin.uk';

  @override
  String? get phone => null;

  @override
  DateTime? get createdAt => DateTime.utc(2025, 8, 14);

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Session? get currentSession => null;

  @override
  String? get accessToken => _signedIn ? 'test-token' : null;

  @override
  String? get userId => _signedIn ? 'rider-1' : null;

  @override
  AppRole get role => AppRole.rider;

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthResponse> signUpRider({
    required String email,
    required String password,
    String? fullName,
  }) =>
      throw UnimplementedError();

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signInWithOtp({required String phone}) =>
      throw UnimplementedError();

  @override
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> refreshSession() async {}
}
