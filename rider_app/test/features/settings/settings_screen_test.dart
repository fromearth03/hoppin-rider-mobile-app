import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/app.dart';
import 'package:hoppin_rider/features/settings/settings_screen.dart';
import 'package:hoppin_rider/features/settings/widgets/settings_prefs_unavailable.dart';
import 'package:hoppin_rider/features/settings/widgets/settings_toggle_row.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../support/recording_support_repository.dart';

/// ACCT-03 — the Settings screen, and seam #71 (settings preferences).
///
/// The whole point of this file is that Settings is the screen where a rider
/// most expects controls to DO things, and seven of eight do not. So the
/// assertions are mostly negative:
///
///   * exactly ONE screen-level rung (eight identical rungs is noise, and noise
///     is how a disclosure gets ignored);
///   * every inert switch is `onChanged: null` — **`isNull`**, never "the
///     handler ran and did nothing". `onChanged: (_) {}` is a lie with a ripple
///     on it, and it is the exact Wave-0 bug that shipped on this screen's
///     parent (`profile_screen.dart:261`, `onTap: rows[i].onTap ?? () {}`);
///   * the fabrications the Figma draws are NOT on the screen at all;
///   * and driving every control on the screen writes NOTHING.
void main() {
  late RecordingSupportRepository support;

  setUp(() => support = RecordingSupportRepository());

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    ThemeData? theme,
  }) async {
    // A tall surface, so the whole screen — including the delete-account route
    // at the very bottom — is laid out and assertable in one pass. Reachability
    // is separately proved by ensureVisible on the real ListView below.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      supportRepositoryProvider.overrideWithValue(support),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? HoppinTheme.riderLight(),
        home: const SettingsScreen(),
      ),
    ));
    // Bounded pumps only — never pumpAndSettle (project convention).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    return container;
  }

  SettingsToggleRow rowFor(WidgetTester tester, String label) =>
      tester.widget<SettingsToggleRow>(
        find.widgetWithText(SettingsToggleRow, label),
      );

  /// The switch INSIDE a row. Tapping the row body deliberately does nothing —
  /// only the control is a control, and this lane does not ship giant invisible
  /// tap targets over inert rows.
  Finder switchIn(Finder row) => find.descendant(
        of: row,
        matching: find.byType(Switch),
      );

  Future<void> flip(WidgetTester tester, Finder row) async {
    await tester.tap(switchIn(row), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  group('ACCT-03 / seam 71: ONE rung for the whole screen', () {
    testWidgets('SettingsPrefsUnavailable is CONSTRUCTED exactly once',
        (tester) async {
      await pumpSettings(tester);

      expect(
        find.byType(SettingsPrefsUnavailable),
        findsOneWidget,
        reason:
            'Group C reachability: the #71 rung must be CONSTRUCTED on the real '
            'screen, and exactly ONCE. One rung per switch would be eight '
            'identical rungs — noise, and noise is how a disclosure gets '
            'ignored.',
      );
    });

    testWidgets('the rung renders non-blank text at non-zero size, both themes',
        (tester) async {
      for (final theme in [
        HoppinTheme.riderLight(),
        HoppinTheme.riderDark(),
      ]) {
        await pumpSettings(tester, theme: theme);

        final size = tester.getSize(find.byType(SettingsPrefsUnavailable));
        expect(size.width, greaterThan(0),
            reason: 'a zero-width disclosure discloses nothing');
        expect(size.height, greaterThan(0),
            reason: 'a zero-height disclosure discloses nothing');

        final texts = tester.widgetList<Text>(
          find.descendant(
            of: find.byType(SettingsPrefsUnavailable),
            matching: find.byType(Text),
          ),
        );
        expect(
          texts.any((t) => (t.data ?? '').trim().isNotEmpty),
          isTrue,
          reason: 'the rung must carry real words in both themes',
        );
      }
    });

    testWidgets('the rung says preferences RESET — it does not claim saving',
        (tester) async {
      await pumpSettings(tester);

      expect(
        find.textContaining('reset', findRichText: true),
        findsWidgets,
        reason:
            'The choice is session-scoped: there is no prefs endpoint and no '
            'persistence package in the repo. The rider must be told the '
            'switches reset when the app reopens — not left to assume they '
            'saved.',
      );
      expect(
        find.textContaining('Theme', findRichText: true),
        findsWidgets,
        reason:
            'The rung must name the ONE exception, or it reads as "nothing on '
            'this screen works" — which is its own small lie.',
      );
    });
  });

  group('ACCT-03: the theme toggle is the ONE control that genuinely works',
      () {
    testWidgets('flipping it changes the REAL themeModeProvider state',
        (tester) async {
      final container = await pumpSettings(tester);

      expect(
        container.read(themeModeProvider),
        ThemeMode.system,
        reason: 'the app follows the platform until the rider says otherwise',
      );

      await flip(tester, find.byKey(SettingsScreenKeys.themeToggle));

      expect(
        container.read(themeModeProvider),
        isNot(ThemeMode.system),
        reason:
            'This is the single genuinely-working control on the screen. It '
            'must move REAL state — not a local bool that pretends to.',
      );
      expect(
        container.read(themeModeProvider),
        ThemeMode.dark,
        reason: 'the toggle turns dark mode ON',
      );

      await flip(tester, find.byKey(SettingsScreenKeys.themeToggle));

      expect(
        container.read(themeModeProvider),
        ThemeMode.light,
        reason: 'and back OFF — an explicit light choice, not back to system',
      );
    });

    testWidgets('its onChanged is NOT null — it is the live one', (tester) async {
      await pumpSettings(tester);

      final theme = tester.widget<SettingsToggleRow>(
        find.byKey(SettingsScreenKeys.themeToggle),
      );
      expect(
        theme.onChanged,
        isNotNull,
        reason: 'the theme toggle works, so it must be enabled',
      );
    });
  });

  group('ACCT-03: the seven inert switches are INERT, not fake-inert', () {
    const inert = <String>[
      'Ride notifications',
      'Email notifications',
      'Chat & message sounds',
      'Share live location',
    ];

    for (final label in inert) {
      testWidgets('"$label" is visible, sized, and onChanged is NULL',
          (tester) async {
        await pumpSettings(tester);

        final finder = find.widgetWithText(SettingsToggleRow, label);
        expect(finder, findsOneWidget,
            reason: 'the control SHIPS — the design is real, the backend '
                'is not. Hiding it would be a different kind of dishonesty.');

        final size = tester.getSize(finder);
        expect(size.width, greaterThan(0));
        expect(size.height, greaterThan(0),
            reason: 'visible means visible — not a zero-height ghost');

        expect(
          rowFor(tester, label).onChanged,
          isNull,
          reason:
              'THE assertion of this lane. `onChanged: (_) {}` is a lie with a '
              'ripple on it — the exact Wave-0 bug (`onTap: rows[i].onTap ?? '
              '() {}`) that shipped five dead rows on this screen\'s parent. '
              'NULL is the truth. Never "the handler did nothing".',
        );
      });
    }

    testWidgets('tapping an inert switch changes NOTHING', (tester) async {
      await pumpSettings(tester);

      final finder = find.widgetWithText(
        SettingsToggleRow,
        'Ride notifications',
      );
      final before = rowFor(tester, 'Ride notifications').value;

      await tester.tap(finder, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        rowFor(tester, 'Ride notifications').value,
        before,
        reason:
            'a disabled switch that still visibly flips would be the worst of '
            'both worlds: it looks saved and it saved nothing',
      );
    });
  });

  group('COMPLY-01: Promotional Offers is LIVE — withdrawal must be as easy as '
      'giving', () {
    testWidgets('it is enabled (onChanged NOT null) and defaults OFF',
        (tester) async {
      await pumpSettings(tester);

      final row = tester.widget<SettingsToggleRow>(
        find.byKey(SettingsScreenKeys.marketingToggle),
      );
      expect(
        row.onChanged,
        isNotNull,
        reason:
            'ICO: withdrawal must be as easy as giving. A rider who cannot '
            'withdraw is a rider whose consent was never freely given — a '
            'greyed-out withdrawal control would make the SIGNUP consent '
            'invalid. This is the one inert-looking control that must be live.',
      );
      expect(
        row.value,
        isFalse,
        reason:
            'PECR requires opt-IN. A pre-ticked marketing box is unlawful, and '
            'the Figma agrees (Promotional Offers renders OFF).',
      );
    });

    testWidgets('flipping it moves real session state', (tester) async {
      await pumpSettings(tester);

      await flip(tester, find.byKey(SettingsScreenKeys.marketingToggle));

      expect(
        tester
            .widget<SettingsToggleRow>(
              find.byKey(SettingsScreenKeys.marketingToggle),
            )
            .value,
        isTrue,
        reason: 'the withdrawal/grant control must actually move',
      );
    });
  });

  group('ACCT-03: the Figma fabrications are NOT DRAWN', () {
    testWidgets('no "Require PIN for Payments" — that one is a SECURITY LIE',
        (tester) async {
      await pumpSettings(tester);

      expect(
        find.textContaining('PIN', findRichText: true),
        findsNothing,
        reason:
            'The Figma renders this toggle ON. The app has NO PIN feature at '
            'all. An ON switch claiming payments are PIN-protected when they '
            'are not is a SECURITY LIE — materially worse than a broken '
            'preference. It is omitted, not disabled.',
      );
    });

    testWidgets('no Language picker — there is no i18n in the app',
        (tester) async {
      await pumpSettings(tester);

      expect(
        find.textContaining('Language', findRichText: true),
        findsNothing,
        reason: 'there is no i18n anywhere in the app; a picker would be fiction',
      );
    });

    testWidgets('no Preferred Vehicle Type — dispatch honours no preference',
        (tester) async {
      await pumpSettings(tester);

      expect(
        find.textContaining('Preferred Vehicle', findRichText: true),
        findsNothing,
        reason:
            'It would imply a preference is honoured in dispatch. It is not '
            '(and cf. #65 — XL/Accessibility are not even bookable).',
      );
    });

    testWidgets('no Default Map View', (tester) async {
      await pumpSettings(tester);

      expect(
        find.textContaining('Default Map View', findRichText: true),
        findsNothing,
        reason: 'no backend, no client setting — a control with nothing behind it',
      );
    });
  });

  group('AUTH-05: the delete-account route is FINDABLE', () {
    testWidgets('the delete row is present, at the bottom, and reachable',
        (tester) async {
      await pumpSettings(tester);

      final row = find.byKey(SettingsScreenKeys.deleteAccountRow);
      expect(
        row,
        findsOneWidget,
        reason:
            'Art. 17 is not honoured by a right you have to know to look for. '
            'The route must exist on the Settings screen.',
      );

      expect(
        tester.getTopLeft(row).dy,
        greaterThan(
          tester.getTopLeft(find.byType(SettingsPrefsUnavailable)).dy,
        ),
        reason: 'it sits at the BOTTOM, below every preference group — where '
            'the Figma puts it, and where a rider looks for it',
      );
      expect(tester.getSize(row).height, greaterThan(0),
          reason: 'reachable means tappable');
    });

    testWidgets('on a REAL phone viewport it is reachable by scrolling',
        (tester) async {
      // The tall-surface harness above proves the row EXISTS. This proves a
      // rider on an actual phone can get to it — a legal right buried below an
      // unscrollable fold would be a right in name only.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [supportRepositoryProvider.overrideWithValue(support)],
        child: MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: const SettingsScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final row = find.byKey(SettingsScreenKeys.deleteAccountRow);
      await tester.scrollUntilVisible(row, 200, maxScrolls: 30);
      await tester.pump();

      expect(
        row,
        findsOneWidget,
        reason:
            'a rider on a 390x844 phone can scroll to the erasure route — it '
            'is not stranded below an unreachable fold',
      );
    });
  });

  group('SEAM PROOF BY EXCLUSIVITY: Settings writes NOTHING', () {
    testWidgets('driving EVERY control files ZERO tickets and copies NOTHING',
        (tester) async {
      final clipboardWrites = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardWrites.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpSettings(tester);

      // Drive every switch on the screen — live ones and inert ones alike —
      // and then the row bodies too, in case any of them is secretly a tap
      // target that does something.
      final switches = find.byType(Switch);
      for (var i = 0; i < switches.evaluate().length; i++) {
        await tester.tap(switches.at(i), warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      final rows = find.byType(SettingsToggleRow);
      for (var i = 0; i < rows.evaluate().length; i++) {
        await tester.tap(rows.at(i), warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(
        support.createdTickets,
        isEmpty,
        reason:
            'The Phase-11 recording-fake idiom, generalised from "the app NEVER '
            'dials" to "the app NEVER writes". ONLY the deletion/export popup '
            'may write in this lane. A toggle that quietly filed a ticket would '
            'be a write nobody asked for.',
      );
      expect(
        clipboardWrites,
        isEmpty,
        reason:
            'nothing on Settings copies anything — the Wave-0 share-sheet bug '
            'copied a sentence with no link in it, and it shipped',
      );
    });
  });
}
