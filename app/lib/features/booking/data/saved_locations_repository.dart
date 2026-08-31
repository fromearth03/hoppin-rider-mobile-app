import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// A place the rider saved. Its label is what they typed; search ranks these
/// above map hits.
class SavedLocation {
  final String id;
  final String label;
  final double lat;
  final double lng;

  const SavedLocation({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
  });

  /// Returns null when `id` is missing or blank rather than throwing, so one
  /// malformed row does not cost the caller the entire list. A place with no
  /// id cannot be renamed or deleted, so rendering it would produce a row
  /// whose buttons fail - the caller skips it instead.
  static SavedLocation? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;

    return SavedLocation(
      id: id,
      label: (json['label'] as String?) ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SavedLocationsRepository {
  final ApiClient _api;
  const SavedLocationsRepository(this._api);

  Future<Result<List<SavedLocation>>> list() async {
    final result =
        await _api.get<Map<String, dynamic>>('/me/saved-locations');
    return switch (result) {
      // `List.cast()` is lazy: it throws when `map` pulls a non-object element,
      // escaping a method that promises a Result. Filter by type instead.
      Ok(:final value) => Ok((value['saved_locations'] is List
              ? value['saved_locations'] as List
              : const [])
          .whereType<Map<String, dynamic>>()
          .map(SavedLocation.tryFromJson)
          .whereType<SavedLocation>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<SavedLocation>> add({
    required String label,
    required double lat,
    required double lng,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return Err(
          ApiException('VALIDATION_FAILED', 'Give this place a name.', 0));
    }

    final result =
        await _api.post<Map<String, dynamic>>('/me/saved-locations', body: {
      'label': trimmed,
      'lat': lat,
      'lng': lng,
    });

    return switch (result) {
      Ok(:final value) => _fromValidJson(value),
      Err(:final error) => Err(error),
    };
  }

  /// Renames in place. The endpoint exists precisely so the id survives -
  /// delete-and-recreate would break anything holding the old one.
  Future<Result<SavedLocation>> rename(String id, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return Err(
          ApiException('VALIDATION_FAILED', 'Give this place a name.', 0));
    }

    final result = await _api.patch<Map<String, dynamic>>(
        '/me/saved-locations/$id',
        body: {'label': trimmed});

    return switch (result) {
      Ok(:final value) => _fromValidJson(value),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> remove(String id) async {
    final result = await _api.delete<dynamic>('/me/saved-locations/$id');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// A successful add/rename response is trusted to carry a real id - if it
  /// somehow does not, that is surfaced as an error rather than silently
  /// returning a place that cannot later be renamed or deleted.
  Result<SavedLocation> _fromValidJson(Map<String, dynamic> json) {
    final place = SavedLocation.tryFromJson(json);
    if (place == null) {
      return const Err(ApiException(
          'INTERNAL', 'Saved place response was missing an id.', 0));
    }
    return Ok(place);
  }
}

final savedLocationsRepositoryProvider = Provider<SavedLocationsRepository>(
    (ref) => SavedLocationsRepository(ref.watch(apiClientProvider)));
