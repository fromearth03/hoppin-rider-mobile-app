import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/settings/data/preferences_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

void main() {
  late _MockApi api;
  late PreferencesRepository repo;

  setUp(() {
    api = _MockApi();
    repo = PreferencesRepository(api);
  });

  group('read', () {
    test('reads the {"preferences": {...}} envelope the handler returns',
        () async {
      when(() => api.get<dynamic>('/me/preferences'))
          .thenAnswer((_) async => const Ok<dynamic>({
                'preferences': {
                  'push_trip_updates': true,
                  'sound_offer_chime': false,
                },
              }));

      final prefs = ((await repo.read()) as Ok<RiderPreferences>).value;

      expect(prefs.pushTripUpdates, isTrue);
      expect(prefs.soundOfferChime, isFalse);
    });

    test('a key the rider has never set reads as null, not as false', () async {
      // GetMyPreferences documents that unset keys are simply ABSENT and "the
      // app applies its own defaults". Collapsing absent to false would show
      // the rider notifications are off when the server never said so — and
      // the first toggle would then look like it changed nothing.
      when(() => api.get<dynamic>('/me/preferences'))
          .thenAnswer((_) async => const Ok<dynamic>({'preferences': {}}));

      final prefs = ((await repo.read()) as Ok<RiderPreferences>).value;

      expect(prefs.pushTripUpdates, isNull);
      expect(prefs.soundOfferChime, isNull);
    });

    test('a non-bool value for a bool key reads as null, not as true',
        () async {
      // The column is free-form JSONB; only PATCH validates. A row written by
      // another client (or an older build) can hold anything.
      when(() => api.get<dynamic>('/me/preferences'))
          .thenAnswer((_) async => const Ok<dynamic>({
                'preferences': {
                  'push_trip_updates': 'yes',
                  'sound_offer_chime': 1,
                },
              }));

      final prefs = ((await repo.read()) as Ok<RiderPreferences>).value;

      expect(prefs.pushTripUpdates, isNull);
      expect(prefs.soundOfferChime, isNull);
    });

    test('a missing envelope is an empty set of preferences, not a crash',
        () async {
      when(() => api.get<dynamic>('/me/preferences'))
          .thenAnswer((_) async => const Ok<dynamic>({}));

      final prefs = ((await repo.read()) as Ok<RiderPreferences>).value;

      expect(prefs.pushTripUpdates, isNull);
    });

    test('surfaces a failure rather than pretending everything is off',
        () async {
      when(() => api.get<dynamic>('/me/preferences')).thenAnswer(
          (_) async => const Err<dynamic>(ApiException('INTERNAL', 'boom', 500)));

      expect((await repo.read()) as Err, isA<Err>());
    });
  });

  group('update', () {
    test('patches only the key that changed', () async {
      // PatchMyPreferences merges with JSONB ||, so sending the whole object
      // is unnecessary — and sending a key the rider did not touch would
      // write a value the server had deliberately left unset.
      when(() => api.patch<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok<dynamic>({
                'preferences': {'push_trip_updates': false},
              }));

      await repo.update(pushTripUpdates: false);

      final captured = verify(() => api.patch<dynamic>('/me/preferences',
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(captured, {'push_trip_updates': false});
      expect(captured.containsKey('sound_offer_chime'), isFalse);
    });

    test('sends the server key sound_offer_chime for the sound toggle',
        () async {
      when(() => api.patch<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok<dynamic>({
                'preferences': {'sound_offer_chime': true},
              }));

      await repo.update(soundOfferChime: true);

      final captured = verify(() => api.patch<dynamic>('/me/preferences',
          body: captureAny(named: 'body'))).captured.single as Map;

      expect(captured, {'sound_offer_chime': true});
    });

    test('returns the merged object the server echoes back', () async {
      // The handler returns the FULL merged preferences, not just the patch,
      // so the screen can settle on server truth rather than its own guess.
      when(() => api.patch<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok<dynamic>({
                'preferences': {
                  'push_trip_updates': false,
                  'sound_offer_chime': true,
                },
              }));

      final prefs =
          ((await repo.update(pushTripUpdates: false)) as Ok<RiderPreferences>)
              .value;

      expect(prefs.pushTripUpdates, isFalse);
      expect(prefs.soundOfferChime, isTrue,
          reason: 'the untouched key survives the merge and comes back');
    });

    test('does not call the server when nothing was asked to change',
        () async {
      final result = await repo.update();

      expect(result, isA<Ok<RiderPreferences>>());
      verifyNever(() => api.patch<dynamic>(any(), body: any(named: 'body')));
    });

    test('surfaces the server error so the toggle can go back', () async {
      when(() => api.patch<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Err<dynamic>(ApiException(
              'VALIDATION_FAILED', 'push_trip_updates must be true or false',
              400)));

      final result = await repo.update(pushTripUpdates: true);

      expect((result as Err).error.message,
          'push_trip_updates must be true or false',
          reason: 'server copy renders verbatim');
    });
  });
}
