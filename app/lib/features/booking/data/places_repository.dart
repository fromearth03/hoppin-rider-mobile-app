import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/geo.dart';
import '../../../core/result.dart';

/// The server returns `[]` below this length rather than an error, so calling
/// is a guaranteed-empty round trip per keystroke.
const kMinQueryLength = 2;

/// One autocomplete row from `GET /api/v1/geocode/search`.
class PlaceSuggestion {
  final String label;
  final double lat;
  final double lng;

  /// Omitted by the server when empty.
  final String? postcode;

  /// `saved` (the rider's own place) or `map` (a Photon hit). Saved places
  /// rank first and are styled differently.
  final String source;

  const PlaceSuggestion({
    required this.label,
    required this.lat,
    required this.lng,
    required this.postcode,
    required this.source,
  });

  bool get isSaved => source == 'saved';

  /// The coordinate, in the shared type the estimate and booking calls take.
  /// Saves every call site converting by hand.
  LatLng get position => LatLng(lat, lng);

  /// Returns null for a row with no usable coordinate.
  ///
  /// A suggestion the rider cannot actually travel to is worse than one that
  /// is missing: it renders as a tappable row that fails when chosen. Letting
  /// the repository skip it keeps the rest of the list usable, where an
  /// unguarded cast would throw away every suggestion.
  static PlaceSuggestion? tryFromJson(Map<String, dynamic> json) {
    final lat = json['lat'], lng = json['lng'];
    if (lat is! num || lng is! num) return null;

    return PlaceSuggestion(
      label: (json['label'] as String?) ?? '',
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      postcode: switch (json['postcode']) {
        String s when s.isNotEmpty => s,
        _ => null,
      },
      source: (json['source'] as String?) ?? 'map',
    );
  }

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json)!;
}

class PlacesRepository {
  final ApiClient _api;
  const PlacesRepository(this._api);

  /// Address autocomplete.
  ///
  /// [lat]/[lng] BIAS the results toward the rider; they do not bound them.
  /// Bounding would return nothing for a trip to Birmingham Airport. When the
  /// position is unknown the parameters are omitted rather than sent as zero,
  /// which would bias every search to a point in the Atlantic.
  ///
  /// An empty result is ambiguous: the server answers with the rider's saved
  /// places alone when Photon is unreachable, silently. Copy must not assert
  /// that no such place exists.
  Future<Result<List<PlaceSuggestion>>> search(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < kMinQueryLength) {
      return const Ok(<PlaceSuggestion>[]);
    }

    final result = await _api.get<Map<String, dynamic>>(
      '/geocode/search',
      query: {
        'q': trimmed,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(((value['results'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          // A row with no usable coordinate is skipped, so one bad result
          // does not cost the rider the whole suggestion list.
          .map(PlaceSuggestion.tryFromJson)
          .whereType<PlaceSuggestion>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// Names a point the rider dropped a pin on.
  Future<Result<PlaceSuggestion>> reverse(double lat, double lng) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/geocode/reverse',
      query: {'lat': lat, 'lng': lng},
    );
    return switch (result) {
      Ok(:final value) => Ok(PlaceSuggestion.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final placesRepositoryProvider = Provider<PlacesRepository>(
    (ref) => PlacesRepository(ref.watch(apiClientProvider)));
