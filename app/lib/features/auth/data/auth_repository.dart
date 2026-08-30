import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/result.dart';

/// Wraps `supabase_flutter`'s auth client so the rest of the app sees the same
/// `Result` + `{code}` contract it uses for the ride service.
///
/// The SDK owns refresh and persistence — nothing here re-implements them.
class AuthRepository {
  final SupabaseClient _client;
  AuthRepository(this._client);

  GoTrueClient get _auth => _client.auth;

  Session? get currentSession => _auth.currentSession;
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  Future<Result<Session>> signIn(String email, String password) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final session = response.session;
      if (session == null) {
        return Err(ApiException('AUTH_FAILED', 'No session returned', 0));
      }
      return Ok(session);
    } on AuthException catch (e) {
      return Err(_map(e));
    } catch (e) {
      return Err(ApiException('INTERNAL', e.toString(), 0));
    }
  }

  /// Creates the auth user. A database trigger mirrors it into `public.users`
  /// and `rider_profiles`, reading `full_name` from this metadata.
  ///
  /// Phone is omitted when blank rather than sent empty: the trigger writes a
  /// `pending-<uid>` placeholder for a rider with no number, and an empty
  /// string would overwrite it with something the API cannot hide.
  ///
  /// `signUp` asserts email XOR phone, so the number cannot be passed as the
  /// `phone:` argument here — it travels as metadata.
  Future<Result<Session>> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    final trimmedPhone = phone?.trim() ?? '';
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          if (trimmedPhone.isNotEmpty) 'phone_number': trimmedPhone,
        },
      );
      final session = response.session;
      if (session == null) {
        return Err(ApiException(
            'AUTH_FAILED', 'Account created but no session returned', 0));
      }
      return Ok(session);
    } on AuthException catch (e) {
      return Err(_map(e));
    } catch (e) {
      return Err(ApiException('INTERNAL', e.toString(), 0));
    }
  }

  Future<Result<void>> requestPasswordReset(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
      return const Ok(null);
    } on AuthException catch (e) {
      return Err(_map(e));
    } catch (e) {
      return Err(ApiException('INTERNAL', e.toString(), 0));
    }
  }

  /// Always reports success: the SDK clears local state before the network
  /// call, so a server error still leaves the rider signed out locally, which
  /// is the outcome they asked for.
  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Intentionally swallowed — see above.
    }
    return const Ok(null);
  }

  ApiException _map(AuthException e) {
    final status = int.tryParse(e.statusCode ?? '') ?? 0;
    final message = e.message.toLowerCase();

    if (status == 429 || message.contains('rate limit')) {
      return ApiException('TOO_MANY_ATTEMPTS', e.message, status);
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return ApiException('EMAIL_TAKEN', e.message, status);
    }
    if (message.contains('expired') || message.contains('invalid token')) {
      return ApiException('EXPIRED_LINK', e.message, status);
    }
    if (status == 400 || message.contains('invalid login')) {
      return ApiException('INVALID_CREDENTIALS', e.message, status);
    }
    if (status >= 500) return ApiException('INTERNAL', e.message, status);
    return ApiException('AUTH_FAILED', e.message, status);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => AuthRepository(ref.watch(supabaseClientProvider)));
