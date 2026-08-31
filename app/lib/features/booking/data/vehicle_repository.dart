import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// One bookable vehicle class, mirroring `GET /api/v1/vehicle-types`.
///
/// Five fields and no more (`app_catalog_repo.go:225-236`). There is no image,
/// icon or description — artwork is a local asset keyed by [name], with a
/// generic fallback, because categories are admin-editable and a new one can
/// appear without an app release.
class VehicleCategory {
  final String id;
  final String name;
  final int seats;
  final int bags;

  /// Relative cost, used to convey price before an estimate resolves.
  final double priceMultiplier;

  const VehicleCategory({
    required this.id,
    required this.name,
    required this.seats,
    required this.bags,
    required this.priceMultiplier,
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
