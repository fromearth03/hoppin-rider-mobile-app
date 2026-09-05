import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// One bookable vehicle class, mirroring `GET /api/v1/vehicle-types`.
///
/// Artwork is admin-uploaded ([iconUrl], migration 132) with the bundled
/// capacity-keyed asset as the fallback — categories are admin-editable and a
/// new one can appear without an app release, so the app must render something
/// sensible for a class it has never heard of.
class VehicleCategory {
  final String id;
  final String name;
  final int seats;
  final int bags;

  /// Relative cost, used to convey price before an estimate resolves.
  final double priceMultiplier;

  /// Artwork the operator uploaded for this class. Null when they uploaded
  /// none, and the app falls back to its bundled asset.
  final String? iconUrl;

  const VehicleCategory({
    required this.id,
    required this.name,
    required this.seats,
    required this.bags,
    required this.priceMultiplier,
    this.iconUrl,
  });

  /// The API COALESCEs seats and bags to 0 when unconfigured. Rendering
  /// "0 Seats 0 Bags" would state something false, so the row is dropped.
  bool get hasCapacity => seats > 0 || bags > 0;

  /// Returns null for a row with no usable id.
  ///
  /// The id is sent to `/rides/estimate` and `/rides/request`, so a category
  /// without one cannot be booked and is worse than absent — it would render
  /// as a tappable card that fails at the last step. Returning null lets the
  /// repository skip that one row instead of throwing away the whole
  /// catalogue, which an unguarded cast would do.
  static VehicleCategory? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;

    return VehicleCategory(
      id: id,
      name: (json['name'] as String?) ?? '',
      seats: (json['seats'] as num?)?.toInt() ?? 0,
      bags: (json['bags'] as num?)?.toInt() ?? 0,
      priceMultiplier: (json['price_multiplier'] as num?)?.toDouble() ?? 1.0,
      iconUrl: switch (json['icon_url']) {
        String s when s.trim().isNotEmpty => s.trim(),
        _ => null,
      },
    );
  }

  factory VehicleCategory.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json)!;
}

class VehicleRepository {
  final ApiClient _api;
  const VehicleRepository(this._api);

  /// Active categories, cheapest first.
  ///
  /// The server orders by `price_multiplier, name` and filters on `is_active`.
  /// Render in the order received — re-sorting client-side would reorder the
  /// picker away from what the operator configured.
  Future<Result<List<VehicleCategory>>> list() async {
    final result = await _api.get<Map<String, dynamic>>('/vehicle-types');
    return switch (result) {
      // A malformed row is skipped rather than throwing: one bad record from
      // the admin panel should cost the rider that category, not the entire
      // picker.
      Ok(:final value) => Ok(((value['vehicle_types'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(VehicleCategory.tryFromJson)
          .whereType<VehicleCategory>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }
}

final vehicleRepositoryProvider = Provider<VehicleRepository>(
    (ref) => VehicleRepository(ref.watch(apiClientProvider)));
