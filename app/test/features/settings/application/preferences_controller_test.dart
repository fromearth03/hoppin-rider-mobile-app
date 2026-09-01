import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/settings/application/preferences_controller.dart';
import 'package:hoppin_rider/features/settings/data/preferences_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements PreferencesRepository {}

void main() {
  late _MockRepo repo;
  late PreferencesController controller;

  setUp(() {
    repo = _MockRepo();
    controller = PreferencesController(repo);
  });

  group('load', () {
    test('adopts the server values', () async {
      when(() => repo.read()).thenAnswer((_) async => const Ok(
          RiderPreferences(pushTripUpdates: true, soundOfferChime: false)));

      await controller.load();

      expect(controller.state.pushTripUpdates, isTrue);
      expect(controller.state.soundOfferChime, isFalse);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isReady, isTrue);
    });

    test('an unset key defaults to on, matching the server default posture',
        () async {
      // Absent means "never set" — the server tells us to apply our own
      // default. Trip updates and the arrival chime are the app's useful
      // defaults, so an unset key reads as ON rather than as a rider who
      // opted out.
      when(() => repo.read()).thenAnswer((_) async =>
          const Ok(RiderPreferences(
              pushTripUpdates: null, soundOfferChime: null)));

      await controller.load();

      expect(controller.state.pushTripUpdates, isTrue);
      expect(controller.state.soundOfferChime, isTrue);
    });

    test('a failed load leaves the toggles unusable rather than guessing',
        () async {
      // A toggle rendered live over a failed read would let the rider "turn
      // off" something whose real state we never learned.
      when(() => repo.read()).thenAnswer(
          (_) async => const Err<RiderPreferences>(
              ApiException('INTERNAL', 'server error', 500)));

      await controller.load();

      expect(controller.state.isReady, isFalse);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.error, 'server error');
    });
  });

  group('setPushTripUpdates', () {
    setUp(() {
      when(() => repo.read()).thenAnswer((_) async => const Ok(
          RiderPreferences(pushTripUpdates: true, soundOfferChime: true)));
    });

    test('moves immediately, then settles on the server echo', () async {
      await controller.load();
      when(() => repo.update(pushTripUpdates: false)).thenAnswer((_) async =>
          const Ok(RiderPreferences(
              pushTripUpdates: false, soundOfferChime: true)));

      final pending = controller.setPushTripUpdates(false);
      // Optimistic: the switch must not sit on its old value waiting for a
      // round trip — that reads as a dead control.
      expect(controller.state.pushTripUpdates, isFalse);

      await pending;
      expect(controller.state.pushTripUpdates, isFalse);
      expect(controller.state.soundOfferChime, isTrue);
    });

    test('rolls back when the server refuses', () async {
      await controller.load();
      when(() => repo.update(pushTripUpdates: false)).thenAnswer((_) async =>
          const Err<RiderPreferences>(
              ApiException('INTERNAL', 'could not save', 500)));

      await controller.setPushTripUpdates(false);

      expect(controller.state.pushTripUpdates, isTrue,
          reason: 'a toggle that stayed off would lie about what was saved');
      expect(controller.state.error, 'could not save');
    });
  });

  group('setSoundOfferChime', () {
    test('patches the sound key only', () async {
      when(() => repo.read()).thenAnswer((_) async => const Ok(
          RiderPreferences(pushTripUpdates: true, soundOfferChime: true)));
      when(() => repo.update(soundOfferChime: false)).thenAnswer((_) async =>
          const Ok(RiderPreferences(
              pushTripUpdates: true, soundOfferChime: false)));

      await controller.load();
      await controller.setSoundOfferChime(false);

      verify(() => repo.update(soundOfferChime: false)).called(1);
      verifyNever(() => repo.update(pushTripUpdates: any(named:
          'pushTripUpdates')));
    });
  });
}
