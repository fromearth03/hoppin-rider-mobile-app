import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/payments/data/receipts_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late ReceiptsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = ReceiptsRepository(api);
  });

  test('reads the receipt and keeps money as pence', () async {
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1',
              'ride_category': 'standard',
              'fare_pence': 1238,
              'waiting_pence': 0,
              'total_pence': 1238,
              'currency': 'GBP',
              'status': 'captured',
              'distance_miles': 4.7,
              'pickup_time': '2026-08-31T09:00:00Z',
              'dropoff_time': '2026-08-31T09:20:00Z',
              'provider_payment_id': 'pi_123',
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.farePence, const Pence(1238));
    expect(r.totalPence, const Pence(1238));
    expect(r.distanceMiles, 4.7);
    expect(r.hasWaitingCharge, isFalse);
  });

  test('a waiting charge is shown only when it is non-zero', () async {
    // A zero waiting line tells the rider nothing and implies they were
    // nearly charged for waiting.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1', 'fare_pence': 1000, 'waiting_pence': 250,
              'total_pence': 1250, 'currency': 'GBP', 'status': 'captured',
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.hasWaitingCharge, isTrue);
    expect(r.waitingPence, const Pence(250));
  });

  test('an uncharged ride has a null total rather than zero', () async {
    // "Not charged yet" and "free" are different things and must not both
    // render as GBP 0.00.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1', 'fare_pence': null, 'waiting_pence': null,
              'total_pence': null, 'currency': 'GBP', 'status': 'pending',
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.totalPence, isNull);
    expect(r.farePence, isNull);
  });

  test('does not model platform commission', () async {
    // It was removed from the receipt deliberately: it let a rider back out
    // driver earnings. Modelling it would resurrect a field the backend
    // withdrew on purpose.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1', 'fare_pence': 1000, 'total_pence': 1000,
              'currency': 'GBP', 'status': 'captured',
              'platform_commission_pence': 200,
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.totalPence, const Pence(1000));
    // No accessor exists for commission; this test documents the intent.
  });

  test('a malformed pickup_time parses as null rather than throwing', () async {
    // This endpoint returns a single object, not a list, so there is no row
    // to skip - but a stray non-string type must not take the whole parse
    // down with it.
    when(() => api.get<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => const Ok({
              'ride_id': 'r1', 'fare_pence': 1000, 'total_pence': 1000,
              'currency': 'GBP', 'status': 'captured',
              'pickup_time': 1234567890,
            }));

    final r = ((await repo.forRide('r1')) as Ok<Receipt>).value;

    expect(r.pickupTime, isNull);
  });
}
