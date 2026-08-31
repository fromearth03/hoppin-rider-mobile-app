import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/geo.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/scheduling/data/scheduled_rides_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late ScheduledRidesRepository repo;

  setUp(() {
    api = _MockApi();
    repo = ScheduledRidesRepository(api);
  });

  group('create', () {
    test('sends the contract body with an RFC3339 UTC pickup time', () async {
      when(() =>
              api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'id': 'sr-1',
                'status': 'scheduled',
              }));

      final result = await repo.create(
        pickup: const LatLng(53.0235, -2.1774),
        dropoff: const LatLng(53.0044, -2.2734),
        pickupTime: DateTime.utc(2026, 9, 2, 14, 30),
        vehicleCategoryId: 'vc-9',
      );

      expect(result, isA<Ok<ScheduledRide>>());
      final captured = verify(() => api.post<Map<String, dynamic>>(
            captureAny(),
            body: captureAny(named: 'body'),
          )).captured;
      expect(captured[0], '/scheduled-rides');
      expect(captured[1], {
        'pickup_lat': 53.0235,
        'pickup_lng': -2.1774,
        'dropoff_lat': 53.0044,
        'dropoff_lng': -2.2734,
        'requested_pickup_time': '2026-09-02T14:30:00.000Z',
        'vehicle_category_id': 'vc-9',
      });
    });

    test('the 30-minute rejection surfaces the server copy verbatim',
        () async {
      when(() =>
              api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Err(ApiException(
              'VALIDATION_FAILED',
              'pickup time must be at least 30 minutes in the future',
              400)));

      final result = await repo.create(
        pickup: const LatLng(1, 2),
        dropoff: const LatLng(3, 4),
        pickupTime: DateTime.utc(2026, 9, 1, 0, 5),
      );

      expect((result as Err).error.message,
          'pickup time must be at least 30 minutes in the future');
    });
  });

  group('list', () {
    test('parses the enriched rows and drops idless ones', () async {
      when(() => api.get<dynamic>(any()))
          .thenAnswer((_) async => const Ok<dynamic>([
                {
                  'id': 'sr-1',
                  'status': 'scheduled',
                  'pickup': {'lat': 53.0, 'lng': -2.1},
                  'dropoff': {'lat': 53.1, 'lng': -2.2},
                  'requested_pickup_time': '2026-09-02T14:30:00Z',
                  'estimate_pence': 850,
                  'currency': 'GBP',
                  'vehicle_category': 'Standard',
                  'active_ride_id': null,
                },
                {'status': 'no id — dropped'},
              ]));

      final list =
          ((await repo.list()) as Ok<List<ScheduledRide>>).value;

      expect(list, hasLength(1));
      expect(list.first.id, 'sr-1');
      expect(list.first.estimatePence?.value, 850);
      expect(list.first.vehicleCategory, 'Standard');
      expect(list.first.requestedPickupTime, DateTime.utc(2026, 9, 2, 14, 30));
    });

    test('accepts a wrapped list too, in case the shape grows an envelope',
        () async {
      when(() => api.get<dynamic>(any())).thenAnswer((_) async =>
          const Ok<dynamic>({
            'scheduled_rides': [
              {'id': 'sr-2', 'status': 'scheduled'}
            ]
          }));

      final list =
          ((await repo.list()) as Ok<List<ScheduledRide>>).value;
      expect(list.single.id, 'sr-2');
    });
  });

  test('cancel DELETEs the row', () async {
    when(() => api.delete<dynamic>(any()))
        .thenAnswer((_) async => const Ok<dynamic>(null));

    final result = await repo.cancel('sr-1');

    expect(result, isA<Ok<void>>());
    verify(() => api.delete<dynamic>('/scheduled-rides/sr-1')).called(1);
  });
}
