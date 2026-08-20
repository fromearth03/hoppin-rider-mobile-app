import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/scheduled/schedule_picker.dart';
import 'package:hoppin_rider/features/scheduled/scheduled_builder.dart';
import 'package:hoppin_rider/features/scheduled/scheduled_screen.dart';
import 'package:hoppin_rider/features/scheduled/scheduled_state.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// BOOK-03: scheduled rides are BOUND over the existing repo methods
/// (`POST /scheduled-rides` + `GET /scheduled-rides`). Two obligations:
///   • the picker enforces the contract's ≥30-minute floor client-side
///     (rides_repository.dart:159) with plain-English copy — a <30-min pick
///     is rejected, a ≥30-min pick is accepted and confirms;
///   • the list renders `scheduledRides()`, and a not-found lookup (gap #22 →
///     live 500) surfaces through `friendlyErrorMessage`, never a raw crash.
///
/// Time math runs under a fixed [clock] so the ≥30-min floor is deterministic.
void main() {
  // A fixed wall clock — the ≥30-min floor is measured against this.
  final fixedNow = DateTime(2026, 7, 11, 9, 0);

  group('SchedulePicker ≥30-min floor', () {
    test('a pickup <30 minutes out is rejected by the floor rule', () {
      withClock(Clock.fixed(fixedNow), () {
        // 29 minutes out — under the floor.
        final tooSoon = fixedNow.add(const Duration(minutes: 29));
        expect(isValidScheduleTime(tooSoon), isFalse,
            reason: 'the contract floor is ≥30 minutes ahead');
        // The rejection carries plain-English copy, not a raw error.
        expect(scheduleFloorMessage,
            contains('30'),
            reason: 'the rider is told the 30-minute rule in words');
      });
    });

    test('a pickup ≥30 minutes out is accepted', () {
      withClock(Clock.fixed(fixedNow), () {
        final ok = fixedNow.add(const Duration(minutes: 30));
        expect(isValidScheduleTime(ok), isTrue);
        final later = fixedNow.add(const Duration(hours: 3));
        expect(isValidScheduleTime(later), isTrue);
      });
    });

    testWidgets('picker disables submit for a <30-min selection and enables '
        'it for a valid one', (tester) async {
      await withClock(Clock.fixed(fixedNow), () async {
        DateTime? confirmed;
        await tester.pumpWidget(MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: Scaffold(
            body: SchedulePicker(
              // Seed an invalid selection (10 min out) so the CTA is disabled.
              initialSelection: fixedNow.add(const Duration(minutes: 10)),
              onConfirm: (when) => confirmed = when,
            ),
          ),
        ));
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        final cta = find.byType(HopButton);
        expect(cta, findsOneWidget);
        // Disabled while the selection is under the floor.
        expect(tester.widget<HopButton>(cta).onPressed, isNull,
            reason: 'submit is disabled while the pick is under the 30-min floor');
        // The floor copy is on screen.
        expect(find.textContaining('30'), findsWidgets);
        expect(confirmed, isNull);
      });
    });

    testWidgets('a valid selection confirms with the chosen time',
        (tester) async {
      await withClock(Clock.fixed(fixedNow), () async {
        DateTime? confirmed;
        final valid = fixedNow.add(const Duration(hours: 2));
        await tester.pumpWidget(MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: Scaffold(
            body: SchedulePicker(
              initialSelection: valid,
              onConfirm: (when) => confirmed = when,
            ),
          ),
        ));
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        final cta = find.byType(HopButton);
        expect(tester.widget<HopButton>(cta).onPressed, isNotNull,
            reason: 'a ≥30-min selection enables the confirm CTA');
        await tester.ensureVisible(cta);
        await tester.pump();
        await tester.tap(cta);
        await tester.pump(const Duration(milliseconds: 100));

        expect(confirmed, valid);
      });
    });
  });

  group('ScheduledInteractor over the repo', () {
    test('create calls createScheduledRide with the chosen pickup time', () {
      final repo = _RecordingScheduledRepo();
      final container = ProviderContainer(overrides: [
        ridesRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(scheduledInteractorProvider, (_, _) {});
      addTearDown(sub.close);

      final interactor =
          container.read(scheduledInteractorProvider.notifier);
      final when = DateTime(2026, 7, 11, 12, 0);

      return interactor
          .create(
        pickupLat: 52.5877,
        pickupLng: -2.1200,
        dropoffLat: 52.6046,
        dropoffLng: -2.0930,
        requestedPickupTime: when,
      )
          .then((_) {
        expect(repo.createdTimes, [when],
            reason: 'the create flow binds to createScheduledRide');
        final state = container.read(scheduledInteractorProvider);
        expect(state.phase, ScheduledPhase.ready);
      });
    });

    test('load renders the scripted scheduledRides list', () {
      final repo = _RecordingScheduledRepo();
      final container = ProviderContainer(overrides: [
        ridesRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(scheduledInteractorProvider, (_, _) {});
      addTearDown(sub.close);

      final interactor =
          container.read(scheduledInteractorProvider.notifier);
      return interactor.load().then((_) {
        final state = container.read(scheduledInteractorProvider);
        expect(state.phase, ScheduledPhase.ready);
        expect(state.rides, hasLength(1));
        expect(state.rides.first.id, 'sched-seed-1');
      });
    });

    test('cancel calls the scheduled cancellation endpoint and refreshes', () {
      final repo = _RecordingScheduledRepo();
      final container = ProviderContainer(overrides: [
        ridesRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(scheduledInteractorProvider, (_, _) {});
      addTearDown(sub.close);

      final interactor =
          container.read(scheduledInteractorProvider.notifier);
      return interactor.cancel('sched-seed-1').then((_) {
        expect(repo.cancelledIds, ['sched-seed-1']);
        expect(container.read(scheduledInteractorProvider).phase,
            ScheduledPhase.ready);
      });
    });

    test('a not-found lookup surfaces via friendlyErrorMessage, not a raw 500',
        () {
      final repo = _RecordingScheduledRepo();
      final container = ProviderContainer(overrides: [
        ridesRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(scheduledInteractorProvider, (_, _) {});
      addTearDown(sub.close);

      final interactor =
          container.read(scheduledInteractorProvider.notifier);
      return interactor.fetchOne('does-not-exist').then((_) {
        final state = container.read(scheduledInteractorProvider);
        expect(state.phase, ScheduledPhase.error);
        expect(state.error, isNotNull);
        // The raw gap-#22 500 body must never reach the rider.
        expect(state.error, isNot(contains('500')));
        expect(state.error, isNot(contains('INTERNAL')));
      });
    });
  });

  group('ScheduledScreen', () {
    testWidgets('renders the scheduled-rides list from the repo',
        (tester) async {
      final repo = _RecordingScheduledRepo();
      final container = ProviderContainer(overrides: [
        ridesRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: const ScheduledScreen(),
        ),
      ));
      // Bounded pumps — never pumpAndSettle.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The seeded scheduled ride renders as a row (its pickup-time label).
      expect(find.byType(ScheduledScreen), findsOneWidget);
      expect(find.byType(HopCard), findsWidgets);
    });
  });
}

/// A repo-level fake for the scheduled surface: records created times, serves
/// one scripted scheduled ride, and throws the gap-#22 not-found shape.
class _RecordingScheduledRepo implements RidesRepository {
  final List<DateTime> createdTimes = [];
  final List<String> cancelledIds = [];

  static final _seed = ScheduledRide(
    id: 'sched-seed-1',
    riderId: 'rider-x',
    requestedPickupTime: DateTime(2026, 7, 12, 8, 30),
  );

  @override
  Future<ScheduledRide> createScheduledRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required DateTime requestedPickupTime,
    String? estimatedFareId,
  }) async {
    createdTimes.add(requestedPickupTime);
    return ScheduledRide(
      id: 'sched-new-1',
      riderId: 'rider-x',
      requestedPickupTime: requestedPickupTime,
    );
  }

  @override
  Future<List<ScheduledRide>> scheduledRides() async => [_seed];

  @override
  Future<void> cancelScheduledRide(String id) async {
    cancelledIds.add(id);
  }

  @override
  Future<ScheduledRide> scheduledRide(String id) async {
    throw const ApiException(
      statusCode: 500,
      message: 'INTERNAL',
      code: 'INTERNAL',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
