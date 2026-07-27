import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/features/support/support_categories.dart';
import 'package:hoppin_rider/features/support/support_screen.dart';
import 'package:hoppin_rider/features/support/ticket_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// SUPPORT-01 — the ONE fully end-to-end BOUND cluster in Phase 12.
///
/// Two things this file polices, and they pull in opposite directions:
///
///  1. **The binding must never break.** `POST/GET /me/support-tickets` is the
///     one place a rider gets a real, working round trip. The conversion to the
///     design system is cosmetic surgery on a live patient.
///
///  2. **The app must not advertise what does not exist.** The Figma
///     "Automated Support" frame shows refunds *"issued automatically"* by a
///     resolution engine that DOES NOT EXIST (SL-7). Truth wins over Figma.
void main() {
  // ── The fake ──────────────────────────────────────────────────────────
  // Repositories are duck-typed in this codebase (`implements`), so no shared
  // package needs touching to fake one.

  group('SUPPORT-01: the bound round trip (it must survive the conversion)',
      () {
    testWidgets('the ticket list renders real tickets from the repository',
        (tester) async {
      final repo = _FakeSupportRepository(tickets: [
        _ticket('t1', subject: 'Driver took a long route'),
        _ticket('t2', subject: 'Charged twice', status: 'resolved'),
      ]);

      await _pumpSupport(tester, repo);

      expect(
        find.text('Driver took a long route'),
        findsOneWidget,
        reason: 'GET /me/support-tickets is BOUND — real tickets must render',
      );
      expect(
        find.text('Charged twice'),
        findsOneWidget,
        reason: 'every ticket in the response renders, open or resolved',
      );
    });

    testWidgets('an empty list renders an honest empty state', (tester) async {
      await _pumpSupport(tester, _FakeSupportRepository(tickets: const []));

      expect(
        find.byType(HopEmptyState),
        findsOneWidget,
        reason:
            'unlike the notification centre, we genuinely CAN list tickets — '
            'so "no tickets yet" is a FACT here, not a guess. An empty state '
            'is honest precisely because the endpoint is bound.',
      );
    });

    testWidgets('creating a ticket calls createTicket exactly once with the '
        'picked category', (tester) async {
      final repo = _FakeSupportRepository(
        tickets: const [],
        // The screen hops to /support/:id after a successful create — that hop
        // is part of the bound round trip, so the harness routes it for real.
        seededThread: TicketThread(ticket: _ticket('new-ticket-id')),
      );
      await _pumpSupport(tester, repo);

      await tester.tap(find.text('New ticket'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.enterText(
        find.byKey(const Key('support.newTicket.subject')),
        'My driver never arrived',
      );
      await tester.pump();

      // Pick a non-default category through the real picker control.
      await tester.tap(find.byKey(const Key('support.newTicket.category')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(
        find.text(SupportCategories.labels[SupportCategories.lostItem]!).last,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.byKey(const Key('support.newTicket.submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        repo.createCalls,
        hasLength(1),
        reason:
            'POST /me/support-tickets is BOUND and must fire exactly once — '
            'a double-post opens two tickets for one problem',
      );
      expect(
        repo.createCalls.single.category,
        SupportCategories.lostItem,
        reason:
            'the category the rider picked is the category that goes on the '
            'wire — and it comes from the single-source taxonomy',
      );
      expect(
        repo.createCalls.single.subject,
        'My driver never arrived',
        reason: 'subject is the only REQUIRED field on the endpoint',
      );
    });

    testWidgets('the picker offers the two legal routes alongside the five '
        'originals, labelled from the taxonomy', (tester) async {
      await _pumpSupport(tester, _FakeSupportRepository(tickets: const []));

      await tester.tap(find.text('New ticket'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.byKey(const Key('support.newTicket.category')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      for (final value in SupportCategories.values) {
        expect(
          find.text(SupportCategories.labelFor(value)),
          findsWidgets,
          reason:
              'the picker is driven by SupportCategories — every category, '
              'including the account_deletion and data_export legal routes, '
              'is offered. Missing: $value',
        );
      }
    });

    testWidgets('the thread renders messages and posting a reply calls '
        'postMessage once', (tester) async {
      final repo = _FakeSupportRepository(
        tickets: const [],
        seededThread: TicketThread(
          ticket: _ticket('t1', subject: 'Charged twice'),
          messages: const [
            TicketMessage(id: 'm1', body: 'I was charged twice.'),
            TicketMessage(id: 'm2', body: 'Looking into it.', isStaff: true),
          ],
        ),
      );

      await _pumpTicket(tester, repo, 't1');

      expect(
        find.text('I was charged twice.'),
        findsOneWidget,
        reason: 'GET /me/support-tickets/:id is BOUND — the thread renders',
      );
      expect(
        find.text('Looking into it.'),
        findsOneWidget,
        reason: 'a staff reply is a real thing a human sent — it renders',
      );

      await tester.enterText(
        find.byKey(const Key('support.ticket.reply')),
        'Any update?',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('support.ticket.send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        repo.replyCalls,
        hasLength(1),
        reason:
            'POST /me/support-tickets/:id/messages is BOUND and must fire '
            'exactly once — a duplicated reply reads as a spamming rider',
      );
      expect(
        repo.replyCalls.single.body,
        'Any update?',
        reason: 'the reply that reaches the human is the one the rider typed',
      );
    });
  });

  group('SUPPORT-01: a FAILED endpoint shows an error, never an endless spinner',
      () {
    // Riverpod 3 delivers a failed FutureProvider as AsyncLoading(error: …) —
    // `isLoading` stays TRUE while the error rides along. A bare `.when` ladder
    // therefore routes a FAILURE into the LOADING branch, and the rider gets a
    // spinner that never resolves. It presents as a hang, not an error: silent,
    // ships green, and only bites when the server is actually down.
    //
    // A rider whose ticket list hangs concludes support is broken. These two
    // tests are the only thing standing between us and that.

    testWidgets('a failing GET /me/support-tickets renders an error rung',
        (tester) async {
      await _pumpSupport(tester, _FakeSupportRepository.failing());

      expect(
        find.byType(HopBanner),
        findsWidgets,
        reason:
            'the list endpoint failed — the rider must be TOLD. Riverpod 3 '
            'keeps isLoading true on a failed future, so a loading-first `when` '
            'ladder would show an endless spinner instead of this.',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'a spinner after a FAILURE is a hang, not a load. The call is over '
            '— it lost. Say so.',
      );
      expect(
        find.text('Retry'),
        findsOneWidget,
        reason: 'a failure the rider can retry must offer the retry',
      );
    });

    testWidgets('a failing GET /me/support-tickets/:id renders an error rung',
        (tester) async {
      await _pumpTicket(tester, _FakeSupportRepository.failing(), 't1');

      expect(
        find.byType(HopBanner),
        findsWidgets,
        reason:
            'the thread endpoint failed — same Riverpod 3 trap, same honest '
            'answer: an error rung, not a spinner',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'the load is over and it failed — stop pretending it is running',
      );
    });
  });

  group('SUPPORT-01: the §3.2 human-support disclosure (a virtue, and TRUE)',
      () {
    testWidgets('the tab tells the rider a person reads every ticket',
        (tester) async {
      await _pumpSupport(tester, _FakeSupportRepository(tickets: const []));

      expect(
        find.textContaining('A person reads every ticket'),
        findsOneWidget,
        reason:
            'Scope-Lock §3.2 mandates "No Human Interaction" and the automated '
            'resolution engine (SL-7) DOES NOT EXIST. Support ships as a '
            'disclosed human-interaction deviation. Saying so inverts the '
            'deviation into a virtue — and it is what makes the deletion route '
            'credible: the rider must believe a HUMAN will act on an erasure '
            'request.',
      );
    });
  });

  group('SUPPORT-01: nothing is advertised that does not exist', () {
    testWidgets('the screen never claims a refund was issued automatically',
        (tester) async {
      await _pumpSupport(tester, _FakeSupportRepository(tickets: const []));

      expect(
        find.textContaining('refund issued automatically'),
        findsNothing,
        reason:
            'the automated-resolution engine (SL-7) DOES NOT EXIST. The Figma '
            '"Automated Support" frame advertises refunds the backend cannot '
            'issue. Truth wins over Figma.',
      );
    });

    testWidgets('no "Preferred Resolution" picker — the endpoint has no such '
        'field', (tester) async {
      await _pumpSupport(tester, _FakeSupportRepository(tickets: const []));

      await tester.tap(find.text('New ticket'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.textContaining('Preferred Resolution'),
        findsNothing,
        reason:
            'POST /me/support-tickets has no resolution field. A picker whose '
            'value is silently discarded is a control that LIES — exactly the '
            'class of bug this phase exists to delete. The rider says what '
            'they want in the free-text body, which a human actually reads.',
      );
    });

    test('the fiction never even appears in the source', () {
      for (final path in const [
        'lib/features/support/support_screen.dart',
        'lib/features/support/ticket_screen.dart',
        'lib/features/support/support_categories.dart',
      ]) {
        final src = File(path).readAsStringSync().toLowerCase();
        expect(
          src.contains('refund issued automatically'),
          isFalse,
          reason:
              'the refund automation does not exist — the string must not be '
              'anywhere in the support feature, not even in a comment that '
              'could later be copy-pasted into copy: $path',
        );
        expect(
          src.contains('preferred resolution'),
          isFalse,
          reason: 'there is no such field on the endpoint: $path',
        );
      }
    });
  });

  group('SUPPORT-01: the conversion is a MACHINE-CHECKED fact, not a claim',
      () {
    test('the support screens carry zero raw Material and zero raw pixels', () {
      const raws = <String>[
        'AppBar(',
        'FloatingActionButton',
        'ListTile(',
        'DropdownButtonFormField',
        'FilledButton',
        'theme.colorScheme',
        'EdgeInsets.all(',
      ];

      for (final path in const [
        'lib/features/support/support_screen.dart',
        'lib/features/support/ticket_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        for (final raw in raws) {
          expect(
            src.contains(raw),
            isFalse,
            reason:
                'the one FULLY BOUND screen in the phase must be on the design '
                'system — it is the one place the rider gets a real experience, '
                'and it predates Phase 8. Raw Material found in $path: $raw',
          );
        }
      }
    });

    test('the taxonomy lives in exactly ONE file — the screens never hand-type '
        'a legal category', () {
      for (final path in const [
        'lib/features/support/support_screen.dart',
        'lib/features/support/ticket_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains("'account_deletion'"),
          isFalse,
          reason:
              'the wire string lives in support_categories.dart ONLY. Two '
              'copies of a load-bearing legal category WILL drift, and a '
              'drifted category means an erasure request ops cannot find: '
              '$path',
        );
        expect(
          src.contains("'data_export'"),
          isFalse,
          reason: 'same contract — the taxonomy is the single source: $path',
        );
      }

      expect(
        File('lib/features/support/support_screen.dart')
            .readAsStringSync()
            .contains('SupportCategories'),
        isTrue,
        reason:
            'the picker must READ the taxonomy, not restate it — that is the '
            'whole point of publishing it as the cross-lane contract',
      );
    });
  });
}

// ── Harness ─────────────────────────────────────────────────────────────

/// The support screen navigates with `context.go` on both tap-through and
/// post-submit, so the harness supplies a real router. Faking that away would
/// hide a genuine crash — the screen must work inside the app's router, and the
/// `/support/:id` hop after opening a ticket is part of the bound round trip.
Future<void> _pumpSupport(
  WidgetTester tester,
  _FakeSupportRepository repo,
) async {
  final router = GoRouter(
    initialLocation: '/support',
    routes: [
      GoRoute(
        path: '/support',
        builder: (_, _) => const SupportScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) =>
                TicketScreen(ticketId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [supportRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      theme: HoppinTheme.riderLight(),
      routerConfig: router,
    ),
  ));
  // Bounded pumps only — never pumpAndSettle (project convention).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _pumpTicket(
  WidgetTester tester,
  _FakeSupportRepository repo,
  String ticketId,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [supportRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: HoppinTheme.riderLight(),
      home: TicketScreen(ticketId: ticketId),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

SupportTicket _ticket(
  String id, {
  String? subject,
  String status = 'open',
}) =>
    SupportTicket(
      id: id,
      subject: subject,
      status: status,
      createdAt: DateTime(2026, 7, 13, 9, 30),
    );

// ── The fake repository ─────────────────────────────────────────────────

class _CreateCall {
  _CreateCall({required this.subject, this.category, this.body});

  final String subject;
  final String? category;
  final String? body;
}

class _ReplyCall {
  _ReplyCall({required this.ticketId, required this.body});

  final String ticketId;
  final String body;
}

class _FakeSupportRepository implements SupportRepository {
  _FakeSupportRepository({required this.tickets, this.seededThread})
      : fails = false;

  /// Every read throws — the server is down. This is the case that used to
  /// present as an endless spinner.
  _FakeSupportRepository.failing()
      : tickets = const [],
        seededThread = null,
        fails = true;

  final List<SupportTicket> tickets;
  final TicketThread? seededThread;
  final bool fails;

  final List<_CreateCall> createCalls = [];
  final List<_ReplyCall> replyCalls = [];

  @override
  Future<String> createTicket({
    required String subject,
    String? category,
    String? typeCode,
    String? priority,
    String? rideId,
    String? body,
    List<String>? tags,
  }) async {
    createCalls
        .add(_CreateCall(subject: subject, category: category, body: body));
    return 'new-ticket-id';
  }

  @override
  Future<List<SupportTicket>> myTickets() async {
    if (fails) throw Exception('support list is down');
    return tickets;
  }

  @override
  Future<TicketThread> thread(String ticketId) async {
    if (fails) throw Exception('support thread is down');
    return seededThread ?? (throw StateError('no thread seeded for $ticketId'));
  }

  @override
  Future<void> reply({required String ticketId, required String body}) async {
    replyCalls.add(_ReplyCall(ticketId: ticketId, body: body));
  }
}
