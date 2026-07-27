import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hoppin_rider/features/location/location_service.dart';

/// SAFETY-01 — `LocationService.currentPosition()`.
///
/// The contract this file pins is a SAFETY contract, not a UX one:
///
///   * it is BOUNDED (a hanging OS read resolves within the timeout),
///   * it returns `null` on EVERY failure path,
///   * it NEVER throws, and
///   * it NEVER prompts — the OS permission dialog must never stand between a
///     frightened rider and the SOS button.
///
/// Anything that escapes as an exception, or hangs, would BLOCK an SOS. A
/// safety feature that fails closed on a denied permission is worse than one
/// that sends an imprecise alert.
///
/// `GeolocatorLocationService` takes an injectable position reader + permission
/// probe (defaulting to the real geolocator statics) so every failure path is
/// drivable from a test without a MethodChannel mock (the project forbids those
/// — fakes are injected, never channel-mocked).
void main() {
  group('GeolocatorLocationService.currentPosition', () {
    Position position(double lat, double lng) => Position(
          latitude: lat,
          longitude: lng,
          timestamp: DateTime.utc(2026, 7, 12),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );

    test('returns the coordinates when permission is granted and the read '
        'succeeds', () async {
      final svc = GeolocatorLocationService(
        checkPermission: () async => true,
        readPosition: ({required Duration timeout}) async =>
            position(52.5862, -2.1281),
      );

      final pos = await svc.currentPosition();

      expect(pos, isNotNull,
          reason: 'a granted, successful read must yield coordinates — '
              'SAFETY-01 requires trip + GPS');
      expect(pos!.lat, 52.5862,
          reason: 'the latitude must be passed through unchanged');
      expect(pos.lng, -2.1281,
          reason: 'the longitude must be passed through unchanged');
    });

    test('returns null WITHOUT prompting when permission is absent', () async {
      var reads = 0;
      final svc = GeolocatorLocationService(
        checkPermission: () async => false,
        readPosition: ({required Duration timeout}) async {
          reads++;
          return position(1, 1);
        },
      );

      final pos = await svc.currentPosition();

      expect(pos, isNull,
          reason: 'no permission means no fix — but it must NOT throw, so the '
              'SOS still fires with a degraded payload');
      expect(reads, 0,
          reason: 'the OS permission dialog must NEVER gate the panic path — '
              'currentPosition() short-circuits instead of prompting');
    });

    test('returns null when the permission probe itself throws', () async {
      final svc = GeolocatorLocationService(
        checkPermission: () async => throw Exception('plugin exploded'),
        readPosition: ({required Duration timeout}) async => position(1, 1),
      );

      await expectLater(svc.currentPosition(), completion(isNull),
          reason: 'a throwing permission probe must degrade to null, never '
              'escape as an exception that would block the SOS');
    });

    test('returns null on a PermissionDeniedException', () async {
      final svc = GeolocatorLocationService(
        checkPermission: () async => true,
        readPosition: ({required Duration timeout}) async =>
            throw const PermissionDeniedException('denied'),
      );

      await expectLater(svc.currentPosition(), completion(isNull),
          reason: 'a denied permission degrades the payload; it never throws');
    });

    test('returns null on a LocationServiceDisabledException', () async {
      final svc = GeolocatorLocationService(
        checkPermission: () async => true,
        readPosition: ({required Duration timeout}) async =>
            throw const LocationServiceDisabledException(),
      );

      await expectLater(svc.currentPosition(), completion(isNull),
          reason: 'location services switched off degrades the payload; '
              'it never throws');
    });

    test('returns null on a TimeoutException', () async {
      final svc = GeolocatorLocationService(
        checkPermission: () async => true,
        readPosition: ({required Duration timeout}) async =>
            throw TimeoutException('too slow'),
      );

      await expectLater(svc.currentPosition(), completion(isNull),
          reason: 'a plugin-raised timeout degrades the payload; it never '
              'throws');
    });

    test('returns null on an arbitrary plugin error (bare catch)', () async {
      final svc = GeolocatorLocationService(
        checkPermission: () async => true,
        // Web geolocation refusals surface as bare, untyped errors — this is
        // exactly the class of failure a typed `on FirebaseException`-style
        // catch would miss.
        readPosition: ({required Duration timeout}) async =>
            throw StateError('browser refused'),
      );

      await expectLater(svc.currentPosition(), completion(isNull),
          reason: 'NO throw may survive currentPosition() — a bare catch is '
              'the last line of defence for the SOS');
    });

    test('is BOUNDED — a hanging read resolves null at the timeout, it does '
        'not hang forever', () {
      fakeAsync((async) {
        // A read that never completes: the OS/browser accepted the request and
        // simply never answered. Without a bound, `await currentPosition()`
        // would hang and the SOS would never fire.
        final svc = GeolocatorLocationService(
          checkPermission: () async => true,
          readPosition: ({required Duration timeout}) =>
              Completer<Position>().future,
        );

        ({double lat, double lng})? result;
        var settled = false;
        unawaited(svc
            .currentPosition(timeout: const Duration(seconds: 5))
            .then((value) {
          result = value;
          settled = true;
        }));

        async.elapse(const Duration(seconds: 4));
        expect(settled, isFalse,
            reason: 'the read is still within its 5s budget');

        async.elapse(const Duration(seconds: 2));
        expect(settled, isTrue,
            reason: 'a hanging location read MUST resolve at the 5s bound — an '
                'unbounded await is a safety defect: it would block the alarm');
        expect(result, isNull,
            reason: 'the bound expires to null, degrading the payload rather '
                'than blocking the SOS');
      });
    });
  });
}
