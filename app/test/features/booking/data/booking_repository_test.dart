import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/booking/data/booking_repository.dart';
import 'package:hoppin_rider/features/booking/data/fare_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late BookingRepository repo;

  const pickup = LatLng(52.586, -2.128);
  const dropoff = LatLng(52.593, -2.110);

  setUp(() {
    api = _MockApi();
    repo = BookingRepository(api);
  });

  test('returns the request id from a 202', () async {
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({'request_id': 'req-42'}));

    final result = await repo.request(
        pickup: pickup, dropoff: dropoff, vehicleCategoryId: 'cat-1');

    expect((result as Ok<BookingRequest>).value.requestId, 'req-42');
  });

  test('refuses more than five stops before calling', () async {
    // The server caps waypoints at 5. Failing here costs nothing; failing
    // server-side costs a round trip and a worse message.
    final result = await repo.request(
      pickup: pickup,
      dropoff: dropoff,
      vehicleCategoryId: 'cat-1',
      waypoints: const [
        LatLng(1, 1), LatLng(2, 2), LatLng(3, 3),
        LatLng(4, 4), LatLng(5, 5), LatLng(6, 6),
      ],
    );

    expect((result as Err).error.code, 'VALIDATION_FAILED');
    verifyNever(() => api.post<Map<String, dynamic>>(any(),
        body: any(named: 'body')));
  });

  test('accepts exactly five stops', () async {
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({'request_id': 'req-1'}));

    final result = await repo.request(
      pickup: pickup,
      dropoff: dropoff,
      vehicleCategoryId: 'cat-1',
      waypoints: const [
        LatLng(1, 1), LatLng(2, 2), LatLng(3, 3),
        LatLng(4, 4), LatLng(5, 5),
      ],
    );

    expect(result, isA<Ok<BookingRequest>>());
  });

  test('surfaces a booking refusal with its code intact', () async {
    // NO_PAYMENT_METHOD, ACTIVE_TRIP_EXISTS, OUTSIDE_SERVICE_AREA and the
    // rest each need a distinct screen response.
    when(() => api.post<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => Err(ApiException(
            'NO_PAYMENT_METHOD', 'add a payment card to book a ride', 402)));

    final result = await repo.request(
        pickup: pickup, dropoff: dropoff, vehicleCategoryId: 'cat-1');

    final err = (result as Err).error;
    expect(err.code, 'NO_PAYMENT_METHOD');
    expect(err.message, 'add a payment card to book a ride',
        reason: 'server copy is shown verbatim');
  });
}
