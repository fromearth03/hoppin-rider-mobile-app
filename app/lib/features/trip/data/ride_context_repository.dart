import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/geo.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';
import 'live_trip_source.dart';

/// `GET /rides/:id` — the one call that renders the whole trip screen.
///
/// Shape read from `rider_ride_detail.go`: ride keys plus `ref`,
/// `geo{pickup,dropoff,waypoints,route,steps}`,
/// `driver{full_name,avatar_url,rating,rating_count,trips_count,
/// vehicle{make,model,colour,plate,seats,bags},eta_seconds}` (null while
/// matching — a normal state, not an error),
/// `fare{estimate_pence,total_pence,currency,discount_pence}`,
/// `timestamps`, `chat_unread`. This maps that real shape onto
/// [LiveTripInfo]; the older flat parse in `live_trip_source.dart` was
/// written against the decisions doc's guess and stays only for its tests.
class RideContextRepository {
  final ApiClient _api;
  const RideContextRepository(this._api);

  Future<Result<LiveTripInfo>> fetch(String rideId) async {
    if (rideId.isEmpty) {
      // /rides//… is malformed; the awaiting state is the honest render.
      return Ok(LiveTripInfo.awaiting(rideId));
    }
    final result = await _api.get<Map<String, dynamic>>('/rides/$rideId');
    return switch (result) {
      Ok(:final value) => Ok(fromRideDetail(value)),
      Err(:final error) => Err(error),
    };
  }

  /// The documented fallback transport: a ~1 Hz poll (SSE for driver
  /// position and FCM for status arrive in a later pass; the poll is the
  /// spec's fallback, not an invention). Emits on every successful fetch;
  /// a transport error keeps the last emitted state rather than flapping
  /// the screen into an error it has no rendering for.
  Stream<LiveTripInfo> watch(String rideId,
      {Duration interval = const Duration(seconds: 2)}) async* {
    LiveTripInfo? last;
    while (true) {
      final result = await fetch(rideId);
      if (result case Ok(:final value)) {
        last = value;
        yield value;
      } else if (last == null) {
        yield LiveTripInfo.awaiting(rideId);
        last = LiveTripInfo.awaiting(rideId);
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Maps the enriched ride detail onto [LiveTripInfo]. Static and public
  /// so tests can feed it captured payloads directly.
  static LiveTripInfo fromRideDetail(Map<String, dynamic> json) {
    final geo = _map(json['geo']);
    final driver = _map(json['driver']);
    final fare = _map(json['fare']);

    TripDriver? tripDriver;
    if (driver != null) {
      final vehicle = _map(driver['vehicle']) ?? const {};
      final vehicleType = [
        vehicle['colour'],
        vehicle['make'],
        vehicle['model'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
      tripDriver = TripDriver.tryFromJson({
        'name': driver['full_name'],
        'avatar_url': driver['avatar_url'],
        'rating': driver['rating'],
        'rating_count': driver['rating_count'],
        'trips_completed': driver['trips_count'],
        'plate': vehicle['plate'],
        'vehicle_type': vehicleType.isEmpty ? null : vehicleType,
        'seats': vehicle['seats'],
        'bags': vehicle['bags'],
      });
    }

    final waypoints = <TripWaypoint>[];
    if (geo != null) {
      void addPoint(Object? raw, String fallbackLabel) {
        final p = _map(raw);
        if (p == null) return;
        final lat = p['lat'], lng = p['lng'];
        waypoints.add(TripWaypoint(
          label: switch (p['label']) {
            String s when s.trim().isNotEmpty => s,
            _ => fallbackLabel,
          },
          distanceLabel: null,
          position: (lat is num && lng is num)
              ? LatLng(lat.toDouble(), lng.toDouble())
              : null,
        ));
      }

      addPoint(geo['pickup'], 'Pickup');
      final mids = geo['waypoints'];
      if (mids is List) {
        for (var i = 0; i < mids.length; i++) {
          addPoint(mids[i], 'Stop ${i + 1}');
        }
      }
      addPoint(geo['dropoff'], 'Destination');
    }

    final dropoff = _map(geo?['dropoff']);

    return LiveTripInfo(
      rideId: switch (json['id']) {
        String s when s.isNotEmpty => s,
        _ => '',
      },
      status: switch (json['status']) {
        'accepted' => LiveTripStatus.accepted,
        'arriving' => LiveTripStatus.arriving,
        'started' => LiveTripStatus.started,
        'completed' => LiveTripStatus.completed,
        // requested / matching / assigned / cancelled / unknown all render
        // as the matching state — the screen's safest real rendering.
        _ => LiveTripStatus.matching,
      },
      driver: tripDriver,
      // The detail's fare block is estimate/total only — no base/surge
      // split exists on this endpoint, and nothing is invented.
      baseFarePence: null,
      surgeMultiplier: null,
      surgePence: null,
      totalPence: Pence.fromJson(
          fare?['total_pence'] ?? fare?['estimate_pence']),
      currency: switch (fare?['currency']) {
        String s when s.isNotEmpty => s,
        _ => 'GBP',
      },
      cancellationPolicy: null,
      waypoints: waypoints,
      route: _points(geo?['route']),
      steps: _steps(geo?['steps']),
      destinationLabel: switch (dropoff?['label']) {
        String s when s.trim().isNotEmpty => s,
        _ => null,
      },
    );
  }

  static Map<String, dynamic>? _map(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : null;

  static List<LatLng>? _points(Object? raw) {
    if (raw is! List) return null;
    final points = <LatLng>[];
    for (final p in raw) {
      if (p is! Map) continue;
      final lat = p['lat'], lng = p['lng'];
      if (lat is num && lng is num) {
        points.add(LatLng(lat.toDouble(), lng.toDouble()));
      }
    }
    return points.isEmpty ? null : points;
  }

  static List<TripStep>? _steps(Object? raw) {
    if (raw is! List) return null;
    final steps = raw
        .whereType<Map>()
        .map((m) => TripStep.tryFromJson(m.cast<String, dynamic>()))
        .whereType<TripStep>()
        .toList(growable: false);
    return steps.isEmpty ? null : steps;
  }
}

final rideContextRepositoryProvider = Provider<RideContextRepository>(
    (ref) => RideContextRepository(ref.watch(apiClientProvider)));
