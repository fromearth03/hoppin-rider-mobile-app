import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late FareRepository repo;

  const pickup = LatLng(52.586, -2.128);
  const dropoff = LatLng(52.593, -2.110);

  setUp(() {
    api = _MockApi();
    repo = FareRepository(api);
    registerFallbackValue(<String, dynamic>{});
  });

  group('single-stop', () {
    test('reads the estimate and keeps money as pence', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 12.50, 'gross': 12.50,
                             'discount': 0.0, 'discount_pct': 0},
                'distance_meters': 4700,
                'duration_seconds': 780,
                'route': [{'lat': 1.0, 'lng': 2.0}],
                'eta_source': 'model',
              }));

      final result = await repo.estimate(pickup: pickup, dropoff: dropoff);
      final fare = (result as Ok<FareEstimate>).value;

      expect(fare.totalPence, const Pence(1250),
          reason: 'the API sends pounds as a decimal; we store whole pence');
      expect(fare.isMultiStop, isFalse);
      expect(fare.legs, isEmpty);
      expect(fare.distanceMeters, 4700);
      expect(fare.etaSource, 'model');
    });

    test('omits waypoints from the body when there are none', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 5.0}, 'distance_meters': 100,
                'duration_seconds': 60,
              }));

      await repo.estimate(pickup: pickup, dropoff: dropoff);

      final body = verify(() => api.post<Map<String, dynamic>>(
          '/rides/estimate',
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body.containsKey('waypoints'), isFalse,
          reason: 'an empty array would switch the server to the multi-stop '
              'response shape for a single-leg trip');
    });
  });

  group('multi-stop', () {
    test('reads per-leg fares and the summed total', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true,
                'legs': [
                  {'seq': 0, 'to_label': 'Tesco', 'distance_meters': 1400,
                   'duration_seconds': 300, 'fare_pence': 3000},
                  {'seq': 1, 'to_label': 'Dropoff',
                   'distance_meters': 1800, 'duration_seconds': 360,
                   'fare_pence': 2000},
                ],
                'total_pence': 5000,
                'stops_count': 1,
                'distance_meters': 3200,
                'duration_seconds': 660,
              }));

      final result = await repo.estimate(
        pickup: pickup,
        dropoff: dropoff,
        waypoints: const [LatLng(52.580, -2.120)],
      );
      final fare = (result as Ok<FareEstimate>).value;

      expect(fare.isMultiStop, isTrue);
      expect(fare.legs, hasLength(2));
      expect(fare.legs.first.toLabel, 'Tesco');
      expect(fare.legs.first.farePence, const Pence(3000));
      expect(fare.totalPence, const Pence(5000));
      expect(fare.stopsCount, 1);
    });

    test('the total equals the sum of the legs', () async {
      // The rider is shown per-leg lines and a total; if they disagree the
      // screen looks like it is overcharging.
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true,
                'legs': [
                  {'seq': 0, 'to_label': 'A', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 3000},
                  {'seq': 1, 'to_label': 'B', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 9000},
                  {'seq': 2, 'to_label': 'C', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 2000},
                ],
                'total_pence': 14000, 'stops_count': 2,
                'distance_meters': 3, 'duration_seconds': 3,
              }));

      final fare = ((await repo.estimate(
        pickup: pickup,
        dropoff: dropoff,
        waypoints: const [LatLng(1, 1), LatLng(2, 2)],
      )) as Ok<FareEstimate>).value;

      final summed = fare.legs
          .map((l) => l.farePence.value)
          .reduce((a, b) => a + b);
      expect(Pence(summed), fare.totalPence);
    });

    test('sends the waypoints in the order given', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true, 'legs': [], 'total_pence': 0,
                'stops_count': 2, 'distance_meters': 0,
                'duration_seconds': 0,
              }));

      await repo.estimate(
        pickup: pickup,
        dropoff: dropoff,
        waypoints: const [LatLng(52.580, -2.120), LatLng(52.578, -2.101)],
      );

      final body = verify(() => api.post<Map<String, dynamic>>(any(),
          body: captureAny(named: 'body'))).captured.single as Map;
      final wp = body['waypoints'] as List;

      expect(wp, hasLength(2));
      expect((wp.first as Map)['lat'], 52.580,
          reason: 'stop order is the route; reordering changes the fare');
    });
  });

  group('zone discount', () {
    test('is read when present', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'gross': 12.00, 'discount_pct': 20,
                             'discount': 2.40, 'total': 9.60},
                'distance_meters': 100, 'duration_seconds': 60,
              }));

      final fare = ((await repo.estimate(pickup: pickup, dropoff: dropoff))
          as Ok<FareEstimate>).value;

      expect(fare.discountPct, 20);
      expect(fare.discountPence, const Pence(240));
      expect(fare.totalPence, const Pence(960));
    });

    test('a zero discount is not rendered as a line', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 12.00, 'discount_pct': 0,
                             'discount': 0.0},
                'distance_meters': 100, 'duration_seconds': 60,
              }));

      final fare = ((await repo.estimate(pickup: pickup, dropoff: dropoff))
          as Ok<FareEstimate>).value;

      expect(fare.hasDiscount, isFalse);
    });
  });
}
