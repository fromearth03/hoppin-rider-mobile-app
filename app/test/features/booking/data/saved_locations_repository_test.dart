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

  test('reads the list', () async {
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'saved_locations': [
                {'id': 's1', 'label': 'Home', 'lat': 52.58, 'lng': -2.12},
              ],
            }));

    final list = ((await repo.list()) as Ok<List<SavedLocation>>).value;

    expect(list.single.label, 'Home');
    expect(list.single.lat, 52.58);
  });

  test('rename keeps the id - it patches rather than recreating', () async {
    // The endpoint exists precisely so a rename does not change the id.
    // Delete-and-recreate would break anything referencing the old one.
    when(() => api.patch<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({
              'id': 's1', 'label': 'Work', 'lat': 52.58, 'lng': -2.12,
            }));

    final updated =
        ((await repo.rename('s1', 'Work')) as Ok<SavedLocation>).value;

    expect(updated.id, 's1');
    expect(updated.label, 'Work');
    verify(() => api.patch<Map<String, dynamic>>('/me/saved-locations/s1',
        body: {'label': 'Work'})).called(1);
  });

  test('refuses a blank label before calling', () async {
    final result = await repo.rename('s1', '   ');

    expect((result as Err).error.code, 'VALIDATION_FAILED');
    verifyNever(() => api.patch<Map<String, dynamic>>(any(),
        body: any(named: 'body')));
  });

  test('add refuses a blank label before calling', () async {
    final result = await repo.add(label: '', lat: 1, lng: 2);

    expect((result as Err).error.code, 'VALIDATION_FAILED');
    verifyNever(() => api.post<Map<String, dynamic>>(any(),
        body: any(named: 'body')));
  });

  test('a saved place with no id is skipped rather than crashing the list',
      () async {
    // An unguarded `json['id'] as String` throws on one bad row and loses
    // the whole list. A place with no id cannot be renamed or deleted, so
    // rendering it would produce a row whose buttons fail - skip it instead.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'saved_locations': [
                {'id': null, 'label': 'Broken', 'lat': 1.0, 'lng': 2.0},
                {'id': '', 'label': 'Also broken', 'lat': 3.0, 'lng': 4.0},
                {'id': 's2', 'label': 'Work', 'lat': 52.6, 'lng': -2.2},
              ],
            }));

    final list = ((await repo.list()) as Ok<List<SavedLocation>>).value;

    expect(list, hasLength(1));
    expect(list.single.id, 's2');
  });
}
