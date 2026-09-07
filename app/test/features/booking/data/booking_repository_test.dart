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
        (label: 'Stop 1', position: LatLng(1, 1)), (label: 'Stop 2', position: LatLng(2, 2)), (label: 'Stop 3', position: LatLng(3, 3)),
        (label: 'Stop 4', position: LatLng(4, 4)), (label: 'Stop 5', position: LatLng(5, 5)), (label: 'Stop 6', position: LatLng(6, 6)),
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
        (label: 'Stop 1', position: LatLng(1, 1)), (label: 'Stop 2', position: LatLng(2, 2)), (label: 'Stop 3', position: LatLng(3, 3)),
        (label: 'Stop 4', position: LatLng(4, 4)), (label: 'Stop 5', position: LatLng(5, 5)),
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
  test('sends each stop with the name the rider chose', () async {
    // The bug this covers: only lat/lng went to the server, so a stop the
    // rider picked as "Molineux Stadium" was stored nameless and the trip
    // screen rendered it as "Stop 1" — the name existed on the confirm screen
    // and nowhere after it.
    Map<String, dynamic>? sent;
    when(() => api.post<Map<String, dynamic>>('/rides/request',
        body: any(named: 'body'))).thenAnswer((inv) async {
      sent = inv.namedArguments[#body] as Map<String, dynamic>;
      return const Ok({'request_id': 'r1'});
    });

    await repo.request(
      pickup: pickup,
      dropoff: dropoff,
      vehicleCategoryId: 'cat-1',
      waypoints: const [
        (label: 'Molineux Stadium', position: LatLng(52.59, -2.13)),
      ],
    );

    final stops = sent!['waypoints'] as List;
    expect(stops.single['label'], 'Molineux Stadium');
    expect(stops.single['lat'], 52.59);
  });

  test('a blank stop label is omitted rather than sent empty', () async {
    Map<String, dynamic>? sent;
    when(() => api.post<Map<String, dynamic>>('/rides/request',
        body: any(named: 'body'))).thenAnswer((inv) async {
      sent = inv.namedArguments[#body] as Map<String, dynamic>;
      return const Ok({'request_id': 'r1'});
    });

    await repo.request(
      pickup: pickup,
      dropoff: dropoff,
      vehicleCategoryId: 'cat-1',
      waypoints: const [(label: '   ', position: LatLng(1, 1))],
    );

    expect((sent!['waypoints'] as List).single.containsKey('label'), isFalse);
  });

}
