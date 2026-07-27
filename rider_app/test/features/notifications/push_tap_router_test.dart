import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/notifications/fcm_gateway.dart';
import 'package:hoppin_rider/features/notifications/push_tap_router.dart';

/// NOTIF-01 — the tap-router and its deep-link allowlist.
///
/// `deep_link` is attacker-influenceable in exactly the way `ad.target_url` is
/// (gap 36 asks for client-side allowlisting of ad targets). A push that names
/// a route we do not recognise must NEVER be followed blind — the rider lands
/// on the notification centre, where they can read the notification themselves.
void main() {
  PushMessage msg(
    PushType type, {
    String? rideId,
    String? deepLink,
  }) =>
      PushMessage(type: type, rideId: rideId, deepLink: deepLink);

  group('NOTIF-01: routeForPush derives a route from type + ride_id', () {
    test('new_message + ride id → the trip chat', () {
      expect(
        routeForPush(msg(PushType.newMessage, rideId: 'r1')),
        '/trip/r1/chat',
        reason: 'A message push should land the rider in the thread.',
      );
    });

    test('trip_completed + ride id → the receipt', () {
      expect(
        routeForPush(msg(PushType.tripCompleted, rideId: 'r1')),
        '/trip/r1/receipt',
        reason: 'A completed trip is done — the useful screen is the receipt.',
      );
    });

    for (final type in <PushType>[
      PushType.driverAssigned,
      PushType.driverArriving,
      PushType.driverArrived,
      PushType.tripStarted,
      PushType.tripCancelled,
    ]) {
      test('$type + ride id → the trip screen', () {
        expect(
          routeForPush(msg(type, rideId: 'r1')),
          '/trip/r1',
          reason: 'Every trip-phase push belongs on the trip screen.',
        );
      });
    }

    test('promo → the notification centre', () {
      expect(
        routeForPush(msg(PushType.promo)),
        '/notifications',
        reason: 'A promo has no trip to open.',
      );
    });

    test('unknown type → the notification centre, never a crash, never a drop',
        () {
      expect(
        routeForPush(msg(PushType.unknown, rideId: 'r1')),
        '/notifications',
        reason:
            'The push schema is ASSUMED (gap 15). A type we do not know must '
            'degrade to the centre — the rider still SEES the notification.',
      );
    });

    test('every trip-scoped type with a NULL ride id falls back to the centre',
        () {
      for (final type in PushType.values) {
        expect(
          routeForPush(msg(type)),
          '/notifications',
          reason:
              'With no ride_id there is no trip route to build. Never build '
              '"/trip/null".',
        );
      }
    });
  });

  group('NOTIF-01: an allowlisted deep_link is obeyed', () {
    test('an in-app trip path is followed', () {
      expect(
        routeForPush(msg(PushType.promo, deepLink: '/trip/abc')),
        '/trip/abc',
        reason: 'The backend gets to say where a push should land — if, and '
            'only if, the target is an in-app path we recognise.',
      );
    });

    test('the centre itself is allowlisted', () {
      expect(
        routeForPush(msg(PushType.unknown, deepLink: '/notifications')),
        '/notifications',
      );
    });

    test('the history path is allowlisted', () {
      expect(
        routeForPush(msg(PushType.promo, deepLink: '/history')),
        '/history',
      );
    });

    test('deep_link BEATS the derived route when it is allowlisted', () {
      expect(
        routeForPush(
          msg(PushType.newMessage, rideId: 'r1', deepLink: '/history'),
        ),
        '/history',
        reason: 'Precedence: allowlisted deep_link → derived → centre.',
      );
    });
  });

  group('NOTIF-01 SECURITY: a non-allowlisted deep_link is REJECTED', () {
    const hostile = <String>[
      'https://evil.example/',
      'http://evil.example/steal',
      '//evil.example',
      '../../etc/passwd',
      '/trip/../../admin',
      'javascript:alert(1)',
      'tel:+447700900000',
      'mailto:a@b.c',
      'evil.example/trip/1',
      '/unknown-route',
      '',
      '   ',
    ];

    for (final link in hostile) {
      test('"$link" is rejected → /notifications', () {
        expect(
          routeForPush(msg(PushType.promo, deepLink: link)),
          '/notifications',
          reason:
              'A push payload is attacker-influenceable. We NEVER navigate to '
              'an unrecognised target — the rider lands on the centre and '
              'reads the notification for themselves.',
        );
      });
    }

    test('a hostile deep_link does not even beat a derived trip route', () {
      expect(
        routeForPush(
          msg(
            PushType.newMessage,
            rideId: 'r1',
            deepLink: 'https://evil.example/',
          ),
        ),
        '/trip/r1/chat',
        reason:
            'Rejecting the link falls through to the DERIVED route — the push '
            'is still delivered honestly, it is just not attacker-steered.',
      );
    });
  });
}
