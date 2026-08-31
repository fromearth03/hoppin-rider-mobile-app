import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/trip/data/ride_actions_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;

  setUp(() {
    api = _MockApi();
  });

  test('cancel sends the contract body to the contract path', () async {
    // PATCH /rides/:id/cancel with canceled_by_user_id + actor_type, straight
    // from ride_handler.go — actor_type must be "rider" and the user id is
    // the Supabase subject, or the ownership check 403s.
    when(() => api.patch<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Ok({'message': 'Ride cancelled'}));

    final repo = RideActionsRepository(api, () => 'user-77');
    final result = await repo.cancelRide('ride-9');

    expect(result, isA<Ok<void>>());
    final captured = verify(() => api.patch<Map<String, dynamic>>(
          captureAny(),
          body: captureAny(named: 'body'),
        )).captured;
    expect(captured[0], '/rides/ride-9/cancel');
    expect(captured[1], {
      'canceled_by_user_id': 'user-77',
      'actor_type': 'rider',
    });
  });

  test('a server rejection surfaces unchanged', () async {
    when(() => api.patch<Map<String, dynamic>>(any(), body: any(named: 'body')))
        .thenAnswer((_) async => const Err(ApiException('ILLEGAL_TRANSITION',
            'ride cannot be cancelled from its current state', 400)));

    final repo = RideActionsRepository(api, () => 'user-77');
    final result = await repo.cancelRide('ride-9');

    expect((result as Err).error.code, 'ILLEGAL_TRANSITION');
    expect(result.error.message,
        'ride cannot be cancelled from its current state');
  });

  test('no signed-in user or empty ride id refuses before the network',
      () async {
    final repo = RideActionsRepository(api, () => null);

    expect((await repo.cancelRide('ride-9')) is Err, isTrue);
    expect(
        (await RideActionsRepository(api, () => 'user-77').cancelRide(''))
            is Err,
        isTrue);
    verifyZeroInteractions(api);
  });
}
