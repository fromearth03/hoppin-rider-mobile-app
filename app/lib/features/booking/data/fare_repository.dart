import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/geo.dart';
import '../../../core/money.dart';
import '../../../core/result.dart';

// LatLng and kMaxWaypoints live in core/geo.dart -- shared geometry, not fare
// data. Re-exported so existing imports of this file keep working.
export '../../../core/geo.dart' show LatLng, kMaxWaypoints;

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

  /// Whether the discount figures are known at all.
  ///
  /// False on the multi-stop path, where the server sends no breakdown. The
  /// discount is still applied to the total; we simply cannot itemise it. The
  /// screen must not read a zero here as "no discount was applied".
  final bool discountKnown;

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
    required this.discountKnown,
    required this.etaSource,
  });

  bool get hasDiscount =>
      discountKnown && discountPct > 0 && discountPence.value > 0;

  /// The legs added up. Empty on a single-leg trip, where it is [Pence.zero].
  Pence get legsTotal => legs.isEmpty
      ? Pence.zero
      : Pence(legs.map((l) => l.farePence.value).reduce((a, b) => a + b));

  /// Whether the per-leg lines actually add up to the total shown beside them.
  ///
  /// The screen renders both, so a disagreement reads to the rider as
  /// overcharging. This is checked at render rather than assumed: a hand-built
  /// test fixture that adds up proves nothing about live data.
  bool get legsReconcile =>
      !isMultiStop || legs.isEmpty || legsTotal == totalPence;

  /// Pounds arrive as a JSON decimal on the single-stop breakdown; multi-stop
  /// sends integer pence directly. Rounding at the boundary keeps every later
  /// calculation in whole pence.
  ///
  /// It MUST round, not truncate. `4.10 * 100` is `409.99999999999994` in
  /// binary floating point, and truncating that yields 409p — a fare quoted a
  /// penny below what is charged. Across two-decimal fares from GBP 3 to GBP
  /// 60, truncation is wrong on 269 of 5701 values (4.7%).
  static Pence _poundsToPence(Object? raw) =>
      Pence((((raw as num?)?.toDouble() ?? 0) * 100).round());

  /// Parses the road polyline, degrading to null on anything malformed.
  static List<LatLng>? _parseRoute(Object? raw) {
    if (raw is! List) return null;
    final points = <LatLng>[];
    for (final p in raw) {
      if (p is! Map) return null;
      final lat = p['lat'], lng = p['lng'];
      if (lat is! num || lng is! num) return null;
      points.add(LatLng(lat.toDouble(), lng.toDouble()));
    }
    return points;
  }

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
      // A malformed point degrades to no polyline rather than throwing. The
      // route is already optional -- the map falls back to a straight line
      // when OSRM is unreachable -- so losing the whole quote over one bad
      // coordinate would be far worse than losing the preview.
      route: _parseRoute(json['route']),
      // A zone discount is already inside the total on both paths. On the
      // multi-stop path the server sends no `estimate` breakdown, so the
      // discount cannot be shown -- `discountKnown` says so explicitly rather
      // than letting a zero read as "no discount applied".
      discountPence: _poundsToPence(breakdown['discount']),
      discountPct: (breakdown['discount_pct'] as num?)?.toInt() ?? 0,
      discountKnown: breakdown.isNotEmpty,
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
  ///
  /// More than [kMaxWaypoints] stops is refused here as well as at booking.
  /// Quoting a six-stop fare and then refusing it at the book button would be
  /// worse than refusing the sixth stop as it is added.
  Future<Result<FareEstimate>> estimate({
    required LatLng pickup,
    required LatLng dropoff,
    String? vehicleCategoryId,
    List<LatLng> waypoints = const [],
  }) async {
    if (waypoints.length > kMaxWaypoints) {
      return const Err(ApiException(
        'VALIDATION_FAILED',
        'A trip can have at most $kMaxWaypoints stops.',
        0,
      ));
    }

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
