import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/geo.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';

/// One booked future ride, as `GET /scheduled-rides` returns it — the
/// enriched row from `rider_gaps.go` (`scheduledRideItem`): coords, the
/// estimate in integer pence, the category name, and `active_ride_id` once
/// the watchdog has activated it into a real ride.
class ScheduledRide {
  final String id;
  final String status;
  final LatLng? pickup;
  final LatLng? dropoff;
  final DateTime? requestedPickupTime;
  final Pence? estimatePence;
  final String currency;
  final String? vehicleCategory;
  final String? activeRideId;

  const ScheduledRide({
    required this.id,
    required this.status,
    required this.pickup,
    required this.dropoff,
    required this.requestedPickupTime,
    required this.estimatePence,
    required this.currency,
    required this.vehicleCategory,
    required this.activeRideId,
  });

  /// Null for a row with no usable id — it could not be cancelled, so it
  /// would render as a card whose one action fails.
  static ScheduledRide? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    return ScheduledRide(
      id: id,
      status: (json['status'] as String?) ?? '',
      pickup: _point(json['pickup']),
      dropoff: _point(json['dropoff']),
      requestedPickupTime: switch (json['requested_pickup_time']) {
        String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      },
      estimatePence: Pence.fromJson(json['estimate_pence']),
      currency: (json['currency'] as String?) ?? 'GBP',
      vehicleCategory: switch (json['vehicle_category']) {
        String s when s.isNotEmpty => s,
        _ => null,
      },
      activeRideId: switch (json['active_ride_id']) {
        String s when s.isNotEmpty => s,
        _ => null,
      },
    );
  }

  static LatLng? _point(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'], lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }
}

/// One row of `GET /cancellation-policy` (rider scenarios only get shown).
/// Shape from `cancellation_policy_service.go`: actor, code, label,
/// free_cancel_seconds/meters, fee_pence, applies.
class CancellationScenario {
  final String actor;
  final String label;
  final Pence feePence;
  final int? freeCancelSeconds;

  const CancellationScenario({
    required this.actor,
    required this.label,
    required this.feePence,
    required this.freeCancelSeconds,
  });

  static CancellationScenario? tryFromJson(Map<String, dynamic> json) {
    final label = json['label'];
    if (label is! String || label.isEmpty) return null;
    return CancellationScenario(
      actor: (json['actor'] as String?) ?? '',
      label: label,
      feePence: Pence.fromJson(json['fee_pence']) ?? Pence.zero,
      freeCancelSeconds: (json['free_cancel_seconds'] as num?)?.toInt(),
    );
  }
}

/// `POST/GET/DELETE /scheduled-rides` — the future-booking surface. The
/// server enforces the pickup window (≥ 30 minutes ahead) and its watchdog
/// activates the ride near pickup time; nothing here re-implements either.
class ScheduledRidesRepository {
  final ApiClient _api;
  const ScheduledRidesRepository(this._api);

  Future<Result<ScheduledRide>> create({
    required LatLng pickup,
    required LatLng dropoff,
    required DateTime pickupTime,
    String? vehicleCategoryId,
  }) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/scheduled-rides',
      body: {
        'pickup_lat': pickup.lat,
        'pickup_lng': pickup.lng,
        'dropoff_lat': dropoff.lat,
        'dropoff_lng': dropoff.lng,
        // RFC3339 in UTC — the server parses time.RFC3339 and compares
        // against its own clock; a local-zone string would shift the
        // 30-minute window by the zone offset.
        'requested_pickup_time': pickupTime.toUtc().toIso8601String(),
        if (vehicleCategoryId != null)
          'vehicle_category_id': vehicleCategoryId,
      },
    );
    return switch (result) {
      Ok(:final value) => switch (ScheduledRide.tryFromJson(value)) {
          final ride? => Ok(ride),
          null => Ok(ScheduledRide(
              // A 201 whose body we cannot parse is still a created ride;
              // the list call renders the truth on next load.
              id: (value['id'] as String?) ?? '',
              status: (value['status'] as String?) ?? 'scheduled',
              pickup: pickup,
              dropoff: dropoff,
              requestedPickupTime: pickupTime.toUtc(),
              estimatePence: null,
              currency: 'GBP',
              vehicleCategory: null,
              activeRideId: null,
            )),
        },
      Err(:final error) => Err(error),
    };
  }

  Future<Result<List<ScheduledRide>>> list() async {
    final result = await _api.get<dynamic>('/scheduled-rides');
    return switch (result) {
      Ok(:final value) => Ok(_rows(value)
          .whereType<Map>()
          .map((row) =>
              ScheduledRide.tryFromJson(Map<String, dynamic>.from(row)))
          .whereType<ScheduledRide>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  static List _rows(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      final inner = body['scheduled_rides'] ?? body['items'];
      if (inner is List) return inner;
    }
    return const [];
  }

  Future<Result<void>> cancel(String id) async {
    final result = await _api.delete<dynamic>('/scheduled-rides/$id');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// The rider-relevant cancellation scenarios, for the policy card the
  /// frame draws under the fare. Lives here for now because scheduling is
  /// the first screen to render it; move to a shared booking data source
  /// when a second caller appears.
  Future<Result<List<CancellationScenario>>> cancellationPolicy() async {
    final result = await _api.get<Map<String, dynamic>>('/cancellation-policy');
    return switch (result) {
      Ok(:final value) => Ok(((value['scenarios'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => CancellationScenario.tryFromJson(
              Map<String, dynamic>.from(row)))
          .whereType<CancellationScenario>()
          .where((s) => s.actor == 'rider')
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }
}

final scheduledRidesRepositoryProvider = Provider<ScheduledRidesRepository>(
    (ref) => ScheduledRidesRepository(ref.watch(apiClientProvider)));
