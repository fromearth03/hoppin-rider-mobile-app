import 'package:flutter/foundation.dart';
import 'package:hoppin_ui/hoppin_ui.dart'
    show
        HopGeoPoint,
        HopMapCameraIntent,
        HopMapPin,
        HopMapTrack;

// The map riblet speaks hoppin_ui's pure-Dart map vocabulary (HopGeoPoint,
// pins, tracks, camera intents — data types, zero widgets). Re-exported so
// the interactor and its tests import ONE riblet-local surface and never
// name hoppin_ui in a brain file.
export 'package:hoppin_ui/hoppin_ui.dart'
    show
        FitPoints,
        FollowPoint,
        HopGeoPoint,
        HopMapCameraIntent,
        HopMapPin,
        HopMapPinRole,
        HopMapTrack,
        SettleOn;

/// The MAP-03 degradation ladder — three DESIGNED rungs, never an error
/// state. Which rung renders is recomputed on every 1 Hz poll from what the
/// geo capability seams actually answered.
enum MapPhase {
  /// Both seams answer null (live today: gaps #17/#41 unshipped) — the map
  /// pane hides entirely and the trip screen renders EXACTLY the Phase 4/5
  /// map-less layout. Nothing is lost.
  hidden,

  /// Route geometry only (live once gap #17 ships, before #41): pickup and
  /// destination pins plus the trip polyline — no car marker.
  routeOnly,

  /// Position + geometry (demo today; live once #41 + #17 ship): the full
  /// live map with the tweened car marker.
  liveTracking,
}

/// Immutable snapshot of the rider map riblet — pure data for HopMap's
/// inputs plus the ladder rung. No controllers, contexts, or repositories
/// (riblet rule, DOCS/05).
@immutable
class MapState {
  const MapState({
    this.phase = MapPhase.hidden,
    this.pins = const [],
    this.track,
    this.carPosition,
    this.carHeading,
    this.cameraIntent,
    this.sampleStale = false,
  });

  /// Which ladder rung the map surface renders.
  final MapPhase phase;

  /// Pickup + destination pins (empty until route geometry arrives). The
  /// interactor caches ONE list instance per geometry so select-scoped
  /// watches stay referentially cheap.
  final List<HopMapPin> pins;

  /// The pickup→destination polyline; null until geometry arrives.
  final HopMapTrack? track;

  /// Latest car sample; null hides the marker (hidden/routeOnly rungs).
  final HopGeoPoint? carPosition;

  /// Seam heading in degrees clockwise from north; null lets HopMap fall
  /// back to the marker's own movement bearing.
  final double? carHeading;

  /// WHAT the camera should frame (HopMap owns HOW). Null only while
  /// [phase] is [MapPhase.hidden] — no map, no camera.
  final HopMapCameraIntent? cameraIntent;

  /// True when the gap since the previous absorbed sample exceeded ~3s
  /// (throttled tab, F5 resume) — HopMap's deliberate-snap hint.
  final bool sampleStale;
}
