import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';

class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

/// One priced leg of a multi-stop trip.
class FareLeg {
  final int seq;
  final String toLabel;
  final int distanceMeters;
  final int durationSeconds;
  final Pence farePence;

  const FareLeg({
    required this.seq,
    required this.toLabel,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.farePence,
  });

  factory FareLeg.fromJson(Map<String, dynamic> json) => FareLeg(
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        toLabel: (json['to_label'] as String?) ?? '',
        distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        farePence: Pence.fromJson(json['fare_pence']) ?? Pence.zero,
      );
}

/// A quote from `POST /api/v1/rides/estimate`.
///
/// One call carries everything the booking screens need: the fare, the
/// distance and duration, the road polyline for the preview map, and - for a
/// multi-stop trip - the per-leg breakdown.
class FareEstimate {
  final Pence totalPence;
  final String currency;
  final int distanceMeters;
  final int durationSeconds;

  /// Empty for a single-leg trip.
  final List<FareLeg> legs;
  final bool isMultiStop;
  final int stopsCount;

  /// Road geometry for the preview. Null when OSRM was unreachable, in which
  /// case the map draws a straight line.
  final List<LatLng>? route;

  /// Automatic per-zone discount, already inside [totalPence].
  final Pence discountPence;
  final int discountPct;

  /// Which ETA tier produced the duration: model, google or osrm.
  final String etaSource;

  const FareEstimate({
    required this.totalPence,
    required this.currency,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.legs,
    required this.isMultiStop,
    required this.stopsCount,
    required this.route,
    required this.discountPence,
    required this.discountPct,
    required this.etaSource,
  });

  bool get hasDiscount => discountPct > 0 && discountPence.value > 0;

  /// Pounds arrive as a JSON decimal on the single-stop breakdown; multi-stop
  /// sends integer pence directly. Rounding at the boundary keeps every later
  /// calculation in whole pence.
  static Pence _poundsToPence(Object? raw) =>
      Pence(((raw as num?)?.toDouble() ?? 0) * 100 ~/ 1);

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    final multi = json['multi_stop'] == true;
    final breakdown =
        (json['estimate'] as Map?)?.cast<String, dynamic>() ?? const {};

    return FareEstimate(
      totalPence: multi
          ? (Pence.fromJson(json['total_pence']) ?? Pence.zero)
          : _poundsToPence(breakdown['total']),
      currency: (json['currency'] as String?) ?? 'GBP',
      distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      legs: ((json['legs'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(FareLeg.fromJson)
          .toList(growable: false),
      isMultiStop: multi,
      stopsCount: (json['stops_count'] as num?)?.toInt() ?? 0,
      route: switch (json['route']) {
        List points => points
            .cast<Map<String, dynamic>>()
            .map((p) => LatLng(
                (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
            .toList(growable: false),
        _ => null,
      },
      discountPence: _poundsToPence(breakdown['discount']),
      discountPct: (breakdown['discount_pct'] as num?)?.toInt() ?? 0,
      etaSource: (json['eta_source'] as String?) ?? '',
    );
  }
}

class FareRepository {
  final ApiClient _api;
  const FareRepository(this._api);

  /// Quotes a trip.
  ///
  /// This is the ONLY pricing call the app makes. The dispatch engine on
  /// :8081 is not client-facing; the ride service consults it internally so
  /// the quote and the eventual charge price off the same corrected duration.
  ///
  /// Waypoints are omitted entirely when empty - sending `[]` switches the
  /// server to the multi-stop response shape for a single-leg trip.
  Future<Result<FareEstimate>> estimate({
    required LatLng pickup,
    required LatLng dropoff,
    String? vehicleCategoryId,
    List<LatLng> waypoints = const [],
  }) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/rides/estimate',
      body: {
        'pickup_lat': pickup.lat,
        'pickup_lng': pickup.lng,
        'dropoff_lat': dropoff.lat,
        'dropoff_lng': dropoff.lng,
        if (vehicleCategoryId != null)
          'vehicle_category_id': vehicleCategoryId,
        if (waypoints.isNotEmpty)
          'waypoints': waypoints.map((w) => w.toJson()).toList(),
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(FareEstimate.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final fareRepositoryProvider = Provider<FareRepository>(
    (ref) => FareRepository(ref.watch(apiClientProvider)));
