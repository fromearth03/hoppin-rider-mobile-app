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

  /// `GET /rides/:id/driver-location` — the assigned driver's last-known
  /// position, or null whenever it is unavailable (no driver yet, telemetry
  /// gap, terminal ride). Null is a normal state here, never an error: the
  /// marker simply doesn't render.
  Future<LatLng?> driverPosition(String rideId) async {
    if (rideId.isEmpty) return null;
    final result =
        await _api.get<Map<String, dynamic>>('/rides/$rideId/driver-location');
    return switch (result) {
      Ok(:final value)
          when value['lat'] is num && value['lng'] is num =>
        LatLng(
          (value['lat'] as num).toDouble(),
          (value['lng'] as num).toDouble(),
        ),
      _ => null,
    };
  }

  /// `GET /me/active-ride` — the rider's current non-terminal ride id, or
  /// null while dispatch is still matching (no ride row exists yet).
  Future<String?> activeRideId() async {
    final result = await _api.get<Map<String, dynamic>>('/me/active-ride');
    return switch (result) {
      Ok(:final value) => switch (value['active_ride_id']) {
          String s when s.isNotEmpty => s,
          _ => null,
        },
      Err() => null,
    };
  }

  /// The documented fallback transport: a ~1 Hz poll (SSE for driver
  /// position and FCM for status arrive in a later pass; the poll is the
  /// spec's fallback, not an invention). Emits on every successful fetch;
  /// a transport error keeps the last emitted state rather than flapping
  /// the screen into an error it has no rendering for.
  ///
  /// `POST /rides/request` answers 202 with a DISPATCH request id — the ride
  /// row is created asynchronously once a driver matches, so that id is never
  /// a ride id and `GET /rides/{it}` is a guaranteed 404. The stream
  /// therefore resolves the real id through `/me/active-ride`: immediately
  /// when started with no id, and on any RIDE_NOT_FOUND when started with a
  /// stale or non-ride id.
  Stream<LiveTripInfo> watch(String rideId,
      {Duration interval = const Duration(seconds: 2)}) async* {
    var id = rideId;
    LiveTripInfo? last;
    while (true) {
      if (id.isEmpty) {
        id = await activeRideId() ?? '';
        if (id.isEmpty) {
          // Dispatch has the request but no ride row yet — honest matching
          // state, then ask again next tick.
          last ??= LiveTripInfo.awaiting(id);
          yield last;
          await Future<void>.delayed(interval);
          continue;
        }
      }

      final result = await fetch(id);
      switch (result) {
        case Ok(:final value):
          last = value;
          yield value;
        case Err(:final error)
            when error.status == 404 || error.code == 'RIDE_NOT_FOUND':
          // The id we hold is not a ride (a dispatch request id, or a ride
          // that vanished). Re-resolve rather than 404ing forever.
          final resolved = await activeRideId();
          if (resolved != null && resolved != id) {
            id = resolved;
            continue; // retry immediately with the real id
          }
          if (last == null) {
            last = LiveTripInfo.awaiting(id);
            yield last;
          }
        case Err():
          // Transient transport error: keep the last emitted state rather
          // than flapping the screen into an error it has no rendering for.
          if (last == null) {
            last = LiveTripInfo.awaiting(id);
            yield last;
          }
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
        // Terminal: dispatch auto-cancelled (no driver) or someone cancelled.
        // Rendering this as "matching" left riders spinning on a dead ride.
        'cancelled' => LiveTripStatus.cancelled,
        // requested / matching / assigned / unknown all render as the
        // matching state — the screen's safest real rendering.
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
      riderNote: switch (json['rider_note']) {
        String s when s.trim().isNotEmpty => s.trim(),
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
