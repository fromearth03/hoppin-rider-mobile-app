import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/features/settings/settings_screen.dart';
import 'package:hoppin_rider/features/settings/widgets/delete_account_popup.dart';
import 'package:hoppin_rider/features/settings/widgets/deletion_via_support_notice.dart';
import 'package:hoppin_rider/features/support/support_categories.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../support/recording_support_repository.dart';

/// AUTH-05 + DATA-01 — the delete-account popup, and seam #73.
///
/// #73 is the strangest seam in the book: its STATE is `MISSING_BE (#43)`
/// because `DELETE /me` does not exist — but the ACTION the rider takes is
/// FULLY BOUND. A real row lands in a real database that a real human reads
/// (`DOCS/10-gdpr-rights-runbook.md`). It is the only seam in the project where
/// the rider's need is genuinely met, and a future reader will be tempted to
/// make the button inert "for consistency". These tests exist to stop that.
///
/// 🔴 The copy is LEGALLY CONSTRAINED. The admin endpoint behind the ticket is
/// `DELETE /users/:id`, which returns `status: "anonymised"` — **not**
/// `"deleted"`. Private-hire licensing and HMRC mandate minimum retention on
/// ride and payment records. The app must therefore NOT promise erasure. These
/// tests pin that it does not.
void main() {
  late RecordingSupportRepository support;
  late List<String> routes;

  setUp(() {
    support = RecordingSupportRepository();
    routes = <String>[];
  });

  Future<void> pumpSettings(WidgetTester tester, {ThemeData? theme}) async {
    // A tall surface so the whole Settings screen and the whole popup are laid
    // out in one pass. Reachability of the delete row on a real phone viewport
    // is proved separately, in settings_screen_test.dart.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/profile/settings',
      routes: [
        GoRoute(
          path: '/profile/settings',
          builder: (_, _) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/support/:id',
          builder: (_, state) {
            routes.add('/support/${state.pathParameters['id']}');
            return const Scaffold(body: Text('ticket thread'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [supportRepositoryProvider.overrideWithValue(support)],
      child: MaterialApp.router(
        theme: theme ?? HoppinTheme.riderLight(),
        routerConfig: router,
      ),
    ));
    // Bounded pumps only — never pumpAndSettle (project convention).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> openPopup(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(SettingsScreenKeys.deleteAccountRow));
    await tester.pump();
    await tester.tap(find.byKey(SettingsScreenKeys.deleteAccountRow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('seam 73: the popup opens and CONSTRUCTS the rung', () {
    testWidgets('tapping the delete row mounts DeletionViaSupportNotice',
        (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      expect(
        find.byType(DeletionViaSupportNotice),
        findsOneWidget,
        reason:
            'Group C reachability: the #73 rung must be CONSTRUCTED by a real '
            'view, presented via showDeleteAccountPopup( from the real screen. '
            'A declared-but-never-mounted disclosure is dead code wearing a '
            'compliance badge.',
      );
    });

    testWidgets('it renders in BOTH themes at non-zero size', (tester) async {
      for (final theme in [
        HoppinTheme.riderLight(),
        HoppinTheme.riderDark(),
      ]) {
        await pumpSettings(tester, theme: theme);
        await openPopup(tester);

        final size = tester.getSize(find.byType(DeletionViaSupportNotice));
        expect(size.width, greaterThan(0));
        expect(size.height, greaterThan(0),
            reason: 'a legal disclosure with no height discloses nothing');
      }
    });
  });

  group('AUTH-05: the copy carries the right, the clock, and the delays', () {
    testWidgets('it names the legal right', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      expect(
        find.textContaining('data-protection law', findRichText: true),
        findsWidgets,
        reason: 'the rider must be told this is a RIGHT, not a favour',
      );
    });

    testWidgets('it states the ONE MONTH statutory clock — and promises no '
        'faster', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      expect(
        find.textContaining('one month', findRichText: true),
        findsWidgets,
        reason:
            'Art. 12(3): "without undue delay and at the latest within one '
            'month". One month is the statutory MAXIMUM. Do not promise '
            'faster; do NOT promise instant.',
      );
      expect(
        find.textContaining('immediately', findRichText: true),
        findsNothing,
        reason: 'nothing here is immediate — a person actions it by hand',
      );
      expect(
        find.textContaining('straight away', findRichText: true),
        findsNothing,
        reason: 'same promise, plainer words — still false',
      );
    });

    testWidgets('it says a HUMAN does this by hand — no euphemism',
        (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      expect(
        find.textContaining('by hand', findRichText: true),
        findsWidgets,
        reason:
            'A manual process is lawful. Dressing it up as automatic is not. '
            'The rider is told exactly how their request is honoured.',
      );
    });

    testWidgets('it carries all THREE honest delays', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      for (final beat in ['trip in progress', 'dispute', 'law requires']) {
        expect(
          find.textContaining(beat, findRichText: true),
          findsWidgets,
          reason:
              'AUTH-05: honestly delayed for active trips / open disputes / '
              'legal retention. The right to erasure is NOT absolute — this is '
              'the law, not a fudge, and the popup says so plainly.',
        );
      }
    });
  });

  group('🔴 LEGAL: the app must NOT promise ERASURE — the backend ANONYMISES',
      () {
    testWidgets('it never says data "will be deleted"', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      for (final lie in [
        'will be deleted',
        'permanently deleted',
        'erase all',
        'wiped',
        'removed forever',
        'gone forever',
      ]) {
        expect(
          find.textContaining(lie, findRichText: true),
          findsNothing,
          reason:
              'DOCS/10: `DELETE /users/:id` returns status "anonymised", NOT '
              '"deleted". It anonymises and bans; it does not erase. '
              'Private-hire licensing and HMRC mandate minimum retention on '
              'ride and payment records. Copy promising erasure is a lie the '
              'backend does not perform.',
        );
      }
    });

    testWidgets('it says plainly that records are KEPT in anonymised form',
        (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      expect(
        find.textContaining('anonymised', findRichText: true),
        findsWidgets,
        reason:
            'The honest word, and the one the backend actually returns. The '
            'rider is told what really happens: personal details removed, '
            'account closed, ride and payment records kept without their name '
            'on them.',
      );
      expect(
        find.textContaining('account is closed', findRichText: true),
        findsWidgets,
        reason: 'what the rider actually gets: closure, not evaporation',
      );
    });
  });

  group('🔴 NO Deactivate — the Figma draws a third unbacked capability', () {
    testWidgets('the popup has no Deactivate option', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      expect(
        find.textContaining('Deactivate', findRichText: true),
        findsNothing,
        reason:
            'The Figma modal offers Deactivate · Delete · Cancel. "Temporary '
            'deactivation" has NO endpoint, NO ledger row, NO gap number, and '
            'is in NO requirement. Building it would invent a capability; '
            'minting a gap for it would hand the backend a false priority. It '
            'is deliberately not built and deliberately NOT given a gap number.',
      );
    });
  });

  group('AUTH-05: the primary action files exactly ONE REAL ticket', () {
    testWidgets('one account_deletion ticket — not zero, not two',
        (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      expect(
        support.createdTickets,
        hasLength(1),
        reason:
            'Exactly one. Not zero — the legal right would go unhonoured, and '
            'an inert button here is precisely what the owner rejected. Not '
            'two — a duplicate statutory request that ops must then '
            'disambiguate by hand.',
      );

      final ticket = support.createdTickets.single;
      expect(
        ticket['category'],
        SupportCategories.accountDeletion,
        reason:
            'imported from Lane D, never hand-typed — two copies of a '
            'load-bearing legal category WILL drift, and a drifted category '
            'means ops cannot triage an erasure request',
      );
      expect(
        (ticket['subject'] as String).toLowerCase(),
        contains('erasure'),
        reason:
            'Belt and braces for gap 75: DOCS/04 does not enumerate the legal '
            'values of `category`. If the server silently drops an unknown '
            'one, the ticket still opens — and a human ops reader must still '
            'be able to see what it IS. The request type rides in the subject '
            'too, and it costs nothing.',
      );
      expect(
        ticket['subject'],
        SupportCategories.deletionSubject,
        reason: 'the canonical subject, from the same single source of truth',
      );
    });

    testWidgets('it routes to /support/:id so the rider WATCHES it move',
        (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      expect(
        routes,
        contains('/support/${support.nextTicketId}'),
        reason:
            'The strongest possible answer to "did anything actually happen?" '
            'is letting the rider watch their own legal request move.',
      );
    });

    testWidgets('the rider\'s optional reason rides along in the body',
        (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);

      await tester.enterText(
        find.byKey(DeleteAccountKeys.reasonField),
        'I no longer use the service.',
      );
      await tester.pump();
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      expect(
        support.createdTickets.single['body'],
        contains('I no longer use the service.'),
        reason: 'if we ask for a reason, we must actually send it',
      );
    });
  });

  group('DATA-01: the export action files exactly ONE REAL ticket', () {
    testWidgets('one data_export ticket, right of access', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmExport));

      expect(
        support.createdTickets,
        hasLength(1),
        reason: 'exactly one — same exclusivity rule as deletion',
      );

      final ticket = support.createdTickets.single;
      expect(
        ticket['category'],
        SupportCategories.dataExport,
        reason: 'imported from Lane D, never hand-typed',
      );
      expect(
        ticket['subject'],
        SupportCategories.exportSubject,
        reason:
            'Art. 15 right of access. Same mechanism, same one-month clock, '
            'same runbook (DOCS/10).',
      );
    });

    testWidgets('it routes to /support/:id too', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmExport));

      expect(routes, contains('/support/${support.nextTicketId}'));
    });
  });

  group('🔴 A FAILED legal request must FAIL LOUDLY — never a silent spinner',
      () {
    testWidgets('a failed POST shows an honest error and does NOT route away',
        (tester) async {
      support.failure = Exception('502 bad gateway');
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      expect(
        routes,
        isEmpty,
        reason:
            'a failed request must NOT route the rider to a ticket that does '
            'not exist — that would be the appearance of compliance with '
            'nothing behind it',
      );
      expect(
        find.byType(StatusBanner),
        findsOneWidget,
        reason:
            'THE worst possible silent failure in this app. A rider who taps '
            '"request account deletion", sees a spinner, and is never told it '
            'failed walks away believing they exercised a statutory right when '
            'NOTHING was filed. That is worse than never offering the button.',
      );
      expect(
        find.byType(DeletionViaSupportNotice),
        findsOneWidget,
        reason: 'the popup stays open so they can actually retry',
      );
    });

    testWidgets('the actions RE-ENABLE after a failure — no permanent spinner',
        (tester) async {
      support.failure = Exception('502 bad gateway');
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      final delete = tester.widget<HopButton>(
        find.byKey(DeleteAccountKeys.confirmDelete),
      );
      expect(
        delete.onPressed,
        isNotNull,
        reason:
            'a busy flag stuck TRUE would disable both actions forever and '
            'render a dead popup that LOOKS like it is still working — the '
            'exact hang the sibling lane hit through the AsyncValue ladder, '
            'reached here by a different road (a leaked non-Exception throwable '
            'escaping an `on Exception` catch).',
      );
    });

    testWidgets('a NON-Exception throwable is still caught and surfaced',
        (tester) async {
      // `on Exception` would let this escape, leaving the popup permanently
      // busy with no message at all. That is the silent-hang shape.
      support.failure = StateError('not an Exception');
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      expect(
        find.byType(StatusBanner),
        findsOneWidget,
        reason: 'ANY failure of a legal request must be visible to the rider',
      );
      expect(
        find.textContaining('Nothing has been filed', findRichText: true),
        findsWidgets,
        reason:
            'the load-bearing sentence: the rider must know the request did '
            'NOT happen, so they can try again or reach us another way',
      );
      expect(routes, isEmpty, reason: 'and it must not route to a phantom ticket');
    });

    testWidgets('a retry after a failure files exactly ONE ticket',
        (tester) async {
      support.failure = Exception('502 bad gateway');
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      expect(support.createdTickets, isEmpty,
          reason: 'the failed attempt filed nothing');

      support.failure = null;
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      expect(
        support.createdTickets,
        hasLength(1),
        reason:
            'the retry works, and the failed attempt left no phantom duplicate '
            'behind it',
      );
      expect(routes, contains('/support/${support.nextTicketId}'));
    });
  });

  group('🔴 Pitfall 8: submitting does NOT sign the rider out or wipe anything',
      () {
    testWidgets('the rider is STILL SIGNED IN after filing a deletion request',
        (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.confirmDelete));

      // The lane's own source is the proof surface here: signing out would
      // require calling signOut, and this lane's diff contains no such call
      // (pinned by the analyzer grep in the plan's verification block). What
      // the widget test CAN prove is that the session-bearing surface survived
      // and the rider landed on their ticket rather than at a login wall.
      expect(
        routes,
        contains('/support/${support.nextTicketId}'),
        reason:
            'Nothing has been erased yet. Signing the rider out would SIMULATE '
            'deletion — a false persistence signal in the other direction — and '
            'it would strand them outside the very ticket they need to follow.',
      );
      expect(
        find.text('ticket thread'),
        findsOneWidget,
        reason:
            'they are on an AUTHENTICATED surface, not bounced to /login. The '
            'session survives the request, because the account still exists.',
      );
    });

    testWidgets('cancelling files NOTHING', (tester) async {
      await pumpSettings(tester);
      await openPopup(tester);
      await tapAndSettle(tester, find.byKey(DeleteAccountKeys.cancel));

      expect(
        support.createdTickets,
        isEmpty,
        reason:
            'a cancelled legal request is not a legal request — an accidental '
            'erasure ticket is a real cost to a real human',
      );
      expect(find.byType(DeletionViaSupportNotice), findsNothing,
          reason: 'and the popup closes');
    });
  });
}
