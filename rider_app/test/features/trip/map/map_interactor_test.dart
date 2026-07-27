import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/map/map_builder.dart';
import 'package:hoppin_rider/features/trip/map/map_state.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

/// Interactor unit layer (riblet testing contract, DOCS/05) for the rider
/// map riblet brain: the MAP-03 degradation ladder as FIRST-CLASS state
/// (hidden / routeOnly / liveTracking — never an error state), the 1 Hz
/// seam poll hygiene (driverPosition per tick, rideGeo memoized after one
/// success), trip-phase → declarative camera-intent mapping, the stale-async
/// generation guard, and transient-throw tolerance — all against a
/// hand-rolled stubbed RidesRepository under FakeAsync.
void main() {
  const pickup = HopGeoPoint(52.5877, -2.1200);
  const destination = HopGeoPoint(52.6046, -2.0930);

  test('both seams null -> MapPhase.hidden, a first-class state', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo();
      final h = _Harness(async, repo);

      expect(h.state.phase, MapPhase.hidden);
      expect(h.state.pins, isEmpty);
      expect(h.state.track, isNull);
      expect(h.state.carPosition, isNull);
      expect(h.state.cameraIntent, isNull);

      // Sustained nulls stay hidden — no error, no crash, poll keeps going.
      async.elapse(const Duration(seconds: 3));
      expect(h.state.phase, MapPhase.hidden);

      h.dispose();
    });
  });

  test('rideGeo only -> routeOnly: pickup/destination pins + trip polyline, '
      'no car', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(geo: _geo);
      final h = _Harness(async, repo);

      expect(h.state.phase, MapPhase.routeOnly);
      expect(h.state.carPosition, isNull);
      expect(h.state.carHeading, isNull);
      expect(h.state.pins, hasLength(2));
      expect(h.state.pins.first, const HopMapPin(pickup, HopMapPinRole.pickup));
      expect(h.state.pins.last,
          const HopMapPin(destination, HopMapPinRole.destination));
      expect(h.state.track, isNotNull);
      expect(h.state.track!.points.length, _geo.route.length);
      expect(h.state.track!.points.first, pickup);
      expect(h.state.track!.points.last, destination);

      h.dispose();
    });
  });

  test('both seams present -> liveTracking with position + heading flowing '
      'each 1 Hz tick', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(
        geo: _geo,
        positions: [
          _pos(52.5880, -2.1210, heading: 95),
          _pos(52.5884, -2.1205, heading: 80),
          _pos(52.5888, -2.1201, heading: 70),
        ],
      );
      final h = _Harness(async, repo);

      expect(h.state.phase, MapPhase.liveTracking);
      expect(h.state.carPosition, const HopGeoPoint(52.5880, -2.1210));
      expect(h.state.carHeading, 95);

      async.elapse(const Duration(seconds: 1));
      expect(h.state.carPosition, const HopGeoPoint(52.5884, -2.1205));
      expect(h.state.carHeading, 80);

      async.elapse(const Duration(seconds: 1));
      expect(h.state.carPosition, const HopGeoPoint(52.5888, -2.1201));
      expect(h.state.carHeading, 70);

      h.dispose();
    });
  });

  test('rideGeo is fetched ONCE; driverPosition polled per tick', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(
        geo: _geo,
        positions: [_pos(52.5880, -2.1210)],
      );
      final h = _Harness(async, repo);

      async.elapse(const Duration(seconds: 5));
      expect(repo.rideGeoCalls, 1,
          reason: 'static route geometry is memoized after one success');
      expect(repo.driverPositionCalls, 6,
          reason: 'immediate first poll + one per 1 Hz tick');

      h.dispose();
    });
  });

  test('camera intents follow the trip phase: approach fits driver + pickup, '
      'on-road follows the car, completed settles on the destination', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(
        geo: _geo,
        positions: [_pos(52.5880, -2.1210, heading: 95)],
      );
      final h = _Harness(async, repo);

      // Accepted -> driverEnRoute (approach): frame the car and the pickup.
      expect(
        h.state.cameraIntent,
        const FitPoints([HopGeoPoint(52.5880, -2.1210), pickup]),
      );

      // Started -> onRoad: chase the car.
      repo.status = RideStatus.started;
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.cameraIntent,
          const FollowPoint(HopGeoPoint(52.5880, -2.1210)));

      // Completed: one settle on the destination pin.
      repo.status = RideStatus.completed;
      async.elapse(const Duration(milliseconds: 3100));
      expect(h.state.cameraIntent, const SettleOn(destination));

      h.dispose();
    });
  });

  test('approach with no driver pin falls back to fitting pickup + '
      'destination (routeOnly rung)', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(geo: _geo);
      final h = _Harness(async, repo);

      expect(h.state.phase, MapPhase.routeOnly);
      expect(h.state.cameraIntent, const FitPoints([pickup, destination]));

      h.dispose();
    });
  });

  test('generation guard: dispose mid-poll — late seam responses never '
      'write state and the timer stops outright', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(
        geo: _geo,
        positions: [_pos(52.5880, -2.1210)],
        seamDelay: const Duration(milliseconds: 700),
      );
      final h = _Harness(async, repo);

      // The immediate first poll is in flight (delayed 700ms). Dispose now.
      expect(repo.driverPositionCalls, 1);
      async.elapse(const Duration(milliseconds: 100));
      h.dispose();

      // The late response lands after dispose: the gen != _generation guard
      // must discard it (an unguarded write on a disposed notifier throws),
      // and the cancelled timer must never poll again.
      async.elapse(const Duration(seconds: 3));
      expect(repo.driverPositionCalls, 1,
          reason: 'disposal must cancel the 1 Hz poll loop outright');
    });
  });

  test('a seam throw is swallowed into the last-known state; the ladder '
      'only downgrades on honest nulls', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(
        geo: _geo,
        positions: [
          _pos(52.5880, -2.1210, heading: 95),
          _pos(52.5884, -2.1205, heading: 80),
        ],
      );
      final h = _Harness(async, repo);
      expect(h.state.phase, MapPhase.liveTracking);
      expect(h.state.carPosition, const HopGeoPoint(52.5880, -2.1210));

      // Transient blip: the map stays up, showing the last-known sample.
      repo.throwNext = true;
      async.elapse(const Duration(seconds: 1));
      expect(h.state.phase, MapPhase.liveTracking,
          reason: 'a single seam failure must never tear the map down');
      expect(h.state.carPosition, const HopGeoPoint(52.5880, -2.1210));

      // Next tick recovers and the position flows again.
      async.elapse(const Duration(seconds: 1));
      expect(h.state.carPosition, const HopGeoPoint(52.5884, -2.1205));

      h.dispose();
    });
  });

  test('sustained null position downgrades honestly to routeOnly', () {
    FakeAsync().run((async) {
      final repo = _GeoStubRepo(
        geo: _geo,
        positions: [_pos(52.5880, -2.1210)],
        positionsThenNull: true,
      );
      final h = _Harness(async, repo);
      expect(h.state.phase, MapPhase.liveTracking);

      // The queue is exhausted -> the seam answers null (honest data, not a
      // failure) -> the ladder steps down, pins + polyline stay up.
      async.elapse(const Duration(seconds: 1));
      expect(h.state.phase, MapPhase.routeOnly);
      expect(h.state.carPosition, isNull);
      expect(h.state.pins, hasLength(2));

      h.dispose();
    });
  });
}

// ── Fixtures ──────────────────────────────────────────────────────────────

const _geo = RideGeo(
  pickupLat: 52.5877,
  pickupLng: -2.1200,
  dropoffLat: 52.6046,
  dropoffLng: -2.0930,
  route: [
    GeoPoint(lat: 52.5877, lng: -2.1200),
    GeoPoint(lat: 52.5920, lng: -2.1080),
    GeoPoint(lat: 52.6046, lng: -2.0930),
  ],
);

DriverPosition _pos(double lat, double lng, {double? heading}) =>
    DriverPosition(lat: lat, lng: lng, heading: heading, updatedAt: clock.now());

// ── Harness ───────────────────────────────────────────────────────────────

/// Boots a ProviderContainer over the stub repo and listens to the map
/// interactor (Riverpod 3 pauses unlistened providers). The sibling trip
/// interactor boots too — it polls the same stub for ride status, which is
/// how the camera-intent tests drive trip phases.
class _Harness {
  _Harness(FakeAsync async, _GeoStubRepo repo) {
    container = ProviderContainer(overrides: [
      ridesRepositoryProvider.overrideWithValue(repo),
    ]);
    sub = container.listen(mapInteractorProvider('ride-1'), (_, _) {});
    async.flushMicrotasks();
  }

  late final ProviderContainer container;
  late final ProviderSubscription<MapState> sub;

  MapState get state => container.read(mapInteractorProvider('ride-1'));

  void dispose() {
    sub.close();
    container.dispose();
  }
}

/// Hand-rolled seam stub: configurable geo/position, call counting for the
/// poll-hygiene proofs, optional per-call delay (generation guard) and a
/// one-shot throw (transient-failure tolerance). getRide serves the sibling
/// trip interactor so trip phases are drivable via [status].
class _GeoStubRepo implements RidesRepository {
  _GeoStubRepo({
    this.geo,
    List<DriverPosition> positions = const [],
    this.positionsThenNull = false,
    this.seamDelay,
  }) : _queue = List.of(positions);

  RideGeo? geo;
  RideStatus status = RideStatus.accepted;
  Duration? seamDelay;
  bool throwNext = false;

  /// When true an exhausted queue answers null; otherwise the last position
  /// keeps repeating.
  final bool positionsThenNull;

  final List<DriverPosition> _queue;
  DriverPosition? _last;

  int rideGeoCalls = 0;
  int driverPositionCalls = 0;

  @override
  Future<DriverPosition?> driverPosition(String rideId) async {
    driverPositionCalls++;
    if (throwNext) {
      throwNext = false;
      throw Exception('seam blip');
    }
    final delay = seamDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    if (_queue.isNotEmpty) {
      _last = _queue.removeAt(0);
      return _last;
    }
    return positionsThenNull ? null : _last;
  }

  @override
  Future<RideGeo?> rideGeo(String rideId) async {
    rideGeoCalls++;
    final delay = seamDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return geo;
  }

  @override
  Future<Ride> getRide(String id) async =>
      Ride(id: id, riderId: 'rider-1', status: status);

  @override
  Future<RideDriverInfo?> driverInfo(String rideId) async => null;

  @override
  Future<Receipt> receipt(String rideId) async =>
      throw Exception('no receipt in this stub');

  @override
  Future<List<Ride>> history({int limit = 50}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
