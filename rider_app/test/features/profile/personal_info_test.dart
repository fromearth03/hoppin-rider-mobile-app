import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/features/profile/personal/personal_facts.dart';
import 'package:hoppin_rider/features/profile/personal/personal_info_screen.dart';
import 'package:hoppin_rider/features/profile/personal/widgets/personal_info_unavailable.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../support/recording_support_repository.dart';

/// ACCT-02 — Personal Information, on seam 70 (SL-5).
///
/// There is no `GET /me/profile` and no `PATCH /me/profile`. There never has
/// been. So this screen may render ONLY what the session already holds, and
/// every control that looks like it saves something must be provably, visibly
/// off.
///
/// These tests are written as NEGATIVE claims on purpose. "Nothing was saved",
/// "this control does nothing", "no value was invented" are exactly the claims
/// a naive widget test waves through — and exactly the claims Wave 0 found
/// broken. Each one below gets a recorder or a literal-string assertion, not a
/// hope.
void main() {
  final light = HoppinTheme.riderLight();
  final dark = HoppinTheme.riderDark();

  /// The facts an OTP-signup rider's session genuinely carries: a name, an
  /// email, a phone and a creation date.
  const factsWithPhone = PersonalFacts(
    fullName: 'Sam Rider',
    email: 'sam@hoppin.uk',
    phone: '+44 7700 900123',
    memberSince: '2025-08-14T09:31:00Z',
  );

  /// The facts an email/password rider's session carries. Supabase never sets
  /// `.phone` on that path, so it is genuinely, honestly unknown.
  const factsWithoutPhone = PersonalFacts(
    fullName: 'Sam Rider',
    email: 'sam@hoppin.uk',
    memberSince: '2025-08-14T09:31:00Z',
  );

  /// The router that gives the rung's `/support` exit somewhere real to land —
  /// a disclosure that strands the rider is only half-honest, and a test that
  /// cannot follow the exit cannot prove it is not a dead end.
  ({GoRouter router, List<String> visited}) buildRouter() {
    final visited = <String>[];
    final router = GoRouter(
      initialLocation: '/profile/personal',
      routes: [
        GoRoute(
          path: '/profile/personal',
          builder: (_, _) => const PersonalInfoScreen(),
        ),
        GoRoute(
          path: '/support',
          builder: (_, _) {
            visited.add('/support');
            return const Scaffold(body: Text('support tab'));
          },
        ),
      ],
    );
    return (router: router, visited: visited);
  }

  Widget harness({
    required PersonalFacts facts,
    required GoRouter router,
    required RecordingSupportRepository support,
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: [
        personalFactsProvider.overrideWithValue(facts),
        supportRepositoryProvider.overrideWithValue(support),
      ],
      child: MaterialApp.router(
        theme: theme ?? light,
        routerConfig: router,
      ),
    );
  }

  /// Bounded pumps only — never `pumpAndSettle`.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  group('ACCT-02 · the screen renders only what the session actually knows', () {
    testWidgets('renders the Name and Email rows with the REAL session values',
        (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithoutPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      expect(find.text('Sam Rider'), findsOneWidget,
          reason: 'the name is a real JWT fact (user_metadata.full_name) — '
              'render it, and render nothing else in its place');
      expect(find.text('sam@hoppin.uk'), findsOneWidget,
          reason: 'the email is the account identifier — the one field the '
              'session always has');
    });

    testWidgets(
        'falls back to the email-derived label when the session has no name',
        (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: const PersonalFacts(email: 'nameless@hoppin.uk'),
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      expect(find.text('nameless@hoppin.uk'), findsWidgets,
          reason: 'full_name is only set at signup and is legitimately null — '
              'the hub already falls back to the email, so do the same here '
              'rather than inventing a display name');
    });

    testWidgets('renders the Contact row when the session HAS a phone',
        (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      expect(find.text('+44 7700 900123'), findsOneWidget,
          reason: 'OTP-signup riders DO have a phone on their session — when '
              'we know it, we must show it');
    });

    testWidgets(
        'OMITS the Contact row entirely when the session has no phone — no '
        'placeholder, no dash, no "Not set"', (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithoutPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      expect(find.text('Contact'), findsNothing,
          reason: 'email/password riders have no phone on the session at all. '
              'Omit the row. The label with nothing under it is still a row.');
      expect(find.text('—'), findsNothing,
          reason: '"—" reads as "you have not filled this in" when the truth '
              'is "we cannot tell you" — the same quiet lie Phase 11 refused '
              'for the notification centre');
      expect(find.textContaining('Not set'), findsNothing,
          reason: 'asserting absence when the truth is ignorance is a lie, '
              'just a polite one');
      expect(find.textContaining('Add phone'), findsNothing,
          reason: 'there is nowhere to add one — no PATCH /me/profile exists');
    });

    testWidgets('renders Member Since from the session creation date',
        (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      expect(find.text('Member Since'), findsOneWidget,
          reason: 'the account creation date IS a real fact the session '
              'carries — it is honest to show it');
      expect(find.textContaining('2025'), findsOneWidget,
          reason: 'the rendered date must come from the session value, not a '
              'Figma caption');
    });
  });

  group('ACCT-02 · the four Figma fabrications this screen refuses to draw', () {
    testWidgets('no "Clark Kent", no city, no photo picker, no fake save',
        (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      expect(find.text('Clark Kent'), findsNothing,
          reason: 'the Figma placeholder name. Wave 0 already deleted this '
              'literal from the Profile hub once, where every real rider saw '
              'it. It does not come back.');
      expect(find.textContaining('Wolverhampton'), findsNothing,
          reason: 'no rider-city field exists ANYWHERE — not in the JWT, not '
              'in the session, not in DOCS/04. The Figma value is a '
              'fabrication.');
      expect(find.text('City'), findsNothing,
          reason: 'the LABEL is the lie as much as the value — an empty City '
              'row still claims we hold a city');
      expect(find.textContaining('Choose File'), findsNothing,
          reason: 'there is no avatar endpoint. A picker would let a rider '
              'choose a photo that goes nowhere — the exact false-persistence '
              'signal the owner rejected.');
      expect(find.textContaining('picture.jpg'), findsNothing,
          reason: 'the Figma filename caption implies an upload happened');
      expect(find.textContaining('Upload'), findsNothing,
          reason: 'nowhere to upload to');
    });
  });

  group('ACCT-02 · the inertness triple (12-RESEARCH §6.1)', () {
    testWidgets(
        'Save is VISIBLE at real size, is onPressed: NULL, and is DISCLOSED',
        (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      final save = find.byKey(const Key('personal.save'));

      // HALF 1 — VISIBLE. A control that is absent is not inert; it is missing.
      expect(save, findsOneWidget,
          reason: 'a control that is absent is not inert — it is missing');
      expect(tester.getSize(save).height, greaterThan(0),
          reason: 'a disabled button nobody can see is not a disclosure');
      expect(tester.getSize(save).width, greaterThan(0),
          reason: 'zero-width is invisible, and invisible is not disclosed');

      // HALF 2 — INERT. Not "the handler did nothing". NULL.
      expect(tester.widget<HopButton>(save).onPressed, isNull,
          reason: 'a no-op callback still ripples — profile_screen.dart:261 '
              'shipped exactly that (onTap: rows[i].onTap ?? () {}) and gave '
              'five dead rows a full tap ripple over silence. Wave 0 caught '
              'it. The rider must SEE it is off.');

      // HALF 3 — DISCLOSED. A visible disabled control with no explanation is
      // a puzzle, not a disclosure.
      expect(find.byType(PersonalInfoUnavailable), findsOneWidget,
          reason: 'a visible disabled control with no explanation is a puzzle, '
              'not a disclosure');
    });

    testWidgets('tapping the inert Save changes NOTHING on screen',
        (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      await tester.tap(find.byKey(const Key('personal.save')),
          warnIfMissed: false);
      await settle(tester);

      expect(find.textContaining('Saved'), findsNothing,
          reason: 'nothing was saved, so nothing may say it was');
      expect(find.byType(SnackBar), findsNothing,
          reason: 'a confirmation toast over a dead button is the Wave-0 '
              'share-sheet bug in a different costume');
      expect(nav.visited, isEmpty,
          reason: 'the inert Save must not navigate anywhere either — going '
              'somewhere is still "something happened"');
    });

    testWidgets('every text field on the screen is non-editable', (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      // Guard against a vacuous pass: if the screen rendered no fields at all,
      // the loop below would assert nothing and still go green.
      expect(find.byType(TextField), findsNWidgets(4),
          reason: 'Name, Email, Contact and Member Since — the four facts the '
              'session actually holds for this rider. No City. No photo.');

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      for (final field in fields) {
        expect(field.readOnly, isTrue,
            reason: 'a field a rider can type into is a promise that the text '
                'goes somewhere. It does not — there is no PATCH /me/profile.');
        expect(field.enabled, isFalse,
            reason: 'read-only alone still takes focus and raises a keyboard, '
                'which reads as "you may edit this". Disabled reads as off.');
      }
    });
  });

  group('seam 70 · PersonalInfoUnavailable is mounted and does not strand', () {
    testWidgets(
        'the rung is CONSTRUCTED unconditionally — the seam is not '
        '"sometimes null", it is ALWAYS null', (tester) async {
      for (final facts in [factsWithPhone, factsWithoutPhone]) {
        final nav = buildRouter();
        await tester.pumpWidget(harness(
          facts: facts,
          router: nav.router,
          support: RecordingSupportRepository(),
        ));
        await settle(tester);

        expect(find.byType(PersonalInfoUnavailable), findsOneWidget,
            reason: 'there is no branch on which saving works, so there is no '
                'branch on which the rung is absent. Group C reachability '
                'wants the real mount site, not a declared-but-never-'
                'constructed widget.');
      }
    });

    testWidgets('the rung renders non-blank text at non-zero size in BOTH themes',
        (tester) async {
      for (final theme in [light, dark]) {
        final nav = buildRouter();
        await tester.pumpWidget(harness(
          facts: factsWithPhone,
          router: nav.router,
          support: RecordingSupportRepository(),
          theme: theme,
        ));
        await settle(tester);

        final rung = find.byType(PersonalInfoUnavailable);
        expect(rung, findsOneWidget, reason: 'the rung must render in $theme');
        final size = tester.getSize(rung);
        expect(size.width, greaterThan(0),
            reason: 'Group C asserts non-zero width');
        expect(size.height, greaterThan(0),
            reason: 'Group C asserts non-zero height');

        final texts = tester.widgetList<Text>(
          find.descendant(of: rung, matching: find.byType(Text)),
        );
        expect(texts.any((t) => (t.data ?? '').trim().isNotEmpty), isTrue,
            reason: 'a blank disclosure discloses nothing');
      }
    });

    testWidgets(
        'the rung offers a WORKING, ENABLED exit to /support — the honest '
        'route to Art. 16 rectification', (tester) async {
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: RecordingSupportRepository(),
      ));
      await settle(tester);

      final exit = find.byKey(const Key('personal.rung.support'));
      expect(exit, findsOneWidget,
          reason: 'a disclosure that strands the rider is only half-honest — '
              'CallUnavailableState set this precedent in Phase 11');

      await tester.tap(exit);
      await settle(tester);

      expect(nav.visited, contains('/support'),
          reason: 'the exit must actually land. Rectification (UK GDPR Art. '
              '16) is a real right, and support is the real route to it while '
              'PATCH /me/profile does not exist.');
    });
  });

  group('seam 70 · the screen writes NOTHING, anywhere', () {
    testWidgets(
        'driving every control opens ZERO support tickets and writes ZERO '
        'clipboard entries', (tester) async {
      final clipboardWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites
                .add((call.arguments as Map)['text']?.toString() ?? '');
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final support = RecordingSupportRepository();
      final nav = buildRouter();
      await tester.pumpWidget(harness(
        facts: factsWithPhone,
        router: nav.router,
        support: support,
      ));
      await settle(tester);

      // Drive EVERY control the screen exposes, not just the interesting one.
      await tester.tap(find.byKey(const Key('personal.save')),
          warnIfMissed: false);
      await settle(tester);
      for (final key in const [
        Key('personal.name'),
        Key('personal.email'),
        Key('personal.phone'),
        Key('personal.member_since'),
      ]) {
        await tester.tap(find.byKey(key), warnIfMissed: false);
        await settle(tester);
      }

      expect(support.createdTickets, isEmpty,
          reason: 'ONLY the deletion/export popup (Lane B) may write. Nothing '
              'on Personal Information may open a ticket on its own.');
      expect(clipboardWrites, isEmpty,
          reason: 'the Wave-0 share sheet copied a sentence containing no link '
              'and toasted "Link copied". This screen copies nothing at all.');
    });
  });
}
