import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../device/device_id.dart';

/// Reads the current access token for the Authorization header.
///
/// Supabase owns the session — persistence, refresh, expiry — so nothing here
/// stores or refreshes a token. Re-implementing that would mean two sources of
/// truth for whether the rider is signed in.
class TokenStore {
  final SupabaseClient _client;
  const TokenStore(this._client);

  Future<String?> read() async => _client.auth.currentSession?.accessToken;

  bool get isSignedIn => _client.auth.currentSession != null;

  /// The GoTrue `session_id` claim, which the backend's SingleSessionGate
  /// compares against `users.active_session_id`.
  ///
  /// Not the user id — one user has many sessions over time and only the newest
  /// is live. Older GoTrue tokens may omit the claim; the gate fails open in
  /// that case, so null is a valid answer rather than an error.
  String? get sessionId {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) return null;
    return _claim(token, 'session_id');
  }

  /// Reads one claim from a JWT payload without verifying the signature —
  /// verification is the backend's job, and this is only ever used for values
  /// the client hands straight back to it.
  static String? _claim(String jwt, String name) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = parts[1];
      final normalised = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalised));
      final map = jsonDecode(decoded);
      if (map is! Map) return null;
      final value = map[name];
      return value is String && value.isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
  }
}

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final tokenStoreProvider =
    Provider<TokenStore>((ref) => TokenStore(ref.watch(supabaseClientProvider)));

/// Re-exported so the API client can attach the device header without reaching
/// across feature folders.
final deviceIdForRequests = deviceIdProvider;
