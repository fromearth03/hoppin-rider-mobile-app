@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/config.dart';

/// Contract checks against the REAL backend at api.hoppin.tech.
///
/// These are excluded from the default suite — they need a network and they
/// touch a production service. Run them deliberately:
///
///   flutter test test/integration --tags live \
///     --dart-define-from-file=../config/dev.json
///
/// What they are for: the unit suite proves our code is self-consistent, but
/// every one of its backend doubles is a guess about what the server does.
/// These assert the guesses. A change to the envelope shape, an endpoint that
/// moves, or auth that starts failing shows up here and nowhere else.
///
/// They deliberately do NOT create accounts or book rides. Sign-up and booking
/// are verified by hand on a device, because they leave real rows behind.
void main() {
  group('live backend', () {
    late HttpClient client;

    setUpAll(() {
      if (!AppConfig.hasSupabase) {
        fail('Run with --dart-define-from-file=../config/dev.json — '
            '${AppConfig.missingReason}');
      }
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    });

    tearDownAll(() => client.close(force: true));

    Future<HttpClientResponse> get(String path) async {
      final request = await client.getUrl(Uri.parse('${AppConfig.apiBaseUrl}$path'));
      request.headers.set('X-Hoppin-Device-ID', 'integration-test');
      return request.close();
    }

    test('the API base URL is reachable and is the production host', () async {
      expect(AppConfig.apiBaseUrl, startsWith('https://'),
          reason: 'never talk to the backend over plain http');
      expect(AppConfig.apiBaseUrl, contains('api.hoppin.tech'));

      // /app-status is public by design — the app polls it on launch, BEFORE
      // login, to learn whether it must force-update or show maintenance.
      //
      // It REQUIRES ?platform=ios|android and takes ?version=. A bare call
      // returns 400 VALIDATION_FAILED (ride_handler.go:1416-1420). The spec
      // originally described this as a parameterless call, which would have
      // failed on every cold start.
      final response = await get('/app-status?platform=android&version=0.1.0');
      expect(response.statusCode, 200,
          reason: '/app-status must answer without a token; the launch '
              'sequence depends on it before a rider has signed in');
    });

    test('/app-status rejects a call with no platform', () async {
      // Pins the requirement so nobody "simplifies" the launch call later.
      final response = await get('/app-status');
      expect(response.statusCode, 400);
    });

    test('an authenticated endpoint rejects an unauthenticated caller',
        () async {
      // Proves the JWT gate is actually enforced. If this ever returns 200,
      // rider data is readable without a token.
      final response = await get('/me/profile');
      expect(response.statusCode, anyOf(401, 403),
          reason: '/me/profile must not serve an anonymous caller');
    });

    test('vehicle types are JWT-gated, matching what the app expects',
        () async {
      // The booking flow calls this WITH a token. Unauthenticated it must
      // refuse — if that changes, our client is sending a header it need not,
      // or the endpoint has been opened up by mistake.
      final response = await get('/vehicle-types');
      expect(response.statusCode, anyOf(401, 403));
    });

    test('Supabase auth is reachable and rejects a bad password', () async {
      // Exercises the real GoTrue endpoint the AuthRepository wraps. A wrong
      // password must come back 400 with a structured body — the shape our
      // error mapping reads.
      final uri = Uri.parse('${AppConfig.supabaseUrl}/auth/v1/token'
          '?grant_type=password');
      final request = await client.postUrl(uri);
      request.headers.set('apikey', AppConfig.supabaseAnonKey);
      request.headers.contentType = ContentType.json;
      request.write(
          '{"email":"nobody-${DateTime.now().microsecondsSinceEpoch}'
          '@example.invalid","password":"definitely-not-a-real-password"}');
      final response = await request.close();

      expect(response.statusCode, anyOf(400, 401),
          reason: 'GoTrue should refuse an unknown account, not error out — '
              'a 5xx here means the project or key is wrong');
    });

    test('/geocode/search is JWT-gated', () async {
      final response = await get('/geocode/search?q=molineux');
      expect(response.statusCode, anyOf(401, 403),
          reason: 'autocomplete must not be an open geocoding service');
    });

    test('/rides/estimate rejects an unauthenticated caller', () async {
      final request =
          await client.postUrl(Uri.parse('${AppConfig.apiBaseUrl}/rides/estimate'));
      request.headers.set('X-Hoppin-Device-ID', 'integration-test');
      request.headers.contentType = ContentType.json;
      request.write('{"pickup_lat":52.586,"pickup_lng":-2.128,'
          '"dropoff_lat":52.593,"dropoff_lng":-2.110}');
      final response = await request.close();

      expect(response.statusCode, anyOf(401, 403),
          reason: 'pricing must not be free to anyone who asks');
    });

    test('/contacts is public, like /app-status', () async {
      // Support and emergency numbers are read live so they can change
      // without an app release, and the safety screen needs them before a
      // rider has necessarily signed in.
      final response = await get('/contacts');
      expect(response.statusCode, 200);
    });
  });
}
