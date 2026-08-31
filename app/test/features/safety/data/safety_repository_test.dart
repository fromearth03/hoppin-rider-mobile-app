import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/safety/data/safety_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late SafetyRepository repo;

  setUp(() {
    api = _MockApi();
    repo = SafetyRepository(api);
  });

  group('raiseSos', () {
    test('sends position and ride when both are known', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({'id': 'sos-1'}));

      await repo.raiseSos(rideId: 'ride-1', lat: 52.58, lng: -2.12);

      final body = verify(() => api.post<Map<String, dynamic>>('/me/sos',
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body['ride_id'], 'ride-1');
      expect(body['lat'], 52.58);
      expect(body['lng'], -2.12);
    });

    test('still raises when there is no position fix', () async {
      // A rider in danger with no GPS must still be able to call for help.
      // Sending 0,0 would put them in the Atlantic on the safety dashboard.
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({'id': 'sos-2'}));

      final result = await repo.raiseSos();

      expect(result, isA<Ok>());
      final body = verify(() => api.post<Map<String, dynamic>>(any(),
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(body.containsKey('lat'), isFalse);
      expect(body.containsKey('ride_id'), isFalse);
    });

    test('surfaces a failure rather than pretending help is coming', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async =>
              Err(ApiException('INTERNAL', 'server error', 500)));

      final result = await repo.raiseSos();

      expect((result as Err).error.code, 'INTERNAL',
          reason: 'a silent failure here is the worst possible outcome');
    });
  });

  group('emergency contacts', () {
    test('reads the list', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'contacts': [
                  {'id': 'c1', 'name': 'Mum', 'phone': '+447700900123',
                   'relationship': 'parent'},
                ],
              }));

      final result = await repo.listContacts();
      final list = (result as Ok<List<EmergencyContact>>).value;

      expect(list, hasLength(1));
      expect(list.first.name, 'Mum');
      expect(list.first.relationship, 'parent');
    });

    test('a contact with no relationship reads as null, not empty', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'contacts': [
                  {'id': 'c2', 'name': 'Sam', 'phone': '+447700900124',
                   'relationship': ''},
                ],
              }));

      final list =
          ((await repo.listContacts()) as Ok<List<EmergencyContact>>).value;

      expect(list.first.relationship, isNull,
          reason: 'so the row renders no relationship line at all');
    });

    test('refuses a contact with no phone before calling', () async {
      final result = await repo.addContact(name: 'Sam', phone: '  ');

      expect((result as Err).error.code, 'VALIDATION_FAILED');
      verifyNever(() => api.post<Map<String, dynamic>>(any(),
          body: any(named: 'body')));
    });

    test('refuses a contact with no name before calling', () async {
      final result = await repo.addContact(name: '', phone: '+447700900125');

      expect((result as Err).error.code, 'VALIDATION_FAILED');
      verifyNever(() => api.post<Map<String, dynamic>>(any(),
          body: any(named: 'body')));
    });
  });

  group('share link', () {
    test('reads the token and url', () async {
      when(() => api.post<Map<String, dynamic>>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => const Ok({
                'token': 'tok-1',
                'url': 'https://api.hoppin.tech/trip-share/tok-1',
              }));

      final link =
          ((await repo.createShareLink('ride-1')) as Ok<ShareLink>).value;

      expect(link.token, 'tok-1');
      expect(link.url, contains('trip-share'));
    });
  });

  group('platform contacts', () {
    test('missing numbers read as null so no dead row is rendered', () async {
      // The server returns blanks rather than 404 when no row is configured.
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => const Ok({
                'support_email': 'help@hoppin.tech',
                'support_phone': '',
                'emergency_phone': '999',
                'whatsapp_number': '',
              }));

      final c =
          ((await repo.platformContacts()) as Ok<PlatformContacts>).value;

      expect(c.supportEmail, 'help@hoppin.tech');
      expect(c.supportPhone, isNull);
      expect(c.emergencyPhone, '999');
      expect(c.whatsappNumber, isNull);
    });
  });
}
