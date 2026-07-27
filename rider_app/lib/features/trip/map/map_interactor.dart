import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import '../trip_builder.dart';
import '../trip_handoff.dart';
import '../trip_state.dart';
import 'map_state.dart';

/// THE BRAIN of the rider map riblet (riblet anatomy, DOCS/05): a sibling
/// brain under the trip riblet that polls the MAP-03 geo capability seams at
/// 1 Hz — `driverPosition` every tick, `rideGeo` memoized after one success
/// — and merges the samples with the trip riblet's smart phase into pins,
/// track, car position, and a declarative camera intent. Zero Flutter widget
/// imports; the map riblet is router-free (embedded view), so there are no
/// nav intents here at all.
///
/// The degradation ladder is recomputed per poll from what the seams
/// actually answered — hidden / routeOnly / liveTracking are all designed
/// rungs, never error handling. A seam THROW is different from a seam null:
/// throws are transient (keep the last-known composition), nulls are honest
/// data (the ladder steps down).
class MapInteractor extends Notifier<MapState> {
  MapInteractor(this.rideId);

  /// The family argument: which ride this map instance tracks.
  final String rideId;

  /// Bumped on dispose/rebuild; in-flight seam responses from an older
  /// generation discard their result instead of writing to a dead notifier
  /// (the trip interactor's generation-guard pattern).
  int _generation = 0;

  Timer? _pollTimer;

  /// Static route geometry, fetched once per ride (memoized on success;
  /// a null answer retries next tick so the routeOnly rung can light up
  /// late — e.g. live mode the day gap #17 ships).
  RideGeo? _geo;

  /// Derived once per geometry — cached so pins/track keep referential
  /// identity across polls (select-scoped watches rebuild only on change).
  List<HopMapPin> _pins = const [];
  HopMapTrack? _track;
  HopGeoPoint? _pickup;
  HopGeoPoint? _destination;

  DriverPosition? _lastPosition;
  DateTime? _lastSampleAt;
  bool _sampleStale = false;

  static const _pollEvery = Duration(seconds: 1);

  /// A gap over this between absorbed samples flags the next one stale —
  /// HopMap snaps instead of gliding across town (throttled-tab rule).
  static const _staleGap = Duration(seconds: 3);

  RidesRepository get _rides => ref.read(ridesRepositoryProvider);

  @override
  MapState build() {
    final gen = ++_generation;
    _geo = null;
    _pins = const [];
    _track = null;
    _pickup = null;
    _destination = null;
    _lastPosition = null;
    _lastSampleAt = null;
    _sampleStale = false;

    ref.onDispose(() {
      _generation++;
      _pollTimer?.cancel();
      _pollTimer = null;
    });

    // Sibling-brain merge: trip phase flips (trip start, completion) re-map
    // the camera intent IMMEDIATELY — the completion settle must land with
    // the RouteStrip bloom, not up to a second later on the next poll.
    ref.listen(tripInteractorProvider(rideId), (previous, next) {
      if (previous?.phase != next.phase) {
        _recompose();
      }
    });

    _pollTimer = Timer.periodic(_pollEvery, (_) => unawaited(_poll(gen)));
    // First fetch immediately — the await inside yields, so the hidden
    // initial state below is returned before any state write happens.
    unawaited(_poll(gen));

    return const MapState();
  }

  // ── 1 Hz seam poll ───────────────────────────────────────────────────

  Future<void> _poll(int gen) async {
    if (gen != _generation) return;
    try {
      // driverPosition is the #41 seam (GET /rides/:id/driver-location):
      // null live today, so the ladder honestly steps to routeOnly and the
      // marker stays dark — never a fake car (decision 4). The day #41 ships
      // this starts answering and liveTracking lights up with zero view
      // change; only HopMap.sampleInterval retargets to the 5–10s cadence.
      final positionFuture = _rides.driverPosition(rideId);
      final geoFuture = _geo == null ? _rides.rideGeo(rideId) : null;
      final position = await positionFuture;
      final geo = geoFuture == null ? _geo : await geoFuture;
      if (gen != _generation) return;

      if (geo != null && !identical(geo, _geo)) {
        _absorbGeo(geo);
      }
      if (position != null) {
        final last = _lastSampleAt;
        final now = clock.now();
        _sampleStale = last != null && now.difference(last) > _staleGap;
        _lastSampleAt = now;
      }
      _lastPosition = position;
      _recompose();
    } on Exception {
      if (gen != _generation) return;
      // Transient seam blip: keep the last-known composition and retry on
      // the next tick — the ladder only downgrades on honest nulls.
    }
  }

  void _absorbGeo(RideGeo geo) {
    _geo = geo;
    _pickup = HopGeoPoint(geo.pickupLat, geo.pickupLng);
    _destination = HopGeoPoint(geo.dropoffLat, geo.dropoffLng);
    _pins = List.unmodifiable([
      HopMapPin(_pickup!, HopMapPinRole.pickup),
      HopMapPin(_destination!, HopMapPinRole.destination),
    ]);
    _track = geo.route.length < 2
        ? null
        : HopMapTrack(List.unmodifiable(
            [for (final p in geo.route) HopGeoPoint(p.lat, p.lng)]));
  }

  /// Build pins + a straight pickup→dropoff line from the booking handoff when
  /// the backend route seam (#17) gave us nothing. The handoff carries the
  /// coordinates the rider actually chose; comparing its `rideId` guards
  /// against an older booking's handoff leaking into this ride's map. A
  /// straight line is honest here — we have the endpoints, not the route
  /// geometry, so we draw what we can vouch for and no more.
  void _adoptHandoffGeo() {
    final handoff = ref.read(tripHandoffProvider);
    if (handoff == null) return;
    if (handoff.rideId != null && handoff.rideId != rideId) return;
    final pickup = handoff.pickup;
    final dropoff = handoff.dropoff;
    if (pickup == null || dropoff == null) return;
    _pickup = HopGeoPoint(pickup.lat, pickup.lng);
    _destination = HopGeoPoint(dropoff.lat, dropoff.lng);
    _pins = List.unmodifiable([
      HopMapPin(_pickup!, HopMapPinRole.pickup),
      HopMapPin(_destination!, HopMapPinRole.destination),
    ]);
    _track = HopMapTrack(List.unmodifiable([_pickup!, _destination!]));
  }

  // ── Composition (ladder + camera intent) ─────────────────────────────

  void _recompose() {
    final position = _lastPosition;
    final car =
        position == null ? null : HopGeoPoint(position.lat, position.lng);

    // LIVE-map fallback: gap #17 (rideGeo) answers null on live, so _geo never
    // populates and the map would stay hidden through a real booking. But the
    // pickup/dropoff coords the rider chose ARE in hand — the booking flow
    // stages them on TripHandoff at the match beat. When the backend seam has
    // given us nothing, draw the two pins and a straight pickup→dropoff line
    // from the handoff so the rider sees WHERE the trip goes, honestly labelled
    // as an approximate line (no route geometry to promise). This lights the
    // routeOnly rung on live instead of a blank canvas.
    if (_geo == null && _pins.isEmpty) {
      _adoptHandoffGeo();
    }

    final hasGeo = _geo != null || _pins.isNotEmpty;
    final phase = car != null
        ? MapPhase.liveTracking
        : (hasGeo ? MapPhase.routeOnly : MapPhase.hidden);
    if (phase == MapPhase.hidden) {
      // Canonical const: identical across polls, so listeners stay quiet
      // while the seams keep answering null.
      state = const MapState();
      return;
    }
    final tripPhase = ref.read(tripInteractorProvider(rideId)).phase;
    state = MapState(
      phase: phase,
      pins: _pins,
      track: _track,
      carPosition: car,
      carHeading: position?.heading,
      cameraIntent: _intentFor(tripPhase, car),
      sampleStale: _sampleStale,
    );
  }

  /// Trip phase → WHAT to frame (declarative — easing/debounce/gesture-pause
  /// are HopMap's job):
  /// - approach beats (driver assigned/arriving/arrived): fit driver +
  ///   pickup (MAP-01); with no driver pin, fit pickup + destination.
  /// - on-road: chase the car (MAP-02); routeOnly falls back to the full
  ///   route framing.
  /// - completed: one settle on the destination pin as the strip blooms.
  HopMapCameraIntent? _intentFor(TripPhase tripPhase, HopGeoPoint? car) {
    final pickup = _pickup;
    final destination = _destination;
    switch (tripPhase) {
      case TripPhase.loading:
      case TripPhase.finding:
      case TripPhase.driverEnRoute:
      case TripPhase.arrivingNow:
      case TripPhase.driverArrived:
        if (car != null && pickup != null) {
          return FitPoints([car, pickup]);
        }
        if (pickup != null && destination != null) {
          return FitPoints([pickup, destination]);
        }
        return car == null ? null : FollowPoint(car);
      case TripPhase.onRoad:
        if (car != null) {
          return FollowPoint(car);
        }
        if (pickup != null && destination != null) {
          return FitPoints([pickup, destination]);
        }
        return null;
      case TripPhase.completed:
        return destination == null ? null : SettleOn(destination);
      case TripPhase.cancelled:
      case TripPhase.error:
        // Terminal-without-celebration: hold the current framing; the world
        // archives the ride and the next polls walk the ladder down.
        return state.cameraIntent;
    }
  }
}
