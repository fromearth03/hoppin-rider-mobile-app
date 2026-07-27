import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_demo/hoppin_demo.dart';
import 'package:hoppin_rider/features/booking/booking_builder.dart';
import 'package:hoppin_rider/features/booking/booking_interactor.dart';
import 'package:hoppin_rider/features/booking/booking_state.dart';
import 'package:hoppin_rider/features/booking/place.dart';
import 'package:hoppin_rider/features/booking/widgets/ride_type_selector.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// BOOK-02 (SL-1): the ride-type selector is a DISCLOSED STATIC seam — a
/// config-driven [Standard, XL, Accessibility] list, never a live-list fetch.
/// Selecting a class threads its `vehicleCategoryId` through the interactor's
/// estimate + request calls (both already accept the param on `:8080`), and a
/// category change re-runs the estimate so the fare reflects the class.
///
/// Two layers, per the riblet testing contract (DOCS/05):
///   • widget — the dumb selector renders the static three and emits the id;
///   • interactor — setCategory re-estimates + threads the id, guarded mid-flight.
void main() {
  // ── Widget layer: the dumb static selector ─────────────────────────────
  group('RideTypeSelector (static SL-1 list)', () {
    Widget host(Widget child) => MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    Future<void> pumpBounded(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('renders exactly three static options — Standard, XL, '
        'Accessibility — with no network', (tester) async {
      await tester.pumpWidget(
        host(RideTypeSelector(selectedCategory: null, onSelect: (_) {})),
      );
      await pumpBounded(tester);

      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('XL'), findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);

      // Exactly three — the static config list, never a fourth from a fetch.
      expect(find.byType(RideTypeCard), findsNWidgets(3));
    });

    testWidgets('the static list is drawn from config ids, not the network',
        (tester) async {
      // The config exposes the three options synchronously — proof this is a
      // static seam, not a live-list read.
      expect(kRideTypeOptions, hasLength(3));
      expect(kRideTypeOptions.map((o) => o.label).toList(),
          ['Standard', 'XL', 'Accessibility']);
      // Standard is the server default — its id is null (disclosed SL-1).
      expect(kRideTypeOptions.first.id, isNull,
          reason: 'Standard defaults server-side; a null id ships the SL-1 '
              'seam honestly rather than faking a category uuid');
    });

    // WAVE-0 REWRITE (2026-07-12): this asserted that tapping XL emits the XL
    // category id — an id that was FABRICATED and is not in the database. The
    // test was green while proving the app sent the server a category it has
    // never seen. XL and Accessibility are now inert until #65 ships.
    testWidgets('tapping XL emits NOTHING — an unbookable class is inert',
        (tester) async {
      String? emitted = 'unset';
      await tester.pumpWidget(
        host(RideTypeSelector(
          selectedCategory: null,
          onSelect: (id) => emitted = id,
        )),
      );
      await pumpBounded(tester);

      final xl = find.text('XL');
      await tester.ensureVisible(xl);
      await tester.pump();
      await tester.tap(xl);
      await pumpBounded(tester);

      expect(emitted, 'unset',
          reason: 'XL carries no real vehicle_category_id (no '
              'GET /vehicle-categories — #65), so the app must emit NOTHING '
              'rather than invent an id the server has never seen. Especially '
              'for Accessibility: a wheelchair user must get an accessible '
              'vehicle or be told plainly they cannot book one here yet.');
      expect(
        kRideTypeOptions.firstWhere((o) => o.label == 'XL').bookable,
        isFalse,
        reason: 'XL stays visible (it is a real product) but not bookable',
      );
    });
  });

  // ── Interactor layer: threading + re-estimate + mid-flight guard ────────
  group('BookingInteractor category threading', () {
    test('setCategory re-runs the estimate with the chosen vehicleCategoryId',
        () {
      FakeAsync().run((async) {
        final h = _Harness();

        h.interactor.setPickup(_railStation);
        h.interactor.setDropoff(_newCross);
        async.flushMicrotasks();
        expect(h.state.phase, BookingPhase.estimated);
        expect(h.repo.estimateCategoryLog.last, isNull,
            reason: 'the first estimate carries no category (Standard)');

        final xlOption = kRideTypeOptions.firstWhere((o) => o.label == 'XL');
        h.interactor.setCategory(xlOption.id);
        async.flushMicrotasks();

        expect(h.state.selectedCategory, xlOption.id);
        expect(h.state.phase, BookingPhase.estimated,
            reason: 'a category change re-estimates like setPickup/setDropoff');
        expect(h.repo.estimateCategoryLog.last, xlOption.id,
            reason: 're-estimate must thread the chosen class id');

        h.dispose();
      });
    });

    test('requestRide carries the selected vehicleCategoryId', () {
      FakeAsync().run((async) {
        final h = _Harness();

        h.interactor.setPickup(_railStation);
        h.interactor.setDropoff(_newCross);
        async.flushMicrotasks();

        final xlOption = kRideTypeOptions.firstWhere((o) => o.label == 'XL');
        h.interactor.setCategory(xlOption.id);
        async.flushMicrotasks();
        expect(h.state.phase, BookingPhase.estimated);

        unawaited(h.interactor.requestRide());
        async.flushMicrotasks();
        expect(h.state.phase, BookingPhase.searching);
        expect(h.repo.requestCategoryLog.last, xlOption.id,
            reason: 'the same class id must ride the request');

        h.interactor.cancelSearch();
        h.dispose();
      });
    });

    test('a category change while a request is in flight is guarded', () {
      FakeAsync().run((async) {
        final h = _Harness()..driveToSearching(async);
        expect(h.state.phase, BookingPhase.searching);
        final before = h.state.selectedCategory;

        // Mirror the _setPlaces lock: category changes are ignored while a
        // request/search is in flight (no silent re-estimate, no state churn).
        final xlOption = kRideTypeOptions.firstWhere((o) => o.label == 'XL');
        h.interactor.setCategory(xlOption.id);
        async.flushMicrotasks();

        expect(h.state.phase, BookingPhase.searching,
            reason: 'a mid-request category change must not disturb the search');
        expect(h.state.selectedCategory, before,
            reason: 'the category is locked while requesting/searching');

        h.interactor.cancelSearch();
        h.dispose();
      });
    });
  });
}

/// Live-shape delegate over the demo world that records the
/// `vehicleCategoryId` threaded into estimate + request.
class _RecordingCategoryRepo extends FakeRidesRepository {
  _RecordingCategoryRepo(super.world);

  final List<String?> estimateCategoryLog = [];
  final List<String?> requestCategoryLog = [];

  @override
  Future<FareEstimate> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) {
    estimateCategoryLog.add(vehicleCategoryId);
    return super.estimate(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      vehicleCategoryId: vehicleCategoryId,
    );
  }

  @override
  Future<String> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? vehicleCategoryId,
  }) {
    requestCategoryLog.add(vehicleCategoryId);
    return super.requestRide(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      vehicleCategoryId: vehicleCategoryId,
    );
  }
}

const _railStation = Place(
  label: 'Wolverhampton Rail Station',
  lat: 52.5877,
  lng: -2.1200,
);
const _newCross = Place(
  label: 'New Cross Hospital',
  lat: 52.6046,
  lng: -2.0930,
);

class _Harness {
  _Harness() {
    world = DemoWorld.riderScenario(
      seed: DemoSeed.seed,
      store: InMemorySnapshotStore(),
    )..restoreOrSeed();
    repo = _RecordingCategoryRepo(world);
    container = ProviderContainer(overrides: [
      // riderDemoOverrides already overrides ridesRepositoryProvider with a
      // FakeRidesRepository; spreading it here AND adding the recording repo
      // double-overrides the same provider (Riverpod asserts). This is a
      // repo-level interactor unit test — override only the rides repo, the
      // same idiom the sibling scheduled_test uses.
      ridesRepositoryProvider.overrideWithValue(repo),
    ]);
    sub = container.listen(bookingInteractorProvider, (_, _) {});
  }

  late final DemoWorld world;
  late final _RecordingCategoryRepo repo;
  late final ProviderContainer container;
  late final ProviderSubscription<BookingState> sub;

  BookingState get state => container.read(bookingInteractorProvider);

  BookingInteractor get interactor =>
      container.read(bookingInteractorProvider.notifier);

  void driveToSearching(FakeAsync async) {
    interactor.setPickup(_railStation);
    interactor.setDropoff(_newCross);
    async.flushMicrotasks();
    expect(state.phase, BookingPhase.estimated);
    unawaited(interactor.requestRide());
    async.flushMicrotasks();
    expect(state.phase, BookingPhase.searching);
  }

  void dispose() {
    sub.close();
    container.dispose();
    world.reset();
  }
}
