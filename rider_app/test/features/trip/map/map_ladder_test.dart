// TRIP-02 — the map seam ladder as an explicit REGRESSION LOCK (Lane C,
// 10-VALIDATION). Three DESIGNED rungs recompute per poll from what the geo
// capability seams actually answered:
//
//   hidden        both seams null (LIVE TODAY: #17/#41 unshipped) — no map,
//                 the trip screen keeps its exact map-less body.
//   routeOnly     rideGeo present, driverPosition null — pickup/destination
//                 pins + route polyline, and ABSOLUTELY NO car marker.
//   liveTracking  a driverPosition sample present — the tweened car marker
//                 lights up with ZERO view change (the #41 body-swap).
//
// The load-bearing assertion is the NO-FAKE-CAR contract (locked decision 4):
// the hidden and routeOnly rungs must never carry a seeded/decorative marker.
// `driverPosition` returning null IS the correct live behaviour; the map
// degrades honestly to route-only until GET /rides/:id/driver-location (#41)
// ships. A fake car on the live path is exactly what this test forbids.
//
// This exercises the REAL TripScreen over a stubbed repo — the production
// shell decision (map-less vs map mode) and the real map interactor's 1 Hz
// ladder, not a hand-driven mock. It may pass green on the already-built
// ladder (that is the regression lock this lane owns); a red rung pinpoints a
// real ladder defect.
//
// Isolation gate (Phase 6): nothing under apps/ may import maplibre_gl, so the
// no-tile-HTTP seam here is dart:io's HttpClient (TileHttpOverrides). The
// hoppin_ui-side hop_map_test.dart owns the tileProvider-sentinel marker
// tween/snap proofs. Bounded pumps only — the
// marker tween and camera eases never settle, so pumpAndSettle would hang.
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/map/map_builder.dart';
import 'package:hoppin_rider/features/trip/trip_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../../support/tile_http_fakes.dart';

void main() {
  HttpOverrides? previousOverrides;

  setUpAll(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = TileHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = previousOverrides;
  });

  group('TRIP-02 map ladder — hidden / routeOnly / liveTracking', () {
    testWidgets(
        'RUNG 1 hidden: both seams null — NO map mounts and NO car marker '
        'anywhere (the live-today degrade)', (tester) async {
      await _pumpTrip(tester, repo: _LadderStubRepo()); // both seams null

      // Stays hidden across further polls — never flickers into map mode.
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(HopMap), findsNothing,
          reason: 'both seams null keeps the exact map-less trip body');
      expect(find.byKey(HopMap.carMarkerKey), findsNothing,
          reason: 'NO fake/seeded car on the hidden rung (decision 4)');

      await _unmount(tester);
    });

    testWidgets(
        'RUNG 2 routeOnly: rideGeo present, driverPosition null — route + '
        'pickup/destination pins, and NO car marker (honest degrade)',
        (tester) async {
      await _pumpTrip(tester, repo: _LadderStubRepo(geo: _geo));

      final map = tester.widget<HopMap>(find.byType(HopMap));
      expect(map.track, isNotNull, reason: 'the route polyline is always shown');
      expect(map.pins, hasLength(2));
      expect(map.pins.first.role, HopMapPinRole.pickup);
      expect(map.pins.last.role, HopMapPinRole.destination);

      // THE no-fake-car contract: a null driverPosition seam must degrade to
      // route-only, never conjure a decorative marker.
      expect(map.carPosition, isNull,
          reason: 'driverPosition null must NOT be faked into a position');
      expect(find.byKey(HopMap.carMarkerKey), findsNothing,
          reason: 'routeOnly shows route + pins ONLY — no seeded car '
              '(decision 4: never a fake car on the live path)');

      // Sustained nulls stay on routeOnly — no late flicker into a fake car.
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(HopMap.carMarkerKey), findsNothing);

      await _unmount(tester);
    });

    testWidgets(
        'RUNG 3 liveTracking: a driverPosition sample present — the car '
        'marker lights up with the route still shown (the #41 body-swap)',
        (tester) async {
      final repo = _LadderStubRepo(
        geo: _geo,
        positions: [_pos(52.5880, -2.1210, heading: 95)],
      );
      await _pumpTrip(tester, repo: repo);

      final map = tester.widget<HopMap>(find.byType(HopMap));
      expect(map.carPosition, const HopGeoPoint(52.5880, -2.1210),
          reason: 'a real seam sample flows straight into the marker input');
      expect(map.track, isNotNull, reason: 'the route stays shown under the car');
      expect(find.byKey(HopMap.carMarkerKey), findsOneWidget,
          reason: 'the marker lights up when — and only when — a real sample '
              'arrives, with zero view change');

      await _unmount(tester);
    });

    testWidgets(
        'the ladder RECOMPUTES per poll: a sample dropping to null steps '
        'liveTracking back DOWN to routeOnly (no lingering fake car)',
        (tester) async {
      // One real sample, then the seam answers null — the honest live
      // downgrade the day a driver-location read blips out.
      final repo = _LadderStubRepo(
        geo: _geo,
        positions: [_pos(52.5880, -2.1210, heading: 95)],
        positionsThenNull: true,
      );
      await _pumpTrip(tester, repo: repo);

      expect(find.byKey(HopMap.carMarkerKey), findsOneWidget,
          reason: 'the first real sample lit the marker');

      // The next 1 Hz poll answers null (honest data, not a failure): the
      // ladder steps down and the marker input clears — no lingering car.
      await tester.pump(const Duration(seconds: 1));
      final map = tester.widget<HopMap>(find.byType(HopMap));
      expect(map.carPosition, isNull,
          reason: 'a null sample must clear the marker input, never freeze a '
              'stale fake car in place');
      expect(map.track, isNotNull,
          reason: 'the route + pins survive the downgrade to routeOnly');

      await _unmount(tester);
    });
  });
}

// One ThemeData, reused across every pump (04-02 harness trap: a fresh
// instance restarts AnimatedTheme mid-assertion).
final _light = HoppinTheme.riderLight();

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

/// Pumps the REAL TripScreen (real map + trip interactors) over the stub
/// repo — the shell decision (map-less vs map mode) is exactly production's.
Future<void> _pumpTrip(
  WidgetTester tester, {
  required RidesRepository repo,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ridesRepositoryProvider.overrideWithValue(repo),
      // Suppress MapLibreMap platform view so tests run headlessly.
      mapTileProvider.overrideWithValue('no-network'),
    ],
    child: MaterialApp(
      theme: _light,
      home: const TripScreen(rideId: 'ride-1'),
    ),
  ));
  // The immediate seam poll lands, the shell settles, tiles resolve.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Unmounts the tree so every riblet timer (map 1 Hz poll, trip poll/tick)
/// dies with the provider scope before teardown's pending-timer check.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// Hand-fed seam stub: geo + a position queue. `positionsThenNull` answers
/// null once the queue is exhausted (the honest live downgrade); otherwise
/// the last sample repeats. getRide serves the sibling trip interactor.
class _LadderStubRepo implements RidesRepository {
  _LadderStubRepo({
    this.geo,
    List<DriverPosition> positions = const [],
    this.positionsThenNull = false,
  }) : _queue = List.of(positions);

  final RideGeo? geo;
  final bool positionsThenNull;
  final List<DriverPosition> _queue;
  DriverPosition? _last;

  @override
  Future<DriverPosition?> driverPosition(String rideId) async {
    if (_queue.isNotEmpty) {
      _last = _queue.removeAt(0);
      return _last;
    }
    return positionsThenNull ? null : _last;
  }

  @override
  Future<RideGeo?> rideGeo(String rideId) async => geo;

  @override
  Future<Ride> getRide(String id) async =>
      Ride(id: id, riderId: 'rider-1', status: RideStatus.accepted);

  @override
  Future<RideDriverInfo?> driverInfo(String rideId) async => null;

  @override
  Future<List<Ride>> history({int limit = 50}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
