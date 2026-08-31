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

  group('pounds to pence', () {
    Future<FareEstimate> quoteOf(num pounds, {num? discount}) async {
      when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => Ok({
                'estimate': {
                  'total': pounds,
                  if (discount != null) 'discount': discount,
                  if (discount != null) 'discount_pct': 20,
                },
                'distance_meters': 100,
                'duration_seconds': 60,
              }));
      return ((await repo.estimate(pickup: pickup, dropoff: dropoff))
              as Ok<FareEstimate>)
          .value;
    }

    test('is exact for fares that are not exact in binary floating point',
        () async {
      // 4.10 * 100 is 409.99999999999994. Truncating gives 409p -- a fare
      // quoted a penny below what is charged. Across two-decimal fares from
      // GBP 3 to GBP 60, truncation is wrong on 269 of 5701 values.
      expect((await quoteOf(4.10)).totalPence, const Pence(410));
      expect((await quoteOf(8.87)).totalPence, const Pence(887));
      expect((await quoteOf(2.30)).totalPence, const Pence(230));
      expect((await quoteOf(1.15)).totalPence, const Pence(115));
      expect((await quoteOf(4.02)).totalPence, const Pence(402));
    });

    test('a discount on an inexact fare also lands exactly', () async {
      // Both figures are shown to the rider, so both rounding independently
      // down would leave gross - discount disagreeing with the total.
      final fare = await quoteOf(9.60, discount: 2.40);

      expect(fare.totalPence, const Pence(960));
      expect(fare.discountPence, const Pence(240));
    });

    test('sweeps every penny value from GBP 1 to GBP 60', () async {
      // The bug was invisible to hand-picked fixtures because the obvious
      // ones (12.50, 5.00) happen to be float-exact.
      for (var p = 100; p <= 6000; p++) {
        final fare = await quoteOf(p / 100.0);
        expect(fare.totalPence.value, p,
            reason: 'GBP ${(p / 100.0).toStringAsFixed(2)} misparsed');
      }
    });
  });

  group('guards the rider would notice', () {
    test('flags legs that do not add up to the total', () async {
      // The screen shows both, so a disagreement reads as overcharging. The
      // fixture deliberately does NOT add up -- a fixture that does proves
      // nothing about live data.
      when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true,
                'legs': [
                  {'seq': 0, 'to_label': 'A', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 3000},
                  {'seq': 1, 'to_label': 'B', 'distance_meters': 1,
                   'duration_seconds': 1, 'fare_pence': 2000},
                ],
                'total_pence': 9999,
                'stops_count': 1, 'distance_meters': 2, 'duration_seconds': 2,
              }));

      final fare = ((await repo.estimate(
        pickup: pickup, dropoff: dropoff,
        waypoints: const [LatLng(1, 1)],
      )) as Ok<FareEstimate>).value;

      expect(fare.legsTotal, const Pence(5000));
      expect(fare.legsReconcile, isFalse);
    });

    test('a single-leg quote always reconciles', () async {
      when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 12.50},
                'distance_meters': 100, 'duration_seconds': 60,
              }));

      final fare = ((await repo.estimate(pickup: pickup, dropoff: dropoff))
          as Ok<FareEstimate>).value;

      expect(fare.legsReconcile, isTrue);
    });

    test('a multi-stop discount is unknown, not zero', () async {
      // The server sends no breakdown on this path. The discount IS applied
      // to the total; we just cannot itemise it. Reading the absence as "no
      // discount" would tell the rider something false.
      when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'multi_stop': true, 'legs': [], 'total_pence': 5000,
                'stops_count': 1, 'distance_meters': 1, 'duration_seconds': 1,
              }));

      final fare = ((await repo.estimate(
        pickup: pickup, dropoff: dropoff,
        waypoints: const [LatLng(1, 1)],
      )) as Ok<FareEstimate>).value;

      expect(fare.discountKnown, isFalse);
      expect(fare.hasDiscount, isFalse);
    });

    test('a malformed polyline costs the preview, not the quote', () async {
      // route is optional by design -- the map falls back to a straight line.
      // Throwing here would lose the fare over a bad coordinate.
      when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'estimate': {'total': 12.50},
                'distance_meters': 100, 'duration_seconds': 60,
                'route': [
                  {'lat': 1.0, 'lng': 2.0},
                  {'lat': null, 'lng': 3.0},
                ],
              }));

      final fare = ((await repo.estimate(pickup: pickup, dropoff: dropoff))
          as Ok<FareEstimate>).value;

      expect(fare.route, isNull);
      expect(fare.totalPence, const Pence(1250));
    });

    test('refuses a sixth stop when quoting, not just when booking', () async {
      // Quoting a six-stop fare and then refusing it at the book button
      // would be worse than refusing the sixth stop as it is added.
      final result = await repo.estimate(
        pickup: pickup,
        dropoff: dropoff,
        waypoints: const [
          LatLng(1, 1), LatLng(2, 2), LatLng(3, 3),
          LatLng(4, 4), LatLng(5, 5), LatLng(6, 6),
        ],
      );

      expect((result as Err).error.code, 'VALIDATION_FAILED');
      verifyNever(() => api.post<Map<String, dynamic>>(any(),
          body: any(named: 'body')));
    });
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
