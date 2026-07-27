import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/support/help/help_support_screen.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Figma #38 — Profile › Help & Support. The screen NOBODY NOTICED WAS MISSING,
/// because the Profile hub's row LOOKED wired: it points at `/support`, which is
/// the ticket TAB — a different screen entirely.
///
/// This one is FAQ + Contact + Legal. No tickets on it. Zero backend. And it is
/// where the privacy-notice link that COMPLY-01 depends on actually lives.
///
/// 🔴 The frame's `+44 123 234 5567` and `support@hoppin.com` are PLACEHOLDERS.
/// `grep -rn "tel:"` is EMPTY monorepo-wide and Phase 11 pinned it that way.
/// This frame is the first thing that would break it. It must not.
void main() {
  Future<void> pumpHelp(WidgetTester tester, {ThemeData? theme}) async {
    // A tall surface so the whole ListView is built — the Legal section (the
    // one COMPLY-01 depends on) sits below a phone-height fold, and a lazily
    // un-built widget would read as a missing one.
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: theme ?? HoppinTheme.riderLight(),
        home: const HelpSupportScreen(),
      ),
    ));
    // Bounded pumps only — never pumpAndSettle (project convention).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('SUPPORT: Figma #38 renders its three sections', () {
    testWidgets('FAQ, Contact and Legal are all present', (tester) async {
      await pumpHelp(tester);

      expect(
        find.textContaining('FAQ', findRichText: true),
        findsWidgets,
        reason: 'The #38 frame promises an FAQ accordion.',
      );
      expect(
        find.textContaining('Contact', findRichText: true),
        findsWidgets,
        reason: 'The #38 frame promises a Contact section.',
      );
      expect(
        find.textContaining('Legal', findRichText: true),
        findsWidgets,
        reason:
            'The Legal section is the one COMPLY-01 depends on — it hosts the '
            'privacy-notice link.',
      );
    });

    testWidgets('the FAQ accordion expands on tap (ephemeral view state)',
        (tester) async {
      await pumpHelp(tester);

      expect(
        find.byType(ExpansionTile),
        findsWidgets,
        reason: 'The FAQ is an accordion, per the frame.',
      );

      const question = 'How do I book a ride?';
      const answerFragment = 'Enter your pickup and destination';

      expect(
        find.textContaining(answerFragment, findRichText: true),
        findsNothing,
        reason: 'The accordion starts collapsed.',
      );

      await tester.tap(find.text(question));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining(answerFragment, findRichText: true),
        findsOneWidget,
        reason:
            'Expand/collapse is EPHEMERAL StatefulWidget state — it works, and '
            'nothing about it is persisted. Nothing here needs persisting, and '
            'nothing here may persist.',
      );
    });

    testWidgets('the Legal section links to Terms and Privacy Policy',
        (tester) async {
      await pumpHelp(tester);

      expect(
        find.textContaining('Privacy Policy', findRichText: true),
        findsOneWidget,
        reason:
            'The privacy-notice link is what makes the CONTRACT basis lawful '
            '(Arts. 13/14). It must be here, and it must resolve.',
      );
      expect(
        find.textContaining('Terms', findRichText: true),
        findsWidgets,
        reason: 'The frame promises Terms too.',
      );
    });
  });

  group('SUPPORT: the placeholder contact details MUST NOT ship', () {
    testWidgets('the fake phone number is nowhere on screen', (tester) async {
      await pumpHelp(tester);

      expect(
        find.textContaining('+44 123 234 5567', findRichText: true),
        findsNothing,
        reason:
            'The frame s phone number is a PLACEHOLDER. Shipping an invented '
            'support line is a dead end that lies — a rider would call it.',
      );
    });

    testWidgets('the fake support email is nowhere on screen', (tester) async {
      await pumpHelp(tester);

      expect(
        find.textContaining('support@hoppin.com', findRichText: true),
        findsNothing,
        reason:
            'The frame s email is a PLACEHOLDER. Mail to a made-up address '
            'goes nowhere and the rider never learns that.',
      );
    });

    testWidgets('Contact offers the HONEST in-app route instead',
        (tester) async {
      await pumpHelp(tester);

      expect(
        find.textContaining('Open a ticket', findRichText: true),
        findsOneWidget,
        reason:
            'Until the owner supplies real contact details, the honest route '
            'is the one that actually works: a real support ticket (POST '
            '/me/support-tickets is genuinely bound).',
      );
    });

    test('the screen source contains no tel: and no mailto:', () {
      final src = File(
        'lib/features/support/help/help_support_screen.dart',
      ).readAsStringSync();

      expect(
        src.contains('tel:'),
        isFalse,
        reason:
            'grep -rn "tel:" is EMPTY monorepo-wide and Phase 11 pinned it '
            'that way. This frame is the first thing that would break it.',
      );
      expect(
        src.contains('mailto:'),
        isFalse,
        reason:
            'Same pin, extended: no mailto: to an address that does not exist.',
      );
      expect(
        src.contains('+44 123 234 5567') || src.contains('support@hoppin.com'),
        isFalse,
        reason: 'Placeholder contact details must not reach the source either.',
      );
    });

    test('the screen source routes Legal at the real /legal/privacy path', () {
      final src = File(
        'lib/features/support/help/help_support_screen.dart',
      ).readAsStringSync();

      expect(
        src.contains('/legal/privacy'),
        isTrue,
        reason:
            'This is the Arts. 13/14 transparency route COMPLY-01 needs. A '
            'missing privacy notice is a BIGGER compliance hole than the '
            'missing consent endpoint.',
      );
      expect(
        src.contains('/legal/terms'),
        isTrue,
        reason: 'Terms must resolve too.',
      );
    });
  });

  group('SUPPORT: #38 renders in both themes', () {
    for (final entry in {
      'light': HoppinTheme.riderLight(),
      'dark': HoppinTheme.riderDark(),
    }.entries) {
      testWidgets('renders non-blank in ${entry.key}', (tester) async {
        await pumpHelp(tester, theme: entry.value);

        expect(
          find.byType(Text),
          findsWidgets,
          reason: 'Both themes are first-class (${entry.key}).',
        );
      });
    }
  });
}
