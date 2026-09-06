import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/saved_locations_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late SavedLocationsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = SavedLocationsRepository(api);
  });

  test('parses the bare array the endpoint actually returns', () async {
    // `rider_handler.go` answers `c.JSON(http.StatusOK, locs)` — a bare JSON
    // array, NOT an object wrapping one. The repository used to ask for a Map,
    // so every response failed its cast and the screen never loaded.
    when(() => api.get<List<dynamic>>('/me/saved-locations'))
        .thenAnswer((_) async => const Ok<List<dynamic>>([
              {'id': 'sl_1', 'label': 'Home', 'lat': 52.58, 'lng': -2.12},
              {'id': 'sl_2', 'label': 'Work', 'lat': 52.59, 'lng': -2.11},
            ]));

    final result = await repo.list();

    expect(result, isA<Ok<List<SavedLocation>>>());
    final places = (result as Ok<List<SavedLocation>>).value;
    expect(places.map((p) => p.label), ['Home', 'Work']);
  });

  test('skips a malformed row rather than losing the whole list', () async {
    when(() => api.get<List<dynamic>>('/me/saved-locations'))
        .thenAnswer((_) async => const Ok<List<dynamic>>([
              {'id': 'sl_1', 'label': 'Home', 'lat': 52.58, 'lng': -2.12},
              'not an object',
              {'label': 'no id'},
            ]));

    final result = await repo.list();

    expect((result as Ok<List<SavedLocation>>).value, hasLength(1));
  });

  test('an empty list is a success, not an error', () async {
    when(() => api.get<List<dynamic>>('/me/saved-locations'))
        .thenAnswer((_) async => const Ok<List<dynamic>>([]));

    final result = await repo.list();

    expect((result as Ok<List<SavedLocation>>).value, isEmpty);
  });
}
