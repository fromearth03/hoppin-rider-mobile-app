import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/auth/signup_eligibility_notice.dart';
import 'package:hoppin_rider/features/auth/signup_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'support/recording_auth_service.dart';

/// AUTH-01 — registration with name + email/phone + password + an 18+
/// declaration. Unchecked 18+ blocks submit; 18+/DOB are cached client-side
/// (persistence is the SL-5 MISSING-BE seam, registered in 09-05).
void main() {
  final light = HoppinTheme.riderLight();

  Widget harness(RecordingAuthService auth) => ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(theme: light, home: const SignupScreen()),
      );

  testWidgets('renders name, email, password, DOB fields + an 18+ checkbox',
      (tester) async {
    await tester.pumpWidget(harness(RecordingAuthService()));

    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // DOB field present (AUTH-01 eligibility, gap #55).
    expect(find.text('Date of birth'), findsOneWidget);
    // The 18+ declaration.
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.textContaining('18'), findsWidgets);
  });

  testWidgets('submit is DISABLED until the 18+ box is checked',
      (tester) async {
    final auth = RecordingAuthService();
    await tester.pumpWidget(harness(auth));

    // Fill the required fields so only the 18+ gate blocks submit.
    await tester.enterText(
        find.byKey(const Key('signup_name')), 'Sam Rider');
    await tester.enterText(
        find.byKey(const Key('signup_email')), 'sam@hoppin.uk');
    await tester.enterText(
        find.byKey(const Key('signup_password')), 'hunter2hunter');
    await tester.pump();

    // Tapping submit while 18+ is unchecked does NOT call the service.
    await tester.ensureVisible(find.byKey(const Key('signup_submit')));
    await tester.tap(find.byKey(const Key('signup_submit')));
    await tester.pump();
    expect(auth.signUpCalls, isEmpty,
        reason: 'unchecked 18+ must block submit');

    // Check 18+ → submit now fires.
    //
    // `ensureVisible` FIRST. The line above scrolled the form down to reach the
    // submit button, which pushed the 18+ box off the top of the viewport — and
    // Phase 12's consent block (notice + marketing toggle) made the form taller
    // still, so the gap between the two controls no longer fits on one screen.
    // Without this, `tap` derives an off-screen offset, silently misses, and the
    // test fails claiming the 18+ gate is broken when the gate is fine.
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('signup_submit')));
    await tester.tap(find.byKey(const Key('signup_submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(auth.signUpCalls, hasLength(1));
    expect(auth.signUpCalls.single.email, 'sam@hoppin.uk');
    expect(auth.signUpCalls.single.fullName, 'Sam Rider');
  });

  // ── SL-5 / #55: the 18+ eligibility disclosure is REACHABLE ──────────────
  //
  // The declaration is captured client-side and there is no rider-profile
  // PATCH to persist it. The registry + SCOPE-TRACE both claim it is
  // "disclosed via signup_eligibility_notice.dart" — these pin that the REAL
  // signup screen actually mounts that notice on its real branch, rather than
  // the widget merely existing.
  group('SL-5 (#55): the on-device eligibility disclosure is mounted', () {
    testWidgets(
        'NOT shown before the rider declares 18+ — nothing to disclose yet',
        (tester) async {
      await tester.pumpWidget(harness(RecordingAuthService()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SignupEligibilityNotice), findsNothing,
          reason: 'the disclosure must not pre-empt the declaration it '
              'discloses — no eligibility is held yet');
    });

    testWidgets(
        'checking 18+ mounts the designed on-device notice in the REAL screen',
        (tester) async {
      await tester.pumpWidget(harness(RecordingAuthService()));

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final notice = find.byType(SignupEligibilityNotice);
      expect(notice, findsOneWidget,
          reason: 'the declaration is captured with nowhere to persist it '
              '(#55) — the rider must be TOLD it is held on this device, not '
              'left to assume it was saved to their account');
      expect(tester.getSize(notice).height, greaterThan(0),
          reason: 'the disclosure must be a real, visible surface — not a '
              'collapsed box');
      expect(find.textContaining('this device'), findsWidgets,
          reason: 'the honest fact — on-device only — must be on screen');
    });

    testWidgets('un-checking 18+ takes the disclosure away with it',
        (tester) async {
      await tester.pumpWidget(harness(RecordingAuthService()));

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SignupEligibilityNotice), findsOneWidget,
          reason: 'precondition: the declaration raised the disclosure');

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SignupEligibilityNotice), findsNothing,
          reason: 'no declaration held → nothing to disclose; the notice is '
              'driven by real state, never pinned on');
    });

    testWidgets('the 18+ box still GATES submit exactly as before',
        (tester) async {
      final auth = RecordingAuthService();
      await tester.pumpWidget(harness(auth));

      await tester.enterText(
          find.byKey(const Key('signup_name')), 'Sam Rider');
      await tester.enterText(
          find.byKey(const Key('signup_email')), 'sam@hoppin.uk');
      await tester.enterText(
          find.byKey(const Key('signup_password')), 'hunter2hunter');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('signup_submit')));
      await tester.tap(find.byKey(const Key('signup_submit')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(auth.signUpCalls, isEmpty,
          reason: 'mounting the disclosure must not weaken the 18+ gate — '
              'unchecked still blocks the service call');
      expect(find.byType(SignupEligibilityNotice), findsNothing,
          reason: 'and no eligibility is disclosed when none was declared');
    });
  });
}
