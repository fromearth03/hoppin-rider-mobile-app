import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/auth/data/auth_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

void main() {
  late _MockClient client;
  late _MockAuth auth;
  late AuthRepository repo;

  setUp(() {
    client = _MockClient();
    auth = _MockAuth();
    when(() => client.auth).thenReturn(auth);
    repo = AuthRepository(client);
  });

  group('signIn', () {
    test('returns the session on success', () async {
      final session = Session(
        accessToken: 'token',
        tokenType: 'bearer',
        user: User(
          id: 'uid',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      when(() => auth.signInWithPassword(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(session: session));

      final result = await repo.signIn('a@b.com', 'pw');

      expect(result, isA<Ok<Session>>());
      expect((result as Ok<Session>).value.accessToken, 'token');
    });

    test('maps a bad password to INVALID_CREDENTIALS', () async {
      when(() => auth.signInWithPassword(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(const AuthException('Invalid login credentials',
              statusCode: '400'));

      final result = await repo.signIn('a@b.com', 'wrong');

      expect((result as Err).error.code, 'INVALID_CREDENTIALS');
    });

    test('maps rate limiting to TOO_MANY_ATTEMPTS', () async {
      when(() => auth.signInWithPassword(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(
              const AuthException('Email rate limit exceeded', statusCode: '429'));

      final result = await repo.signIn('a@b.com', 'pw');
      final err = result as Err;

      expect(err.error.code, 'TOO_MANY_ATTEMPTS');
      expect(err.error.isRetryable, isFalse,
          reason: 'retrying a rate limit extends the lockout');
    });

    test('trims the email so a trailing space cannot fail a login', () async {
      when(() => auth.signInWithPassword(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(session: null));

      await repo.signIn('  a@b.com  ', 'pw');

      verify(() => auth.signInWithPassword(email: 'a@b.com', password: 'pw'))
          .called(1);
    });

    test('a null session is a failure, not a success', () async {
      when(() => auth.signInWithPassword(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => AuthResponse(session: null));

      final result = await repo.signIn('a@b.com', 'pw');

      expect(result, isA<Err<Session>>());
      expect((result as Err).error.code, 'AUTH_FAILED');
    });
  });

  group('signUp', () {
    test('passes full_name as user metadata for the profile trigger',
        () async {
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => AuthResponse(session: null));

      await repo.signUp(
          email: 'a@b.com', password: 'pw', fullName: 'Ada Lovelace');

      final captured = verify(() => auth.signUp(
            email: 'a@b.com',
            password: 'pw',
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;

      expect(captured['full_name'], 'Ada Lovelace');
    });

    test('includes phone in metadata only when given', () async {
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => AuthResponse(session: null));

      await repo.signUp(email: 'a@b.com', password: 'pw', fullName: 'Ada');

      final captured = verify(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: captureAny(named: 'data'),
          )).captured.single as Map<String, dynamic>;

      expect(captured.containsKey('phone_number'), isFalse,
          reason: 'a blank phone must not overwrite the pending- placeholder');
    });

    test('maps an existing account to EMAIL_TAKEN', () async {
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          )).thenThrow(const AuthException('User already registered',
              statusCode: '422'));

      final result =
          await repo.signUp(email: 'a@b.com', password: 'pw', fullName: 'Ada');

      expect((result as Err).error.code, 'EMAIL_TAKEN');
    });
  });

  group('structured error code takes precedence over message text', () {
    test('otp_expired code maps to EXPIRED_LINK', () async {
      when(() => auth.signInWithPassword(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(const AuthException('Token has expired or is invalid',
              statusCode: '403', code: 'otp_expired'));

      final result = await repo.signIn('a@b.com', 'pw');
      final err = result as Err;

      expect(err.error.code, 'EXPIRED_LINK');
    });

    test('email_exists code maps to EMAIL_TAKEN alongside the message-based '
        'mapping', () async {
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          )).thenThrow(const AuthException('A user with this email address '
              'has already been registered',
              statusCode: '422', code: 'email_exists'));

      final result =
          await repo.signUp(email: 'a@b.com', password: 'pw', fullName: 'Ada');
      final err = result as Err;

      expect(err.error.code, 'EMAIL_TAKEN');
    });

    test('weak_password code maps to WEAK_PASSWORD', () async {
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          )).thenThrow(const AuthException('Password should be at least 6 '
              'characters',
              statusCode: '422', code: 'weak_password'));

      final result = await repo.signUp(
          email: 'a@b.com', password: 'pw', fullName: 'Ada');
      final err = result as Err;

      expect(err.error.code, 'WEAK_PASSWORD');
    });

    test('a null code falls back to the message heuristics', () async {
      when(() => auth.signInWithPassword(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(
              const AuthException('Invalid login credentials', statusCode: '400'));

      final result = await repo.signIn('a@b.com', 'wrong');
      final err = result as Err;

      expect(err.error.code, 'INVALID_CREDENTIALS');
    });
  });

  group('signOut', () {
    test('reports success even when the network call fails', () async {
      when(() => auth.signOut()).thenThrow(Exception('offline'));

      final result = await repo.signOut();

      expect(result, isA<Ok<void>>(),
          reason: 'the SDK clears local state first, so the rider is signed '
              'out locally either way — which is what they asked for');
    });
  });
}
