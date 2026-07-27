import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/trip/cancel_flow.dart';
import 'package:hoppin_rider/features/trip/widgets/cancellation_unavailable_state.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../support/recording_support_repository.dart';

/// CANCEL-01 — the two-stage cancel-with-reason (Pitfall 2): the cancel call
/// carries the default `reason_id` at call time (because
/// `PATCH /rides/:id/cancel` REQUIRES a valid uuid — a non-seeded id →
/// VALIDATION_FAILED), and the reason survey is a SKIPPABLE POST-cancel
/// acknowledgment. The flow must NOT be reordered to gate the cancel button
/// behind a reason picker.
///
/// AND — the far bigger fact this file now pins — **cancellation is BROKEN on
/// live (backend gap #1, P0).** The reason ids the app sends are fabricated
/// placeholders that are not in the database, so the server rejects every
/// rider cancellation with `VALIDATION_FAILED`. That was known, and disclosed
/// ONLY in a source comment — a surface no rider will ever read — while the
/// sheet shipped a confident destructive confirm over it.
///
/// The rule: **a known-broken capability may not be presented as working. The
/// degradation must be VISIBLE and REACHABLE, BEFORE the user relies on it.**
/// These tests pin that: the disclosure is on screen before any confirm is
/// possible, the working route out (a real support ticket) is reachable from
/// it, and the confirm path still behaves honestly.
void main() {
  /// Bounded pumps only — never pumpAndSettle (project convention).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  // ── The gap-#1 pre-commit disclosure ───────────────────────────────────

  testWidgets(
    'the cancel sheet DISCLOSES that in-app cancellation is broken BEFORE any '
    'confirm action is possible',
    (tester) async {
      final h = await _boot(tester);

      // The rung is on screen the moment the sheet opens — the rider cannot
      // reach the confirm without having been told.
      expect(
        find.byType(CancellationUnavailableState),
        findsOneWidget,
        reason:
            'the gap-#1 rung must render on the intercept sheet itself, '
            'BEFORE the rider commits — a post-hoc error arrives after the '
            'rider has already relied on the button',
      );
      expect(
        find.byKey(CancellationDisclosureKeys.notice),
        findsOneWidget,
        reason: 'the disclosure surface must be present and findable',
      );
      expect(
        find.textContaining("isn't working right now"),
        findsOneWidget,
        reason:
            'the disclosure must state PLAINLY that cancelling in the app '
            'does not work — not hint at it, not bury it in a source comment',
      );
      expect(
        find.textContaining('carry on charging'),
        findsOneWidget,
        reason:
            'the rider must be told the consequence BEFORE committing: '
            'the trip keeps running, so it keeps charging',
      );

      // And it is genuinely visible — not clipped off a short sheet.
      final size = tester.getSize(find.byType(CancellationUnavailableState));
      expect(
        size.height,
        greaterThan(0),
        reason: 'a disclosure collapsed to zero height is not a disclosure',
      );

      await h.dispose(tester);
    },
  );

  testWidgets(
    'the working alternative — a real support ticket for THIS ride — is '
    'reachable from the disclosure and lands the rider on the ticket',
    (tester) async {
      final h = await _boot(tester);

      expect(
        find.byKey(CancellationDisclosureKeys.contactSupport),
        findsOneWidget,
        reason:
            'a disclosure that strands the rider is only half-honest — the '
            'rung must offer the route that actually works',
      );

      await tester.tap(find.byKey(CancellationDisclosureKeys.contactSupport));
      await settle(tester);

      // EXACTLY ONE real ticket — never zero (the rider is stranded in a ride
      // they are being charged for) and never two (ops has to disambiguate).
      expect(
        h.support.createdTickets.length,
        1,
        reason:
            'the support route must file exactly one REAL '
            'POST /me/support-tickets — this is the only working way out of '
            'gap #1',
      );
      final ticket = h.support.createdTickets.single;
      expect(
        ticket['ride_id'],
        h.rideId,
        reason:
            'the ticket must carry THIS ride id, or the human reading it '
            'cannot find the trip they are being asked to stop',
      );
      expect(
        ticket['subject'],
        isNotEmpty,
        reason: 'the ticket must say what it is for',
      );

      // The rider lands ON the ticket — they can watch a person act on it.
      expect(
        find.text('ticket:${h.support.nextTicketId}'),
        findsOneWidget,
        reason:
            'the rider must be routed to /support/:id, not dropped back '
            'onto the trip with no evidence anything happened',
      );

      await h.dispose(tester);
    },
  );

  testWidgets(
    'a FAILED support ticket fails LOUDLY — nothing is filed and the rider is '
    'told so, rather than left believing help is coming',
    (tester) async {
      final h = await _boot(tester);
      // Deliberately a non-Exception throwable: a catch that only handles
      // Exception would strand the rider on a dead disabled button.
      h.support.failure = StateError('boom');

      await tester.tap(find.byKey(CancellationDisclosureKeys.contactSupport));
      await settle(tester);

      expect(
        h.support.createdTickets,
        isEmpty,
        reason:
            'nothing was filed — the test must reproduce the failure, not '
            'paper over it',
      );
      expect(
        find.textContaining('Nothing has been sent'),
        findsOneWidget,
        reason:
            'a silent failure here would leave the rider believing a human '
            'is coming to stop their ride when no ticket exists',
      );
      // The route is still offered — the rider can retry.
      expect(
        tester
            .widget<HopButton>(
              find.byKey(CancellationDisclosureKeys.contactSupport),
            )
            .onPressed,
        isNotNull,
        reason:
            'after a failure the support action must be live again — a '
            'stuck-disabled button is a dead end on the only working route',
      );

      await h.dispose(tester);
    },
  );

  testWidgets(
    'the cancel button is NOT disabled — a dead control is its own lie',
    (tester) async {
      final h = await _boot(tester);

      final cancel = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Cancel ride'),
          matching: find.byType(TextButton),
        ),
      );
      expect(
        cancel.onPressed,
        isNotNull,
        reason:
            'greying out Cancel ride would disclose the gap and strand the '
            'rider with it — the attempt is still made and still fails '
            'honestly',
      );

      await h.dispose(tester);
    },
  );

  // ── The pre-existing CANCEL-01 flow, unchanged ─────────────────────────

  testWidgets('stage 1 keeps the ride the positive primary action; cancel is '
      'NOT gated behind picking a reason', (tester) async {
    final h = await _boot(tester);

    // The intercept keeps the ride — "No, keep my ride" is the primary CTA.
    expect(
      find.text('No, keep my ride'),
      findsOneWidget,
      reason: 'keeping the ride stays the positive primary action',
    );
    expect(
      find.text('Cancel ride'),
      findsOneWidget,
      reason: 'the destructive confirm is still present, just disclosed',
    );

    // The cancel button is immediately actionable — there is NO reason picker
    // standing between the rider and the cancel call (reason-first gating is
    // the forbidden reorder).
    expect(
      find.text('Mind telling us why?'),
      findsNothing,
      reason: 'the reason survey must NOT appear before the cancel call',
    );

    await h.dispose(tester);
  });

  testWidgets('confirming cancel sends the default reason id, then the '
      'skippable post-cancel survey appears', (tester) async {
    final h = await _boot(tester);

    // Confirm the cancel — this fires cancelWithDefaultReason(), which sends
    // the first reason id. The demo world accepts it; the LIVE backend does
    // NOT (gap #1), which is precisely why the rung above exists.
    await tester.tap(find.text('Cancel ride'));
    await settle(tester);

    expect(
      h.world.eventLog.any((e) => e.contains('rideCancelled')),
      isTrue,
      reason: 'the cancel call must have sent the default reason id',
    );

    // Stage 2: the post-cancel reason survey appears and is skippable.
    expect(
      find.text('Mind telling us why?'),
      findsOneWidget,
      reason: 'the reason survey is a POST-cancel acknowledgment',
    );
    expect(
      find.text('Skip'),
      findsOneWidget,
      reason: 'skipping the survey is a first-class choice',
    );

    // No ticket was filed by the cancel path — the support route is the
    // rider's choice, never something the app takes on their behalf.
    expect(
      h.support.createdTickets,
      isEmpty,
      reason: 'confirming a cancel must not silently open a support ticket',
    );

    await h.dispose(tester);
  });

  testWidgets('the post-cancel survey lists the reasons and skipping '
      'closes it cleanly', (tester) async {
    final h = await _boot(tester);

    await tester.tap(find.text('Cancel ride'));
    await settle(tester);

    // The reasons render (they are a disclosed stub — SEAMED, gap #1).
    expect(
      find.text('Changed my mind'),
      findsOneWidget,
      reason: 'the survey lists the disclosed stub reasons',
    );

    // Skipping is acknowledgment-only and closes the survey.
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(
      find.text('Mind telling us why?'),
      findsNothing,
      reason: 'skipping must close the survey',
    );
    expect(tester.takeException(), isNull, reason: 'skipping must not throw');

    await h.dispose(tester);
  });
}

/// Boots the demo world to a live accepted ride, signs the rider in, mounts a
/// GoRouter host that opens the cancel intercept (and a `/support/:id` landing
/// so the working route is assertable end-to-end), and pumps it up.
Future<_Harness> _boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final world = DemoWorld.riderScenario(
    seed: DemoSeed.seed,
    store: InMemorySnapshotStore(),
  )..restoreOrSeed();
  world.markSignedIn();
  world.submitRideRequest(
    pickupLat: DemoPlaces.railStation.lat,
    pickupLng: DemoPlaces.railStation.lng,
    dropoffLat: DemoPlaces.newCrossHospital.lat,
    dropoffLng: DemoPlaces.newCrossHospital.lng,
  );
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5)); // match beat ~4.2s
  final rideId = world.rideHistory().first.id;

  final auth = DemoAuthService(persona: DemoPersonas.rider, world: world);
  await auth.signInWithPassword(
    email: DemoSeed.riderCredentials.email,
    password: DemoSeed.riderCredentials.password,
  );

  final support = RecordingSupportRepository();

  final container = ProviderContainer(
    overrides: [
      ridesRepositoryProvider.overrideWithValue(FakeRidesRepository(world)),
      authServiceProvider.overrideWithValue(auth),
      supportRepositoryProvider.overrideWithValue(support),
    ],
  );

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => _CancelHost(rideId: rideId),
      ),
      GoRoute(
        path: '/support/:id',
        builder: (_, state) => Scaffold(
          body: Center(child: Text('ticket:${state.pathParameters['id']}')),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: HoppinTheme.riderLight(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));

  // Open the intercept.
  await tester.tap(find.text('Open cancel'));
  await tester.pump(const Duration(milliseconds: 100));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }

  return _Harness(
    world: world,
    container: container,
    rideId: rideId,
    support: support,
    router: router,
  );
}

/// A trivial host with a button that opens the cancel intercept — mirrors the
/// trip screen's cancel entry without pulling the whole trip riblet in.
class _CancelHost extends StatelessWidget {
  const _CancelHost({required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCancelIntercept(context, rideId: rideId),
            child: const Text('Open cancel'),
          ),
        ),
      ),
    );
  }
}

class _Harness {
  _Harness({
    required this.world,
    required this.container,
    required this.rideId,
    required this.support,
    required this.router,
  });

  final DemoWorld world;
  final ProviderContainer container;
  final String rideId;
  final RecordingSupportRepository support;
  final GoRouter router;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    container.dispose();
    world.reset();
  }
}
