import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/geo.dart';
import '../../../core/result.dart';

/// A journey the rider takes repeatedly — three or more completed trips
/// between roughly the same two points (the server groups to ~110 m).
class FrequentTrip {
  final LatLng pickup;
  final LatLng dropoff;
  final String? pickupLabel;
  final String? dropoffLabel;
  final int tripCount;
  final DateTime? lastTakenAt;

  /// The category the rider last chose for this journey, so a rebook can start
  /// from the vehicle they actually use rather than the default.
  final String? vehicleCategoryId;

  const FrequentTrip({
    required this.pickup,
    required this.dropoff,
    required this.pickupLabel,
    required this.dropoffLabel,
    required this.tripCount,
    required this.lastTakenAt,
    required this.vehicleCategoryId,
  });

  /// What to show for each end. The server keeps the most recent non-empty
  /// label; coordinates are the honest fallback when a trip was booked before
  /// labels were stored.
  String get fromLabel => pickupLabel ?? _coords(pickup);
  String get toLabel => dropoffLabel ?? _coords(dropoff);

  static String _coords(LatLng p) =>
      '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}';

  static FrequentTrip? tryFromJson(Map<String, dynamic> json) {
    final pLat = json['pickup_lat'], pLng = json['pickup_lng'];
    final dLat = json['dropoff_lat'], dLng = json['dropoff_lng'];
    if (pLat is! num || pLng is! num || dLat is! num || dLng is! num) {
      return null;
    }
    return FrequentTrip(
      pickup: LatLng(pLat.toDouble(), pLng.toDouble()),
      dropoff: LatLng(dLat.toDouble(), dLng.toDouble()),
      pickupLabel: _str(json['pickup_label']),
      dropoffLabel: _str(json['dropoff_label']),
      tripCount: switch (json['trip_count']) {
        final num n => n.toInt(),
        _ => 0,
      },
      lastTakenAt: switch (json['last_taken_at']) {
        String s => DateTime.tryParse(s),
        _ => null,
      },
      vehicleCategoryId: _str(json['vehicle_category_id']),
    );
  }

  static String? _str(Object? raw) => switch (raw) {
        String s when s.trim().isNotEmpty => s.trim(),
        _ => null,
      };
}

class FrequentTripsRepository {
  final ApiClient _api;
  const FrequentTripsRepository(this._api);

  Future<Result<List<FrequentTrip>>> list({int limit = 5}) async {
    final res = await _api.get<List<dynamic>>(
      '/me/frequent-trips',
      query: {'limit': '$limit'},
    );
    return switch (res) {
      Ok(:final value) => Ok(value
          .whereType<Map>()
          .map((m) => FrequentTrip.tryFromJson(m.cast<String, dynamic>()))
          .whereType<FrequentTrip>()
          .toList()),
      Err(:final error) => Err(error),
    };
  }
}

final frequentTripsRepositoryProvider = Provider<FrequentTripsRepository>(
    (ref) => FrequentTripsRepository(ref.watch(apiClientProvider)));

/// The rider's repeated journeys. Most riders have none — an empty list is the
/// normal answer, not a failure — and a failure degrades to empty too, because
/// a suggestion that cannot load must never break the screen carrying it.
final frequentTripsProvider =
    FutureProvider.autoDispose<List<FrequentTrip>>((ref) async {
  final result = await ref.watch(frequentTripsRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err() => const <FrequentTrip>[],
  };
});
