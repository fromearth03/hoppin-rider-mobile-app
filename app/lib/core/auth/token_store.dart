import 'dart:convert';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../device/device_id.dart';

/// Reads the current access token for the Authorization header.
///
/// Supabase owns the session — persistence, refresh, expiry — so nothing here
/// stores a token or manages its lifetime. Re-implementing that would mean two
/// sources of truth for whether the rider is signed in.
class TokenStore {
  final SupabaseClient _client;
  TokenStore(this._client);

  /// The refresh currently in flight, shared by every caller.
  ///
  /// A cold start fires several requests at once (profile, saved places, the
  /// reachability probe) and each would otherwise start its own refresh of the
  /// same session. The SDK serialises them internally, and one that never
  /// settles takes every waiter down with it.
  Future<String?>? _refreshing;

  /// The access token to send, refreshed first if it has already expired.
  ///
  /// The SDK refreshes in the background, but a cold start races it: the
  /// persisted session is restored with whatever access token it was last
  /// saved with, and after an hour away that token is already dead. Sending it
  /// anyway earns a 401, and the rider who never signed out is bounced to the
  /// login screen with a live refresh token sitting in storage. Awaiting the
  /// refresh here is what actually keeps them signed in.
  ///
  /// A refresh that fails or stalls falls back to the token we already have.
  /// Sending a stale token earns a fast 401, which the app handles; waiting on
  /// a refresh that never settles hangs the request BEFORE it is sent, where no
  /// Dio timeout can reach it — the screen then sits on its skeleton forever.
  /// A wrong answer quickly beats a right answer never.
  Future<String?> read() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    if (!session.isExpired) return session.accessToken;
    return await _refreshOnce() ?? session.accessToken;
  }

  /// One refresh at a time, bounded. Subsequent callers join the in-flight one
  /// instead of queueing another behind it.
  Future<String?> _refreshOnce() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _refresh() async {
    try {
      // One HTTP round trip to GoTrue. Anything slower than this is a stall,
      // not a slow network, and the rider is staring at a loading screen for
      // every second of it.
      final refreshed = await _client.auth
          .refreshSession()
          .timeout(const Duration(seconds: 5));
      return refreshed.session?.accessToken;
    } catch (_) {
      return null;
    }
  }

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
