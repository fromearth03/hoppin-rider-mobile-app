import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/config.dart';

/// Guards the wiring between `--dart-define-from-file` and the app.
///
/// Run with the config to prove it arrives:
///   flutter test --dart-define-from-file=../config/dev.json
///
/// Without it the values are empty, which is also correct — so these tests
/// assert the *shape* of what arrives rather than that it is present, and skip
/// the value checks when nothing was supplied.
void main() {
  group('AppConfig', () {
    test('reports a usable reason when nothing is supplied', () {
      if (AppConfig.hasSupabase) return; // configured run — nothing to assert
      expect(AppConfig.missingReason, isNotNull);
      expect(AppConfig.missingReason, contains('--dart-define-from-file'));
    });

    test('api base url always has a value', () {
      // Defaulted, so it is never empty even with no config at all.
      expect(AppConfig.apiBaseUrl, isNotEmpty);
      expect(AppConfig.apiBaseUrl, startsWith('https://'));
    });

    test('supabase url is a real https project url when supplied', () {
      if (!AppConfig.hasSupabase) return;
      expect(AppConfig.supabaseUrl, startsWith('https://'));
      expect(AppConfig.supabaseUrl, contains('.supabase.co'));
      expect(AppConfig.missingReason, isNull);
    });

    test('anon key is a JWT carrying the anon role, never service_role', () {
      if (!AppConfig.hasSupabase) return;
      final parts = AppConfig.supabaseAnonKey.split('.');
      expect(parts, hasLength(3), reason: 'anon key should be a JWT');

      // Decode the payload rather than string-matching it. A service_role key
      // here would ship full database access — bypassing every row-level
      // security policy — inside a binary that anyone can unzip. This assertion
      // is the entire point of the test.
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;

      expect(payload['role'], 'anon',
          reason: 'a non-anon key must never ship in the app');
      expect(payload['ref'], isNotEmpty);
      expect(AppConfig.supabaseUrl, contains(payload['ref'] as String),
          reason: 'key and url should belong to the same project');
    });
  });
}
