// View layer for the rider map riblet (riblet testing contract, DOCS/05):
// the MAP-03 ladder RENDERS — hidden keeps the exact map-less trip body
// (regression lock for live mode today), routeOnly draws pins + polyline
// with no car, liveTracking glides the car marker (never-teleport smoke at
// the view level) — plus the follow-pause/recenter choreography and both
// themes pumping clean.
//
// Bounded pumps ONLY — the marker tween and camera eases never settle.
// Tile HTTP is intercepted at the dart:io HttpClient layer (see
// test/support/tile_http_fakes.dart) because nothing under apps/ may import
// maplibre_gl to build a stub TileProvider (Phase 6 isolation gate).
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/map/map_builder.dart';
import 'package:hoppin_rider/features/trip/map/map_view.dart';
import 'package:hoppin_rider/features/trip/trip_screen.dart';
import 'package:hoppin_rider/features/trip/widgets/seam_unavailable_states.dart';
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

  testWidgets(
      'hidden rung: NO map in the tree — the exact map-less trip body '
      'renders (live-mode regression lock)', (tester) async {
    await _pumpTrip(tester, repo: _GeoStubRepo()); // both seams null

    // Stays hidden across further polls — no flicker into map mode.
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(HopMap), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.text('Your trip'), findsOneWidget,
        reason: 'the map-less layout keeps its AppBar shell');
    expect(find.byType(TripFlowContent), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets(
      'routeOnly rung: HopMap with pickup/destination pins + track, no car '
      'marker, trip content riding the draggable card', (tester) async {
    await _pumpTrip(tester, repo: _GeoStubRepo(geo: _geo));

    expect(find.byType(HopMap), findsOneWidget);
    final map = tester.widget<HopMap>(find.byType(HopMap));
    expect(map.pins, hasLength(2));
    expect(map.pins.first.role, HopMapPinRole.pickup);
    expect(map.pins.last.role, HopMapPinRole.destination);
    expect(map.track, isNotNull);
    expect(map.carPosition, isNull);
    expect(find.byKey(HopMap.carMarkerKey), findsNothing);

    // The same TripFlowContent — never forked — inside the bottom card, over
    // the full-bleed canvas. Under the active-trip lock the map-exit chip is
    // intentionally GONE during active phases: an Uber-style app is captive to
    // the trip while a ride is live, so there is no minimise/Home escape here —
    // only trip completion or the explicit Cancel leave the trip.
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(TripFlowContent), findsOneWidget);
    expect(find.text('Your trip'), findsNothing);
    expect(find.byTooltip('Home'), findsNothing);

    await _unmount(tester);
  });

  // ── #41/#17: the routeOnly rung DISCLOSES, it does not just go quiet ─────
  //
  // routeOnly means: route + pins render, driver-location answered nothing, so
  // the car marker is dark. That hide used to be SILENT — the rider watched a
  // map with no car and was told nothing. RouteOnlyMapState was registered as
  // the disclosure and was constructed by ZERO production files. These pin the
  // mount on the REAL degrade branch, in the real view.
  testWidgets(
      'routeOnly rung: the #41/#17 disclosure is MOUNTED on the real map — '
      'the silent no-car hide is disclosed, not just quiet', (tester) async {
    await _pumpTrip(tester, repo: _GeoStubRepo(geo: _geo)); // no positions

    final notice = find.byType(RouteOnlyMapState);
    expect(notice, findsOneWidget,
        reason: 'the driver-location seam answered null: the rider must be '
            'told live tracking is unavailable, not left staring at a map '
            'with no car and no reason');
    // The disclosure is a real, visible surface — never a collapsed box.
    final size = tester.getSize(notice);
    expect(size.width, greaterThan(0),
        reason: 'the disclosure must have real width');
    expect(size.height, greaterThan(0),
        reason: 'the disclosure must have real height');

    // It must NOT obscure the map or the trip card (locked anatomy): the map
    // still renders under it, and the trip content still rides the card.
    expect(find.byType(HopMap), findsOneWidget,
        reason: 'the notice is an overlay, never a replacement for the map');
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(TripFlowContent), findsOneWidget);

    // It rides the TOP band: it clears the trip card's collapsed rim entirely,
    // so it can never collide with the card or with the recenter chip that
    // floats just above that rim.
    final screen = tester.getSize(find.byType(TripScreen));
    final noticeBottom = tester.getBottomLeft(notice).dy;
    final cardTop = screen.height * (1 - kTripSheetMinExtent);
    expect(noticeBottom, lessThan(cardTop),
        reason: 'the disclosure must sit above the trip card rim (and the '
            'recenter chip lane over it) — never obscuring either');

    // The disclosure is inset from the left (it once shared that lane with the
    // map exit chip). Under the active-trip lock the exit chip is gone during
    // active phases — the trip is captive — so there is no Home affordance to
    // survive the overlay; the disclosure simply coexists with the map + card.
    expect(tester.getTopLeft(notice).dx, greaterThan(0),
        reason: 'the disclosure is inset from the left');
    expect(find.byTooltip('Home'), findsNothing,
        reason: 'the active-trip lock removes the map exit chip: no escape '
            'from a live trip except completion or explicit Cancel');

    await _unmount(tester);
  });

  testWidgets(
      'liveTracking rung: the disclosure is GONE — the marker is live, there '
      'is nothing to disclose', (tester) async {
    final repo = _GeoStubRepo(
      geo: _geo,
      positions: [_pos(52.5880, -2.1210, heading: 95)],
    );
    await _pumpTrip(tester, repo: repo);

    expect(find.byKey(HopMap.carMarkerKey), findsOneWidget,
        reason: 'precondition: the marker is live on this rung');
    expect(find.byType(RouteOnlyMapState), findsNothing,
        reason: 'the disclosure is driven by the REAL ladder rung — it must '
            'never render when live tracking is actually working');

    await _unmount(tester);
  });

  testWidgets(
      'hidden rung: no disclosure either — the map view is unmounted, the '
      'map-less layout is the designed rung', (tester) async {
    await _pumpTrip(tester, repo: _GeoStubRepo()); // both seams null
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(RouteOnlyMapState), findsNothing,
        reason: 'the hidden rung has no map surface to disclose ON — the '
            'map-less layout IS its designed state');

    await _unmount(tester);
  });

  testWidgets(
      'liveTracking rung: the car marker is present and GLIDES between '
      'samples — never-teleport smoke at the view level', (tester) async {
    final repo = _GeoStubRepo(
      geo: _geo,
      positions: [
        _pos(52.5880, -2.1210, heading: 95),
        _pos(52.5884, -2.1205, heading: 92), // ~55 m — under the snap rule
      ],
    );
    await _pumpTrip(tester, repo: repo);

    expect(find.byKey(HopMap.carMarkerKey), findsOneWidget);

    // The next 1 Hz poll absorbs the second sample and the tween retargets;
    // half a sample interval later the lat/lng has visibly advanced.
    // (The marker renders in a Center overlay so screen coordinates are
    // constant; check the widget's own lat/lng fields as the unit test does.)
    await tester.pump(const Duration(seconds: 1));
    final markerBefore =
        tester.widget<HopMapCarMarker>(find.byKey(HopMap.carMarkerKey));
    await tester.pump(const Duration(milliseconds: 500));
    final markerAfter =
        tester.widget<HopMapCarMarker>(find.byKey(HopMap.carMarkerKey));
    expect(markerAfter.lat, isNot(equals(markerBefore.lat)),
        reason: 'the marker must glide toward the new sample, not sit '
            'still (and never jump only on the sample beat)');

    await _unmount(tester);
  });

  testWidgets(
      'a map gesture pauses follow and raises the recenter chip; tapping '
      'the chip restores follow and hides it', (tester) async {
    final repo = _GeoStubRepo(
      geo: _geo,
      positions: [_pos(52.5880, -2.1210, heading: 95)],
    );
    await _pumpTrip(tester, repo: repo);
    expect(find.text('Recenter'), findsNothing);

    // Pan on the map region (clear of the exit chip and the bottom card).
    await tester.dragFrom(const Offset(400, 200), const Offset(-80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // 100ms fade in
    expect(find.text('Recenter'), findsOneWidget,
        reason: 'a user gesture must pause camera-follow and offer the '
            'way back');

    await tester.tap(find.text('Recenter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // 100ms fade out
    expect(find.text('Recenter'), findsNothing,
        reason: 'the chip resumes follow and stands down');

    await _unmount(tester);
  });

  testWidgets('light theme: map mode pumps without exceptions, attribution '
      'visible', (tester) async {
    final repo = _GeoStubRepo(
      geo: _geo,
      positions: [_pos(52.5880, -2.1210, heading: 95)],
    );
    await _pumpTrip(tester, repo: repo);

    expect(find.byType(HopMap), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });

  testWidgets('dark theme: map mode pumps without exceptions (dark tiles '
      'path), attribution visible', (tester) async {
    final repo = _GeoStubRepo(
      geo: _geo,
      positions: [_pos(52.5880, -2.1210, heading: 95)],
    );
    await _pumpTrip(tester, repo: repo, theme: _dark);

    expect(find.byType(HopMap), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _unmount(tester);
  });
}

// One ThemeData per mode, reused across every pump (04-02 test-harness
// trap: a fresh instance restarts AnimatedTheme mid-assertion).
final _light = HoppinTheme.riderLight();
final _dark = HoppinTheme.riderDark();

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
  ThemeData? theme,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ridesRepositoryProvider.overrideWithValue(repo),
      // Suppress MapLibreMap platform view so tests run headlessly.
      mapTileProvider.overrideWithValue('no-network'),
    ],
    child: MaterialApp(
      theme: theme ?? _light,
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

/// Hand-fed seam stub: geo + a position queue (the last sample repeats), a
/// ride row for the sibling trip interactor. No world, no timers.
class _GeoStubRepo implements RidesRepository {
  _GeoStubRepo({this.geo, List<DriverPosition> positions = const []})
      : _queue = List.of(positions);

  final RideGeo? geo;
  final List<DriverPosition> _queue;
  DriverPosition? _last;

  @override
  Future<DriverPosition?> driverPosition(String rideId) async {
    if (_queue.isNotEmpty) {
      _last = _queue.removeAt(0);
    }
    return _last;
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
