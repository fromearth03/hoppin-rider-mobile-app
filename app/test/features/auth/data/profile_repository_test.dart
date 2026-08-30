import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late ProfileRepository repo;

  setUp(() {
    api = _MockApi();
    repo = ProfileRepository(api);
  });

  group('RiderProfile.fromJson', () {
    test('reads every field the API sends', () {
      final p = RiderProfile.fromJson(const {
        'full_name': 'Ada Lovelace',
        'phone_number': '+447700900123',
        'email': 'ada@example.com',
        'avatar_url': 'https://example.com/a.png',
        'date_of_birth': '1990-12-10',
        'rating': 4.31,
        'rating_count': 150,
      });

      expect(p.fullName, 'Ada Lovelace');
      expect(p.dateOfBirth, '1990-12-10');
      expect(p.rating, 4.31);
      expect(p.ratingCount, 150);
    });

    test('keeps rating null for a rider nobody has rated', () {
      final p = RiderProfile.fromJson(const {
        'full_name': 'New Rider',
        'phone_number': '',
        'email': 'new@example.com',
        'avatar_url': '',
        'date_of_birth': null,
        'rating': null,
        'rating_count': 0,
      });

      expect(p.rating, isNull,
          reason: 'a defaulted 5.0 would fabricate a rating nobody gave');
      expect(p.ratingCount, 0);
      expect(p.dateOfBirth, isNull);
    });

    test('treats the hidden phone placeholder as no phone', () {
      // The API already maps 'pending-<uid>' to '', but an empty string is
      // still "no phone" rather than a phone whose value is empty.
      final p = RiderProfile.fromJson(const {
        'full_name': 'Ada',
        'phone_number': '',
        'email': 'a@b.com',
        'avatar_url': '',
        'date_of_birth': null,
        'rating': null,
        'rating_count': 0,
      });

      expect(p.phoneNumber, isNull);
    });
  });

  group('patch', () {
    test('sends only the fields given', () async {
      when(() => api.patch<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'full_name': 'Ada',
                'phone_number': '',
                'email': 'a@b.com',
                'avatar_url': '',
                'date_of_birth': '1990-12-10',
                'rating': null,
                'rating_count': 0,
              }));

      await repo.patch(dateOfBirth: '1990-12-10');

      final body = verify(() => api.patch<Map<String, dynamic>>('/me/profile',
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body, {'date_of_birth': '1990-12-10'});
      expect(body.containsKey('full_name'), isFalse,
          reason: 'a null field means leave unchanged, not clear');
    });

    test('surfaces USER_NOT_FOUND rather than swallowing it', () async {
      // The signup trigger's exception handler can leave an auth user with no
      // profile row (see migration 124). This is how the app detects it.
      when(() => api.patch<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async =>
              Err(ApiException('USER_NOT_FOUND', 'profile not found', 404)));

      final result = await repo.patch(dateOfBirth: '1990-12-10');

      expect((result as Err).error.code, 'USER_NOT_FOUND');
    });
  });
}
