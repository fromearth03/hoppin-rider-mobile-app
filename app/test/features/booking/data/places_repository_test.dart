import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/geo.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/places_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late PlacesRepository repo;

  setUp(() {
    api = _MockApi();
    repo = PlacesRepository(api);
  });

  test('a saved place is distinguishable from a map hit', () {
    final saved = PlaceSuggestion.fromJson(const {
      'label': 'Home', 'lat': 52.58, 'lng': -2.12, 'source': 'saved',
    });
    final map = PlaceSuggestion.fromJson(const {
      'label': 'Molineux Stadium', 'lat': 52.59, 'lng': -2.13,
      'postcode': 'WV1 4QR', 'source': 'map',
    });

    expect(saved.isSaved, isTrue);
    expect(map.isSaved, isFalse);
    expect(map.postcode, 'WV1 4QR');
    expect(saved.postcode, isNull, reason: 'omitted when empty');
  });

  test('skips a row with no coordinate rather than losing the list', () async {
    // A suggestion the rider cannot travel to renders as a tappable row that
    // fails when chosen. One bad result should not cost the whole list.
    when(() => api.get<Map<String, dynamic>>(any(), query: any(named: 'query')))
        .thenAnswer((_) async => const Ok({
              'results': [
                {'label': 'Good', 'lat': 52.58, 'lng': -2.12, 'source': 'map'},
                {'label': 'No coords', 'source': 'map'},
                {'label': 'Null lat', 'lat': null, 'lng': -2.12,
                 'source': 'map'},
                {'label': 'Also good', 'lat': 52.59, 'lng': -2.13,
                 'source': 'saved'},
              ],
            }));

    final labels = ((await repo.search('molineux')) as Ok<List<PlaceSuggestion>>)
        .value
        .map((p) => p.label);

    expect(labels, ['Good', 'Also good']);
  });

  test('exposes a position in the shared coordinate type', () {
    // Saves every call site converting lat/lng by hand when handing a chosen
    // place to the estimate or booking call.
    final p = PlaceSuggestion.fromJson(const {
      'label': 'Home', 'lat': 52.58, 'lng': -2.12, 'source': 'saved',
    });

    expect(p.position, const LatLng(52.58, -2.12));
  });

  test('does not call the API below the minimum query length', () async {
    // The server returns [] under 2 characters. Calling anyway would burn a
    // request per keystroke for a guaranteed-empty answer.
    final result = await repo.search('m');

    expect((result as Ok<List<PlaceSuggestion>>).value, isEmpty);
    verifyNever(() => api.get<Map<String, dynamic>>(any(),
        query: any(named: 'query')));
  });

  test('sends position as a bias when it is known', () async {
    when(() => api.get<Map<String, dynamic>>(any(),
            query: any(named: 'query')))
        .thenAnswer((_) async => const Ok({'results': [], 'query': 'molin'}));

    await repo.search('molin', lat: 52.58, lng: -2.12);

    final q = verify(() => api.get<Map<String, dynamic>>('/geocode/search',
        query: captureAny(named: 'query'))).captured.single as Map;

    expect(q['q'], 'molin');
    expect(q['lat'], 52.58);
    expect(q['lng'], -2.12);
  });

  test('omits position entirely when unknown', () async {
    when(() => api.get<Map<String, dynamic>>(any(),
            query: any(named: 'query')))
        .thenAnswer((_) async => const Ok({'results': []}));

    await repo.search('molineux');

    final q = verify(() => api.get<Map<String, dynamic>>('/geocode/search',
        query: captureAny(named: 'query'))).captured.single as Map;

    expect(q.containsKey('lat'), isFalse,
        reason: 'sending lat=0 would bias every search to the Atlantic');
  });

  test('preserves server ranking — saved places already come first', () async {
    when(() => api.get<Map<String, dynamic>>(any(),
            query: any(named: 'query')))
        .thenAnswer((_) async => const Ok({
              'results': [
                {'label': 'Home', 'lat': 1.0, 'lng': 1.0, 'source': 'saved'},
                {'label': 'Holt Street', 'lat': 2.0, 'lng': 2.0,
                 'source': 'map'},
              ],
            }));

    final result = await repo.search('ho');

    final labels =
        (result as Ok<List<PlaceSuggestion>>).value.map((p) => p.label);
    expect(labels, ['Home', 'Holt Street']);
  });
}
