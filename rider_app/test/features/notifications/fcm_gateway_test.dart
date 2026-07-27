import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/notifications/fake_fcm_gateway.dart';
import 'package:hoppin_rider/features/notifications/fcm_gateway.dart';

/// NOTIF-01 — the L1c boundary.
///
/// The whole point of this file: it needs NO firebase mock and NO MethodChannel
/// mock. If either ever appears here, the boundary has leaked and the isolation
/// contract (firebase imports live in exactly two files) is broken.
void main() {
  group('NOTIF-01: NoopFcmGateway is the provider default', () {
    test('fcmGatewayProvider defaults to the no-op — never a real SDK', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(fcmGatewayProvider),
        isA<NoopFcmGateway>(),
        reason:
            'The live target IS the no-op (the StripeSdkGateway contract). If '
            'this is ever a Firebase gateway by default, every test and the '
            'demo would touch Firebase.initializeApp and crash.',
      );
    });

    test('requestPermission reports unsupported — never a fabricated grant',
        () async {
      expect(
        await const NoopFcmGateway().requestPermission(),
        FcmPermission.unsupported,
        reason:
            'Push delivery is GATED. The honest answer is "unsupported", never '
            'a fake "granted".',
      );
    });

    test('token() is null — never a fabricated token', () async {
      expect(
        await const NoopFcmGateway().token(),
        isNull,
        reason:
            'A fabricated token would be written to the backend database. The '
            'no-op must return null.',
      );
    });

    test('onMessage() is an empty stream that completes', () async {
      expect(
        await const NoopFcmGateway().onMessage().toList(),
        isEmpty,
        reason: 'The no-op never emits a synthetic push.',
      );
    });

    test('onMessageOpened() is an empty stream that completes', () async {
      expect(
        await const NoopFcmGateway().onMessageOpened().toList(),
        isEmpty,
        reason:
            'PushNavigationHost listens to this. An empty stream is what makes '
            'the host a free no-op in every test and in the demo.',
      );
    });

    test('initialMessage() is null — no cold-start push', () async {
      expect(
        await const NoopFcmGateway().initialMessage(),
        isNull,
        reason: 'Nothing cold-started us. Say so.',
      );
    });

    test('nothing on the no-op throws', () async {
      const gateway = NoopFcmGateway();
      await expectLater(
        Future.wait<void>([
          gateway.requestPermission(),
          gateway.token(),
          gateway.initialMessage(),
          gateway.onMessage().toList(),
          gateway.onMessageOpened().toList(),
        ]),
        completes,
        reason:
            'The GATED path must degrade silently, never throw into the app.',
      );
    });
  });

  group('NOTIF-01: PushMessage / PushType catalogue', () {
    test('PushType carries the 9 assumed values (gap 15 catalogue)', () {
      expect(
        PushType.values,
        containsAll(<PushType>[
          PushType.driverAssigned,
          PushType.driverArriving,
          PushType.driverArrived,
          PushType.tripStarted,
          PushType.tripCompleted,
          PushType.tripCancelled,
          PushType.newMessage,
          PushType.promo,
          PushType.unknown,
        ]),
        reason:
            'The catalogue is ASSUMED (gap 15) and relayed. Unknown values '
            'degrade to PushType.unknown rather than throwing.',
      );
    });

    test('pushTypeFromWire maps the snake_case wire values', () {
      expect(pushTypeFromWire('driver_assigned'), PushType.driverAssigned);
      expect(pushTypeFromWire('driver_arriving'), PushType.driverArriving);
      expect(pushTypeFromWire('driver_arrived'), PushType.driverArrived);
      expect(pushTypeFromWire('trip_started'), PushType.tripStarted);
      expect(pushTypeFromWire('trip_completed'), PushType.tripCompleted);
      expect(pushTypeFromWire('trip_cancelled'), PushType.tripCancelled);
      expect(pushTypeFromWire('new_message'), PushType.newMessage);
      expect(pushTypeFromWire('promo'), PushType.promo);
    });

    test('an unrecognised or null wire type degrades to unknown, never throws',
        () {
      expect(
        pushTypeFromWire('something_the_backend_invented_later'),
        PushType.unknown,
        reason:
            'The schema is ASSUMED. A backend that ships a type we do not know '
            'must not crash the app — it degrades to the centre.',
      );
      expect(pushTypeFromWire(null), PushType.unknown);
      expect(pushTypeFromWire(''), PushType.unknown);
    });
  });

  group('NOTIF-01: FakeFcmGateway (demo only — pure Dart, zero firebase)', () {
    test('scripted() emits the demo push script on onMessage', () async {
      final emitted = await FakeFcmGateway.scripted().onMessage().toList();

      expect(
        emitted.map((m) => m.type).toList(),
        <PushType>[
          PushType.driverAssigned,
          PushType.driverArrived,
          PushType.newMessage,
        ],
        reason:
            'The demo stage needs a non-empty centre. This is a pure-Dart '
            'stream — it is NOT on the live path, and the live default stays '
            'the Noop.',
      );
    });

    test('scripted() does not fabricate an opened-push navigation', () async {
      expect(
        await FakeFcmGateway.scripted().onMessageOpened().toList(),
        isEmpty,
        reason:
            'A fake that auto-navigates the demo would be a surprise, not a '
            'demo. Taps are the presenter\'s job.',
      );
    });

    test('scripted() still refuses to fabricate a device token', () async {
      expect(
        await FakeFcmGateway.scripted().token(),
        isNull,
        reason:
            'Even the demo fake must not mint a token — gap 69 means we never '
            'register one anyway.',
      );
    });
  });
}
