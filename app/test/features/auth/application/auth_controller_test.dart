import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/data/auth_repository.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockAuthRepo extends Mock implements AuthRepository {}

class _MockProfileRepo extends Mock implements ProfileRepository {}

Session _session() => Session(
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

RiderProfile _profile({String? dob}) => RiderProfile(
      fullName: 'Ada',
      phoneNumber: null,
      email: 'a@b.com',
      avatarUrl: null,
      dateOfBirth: dob,
      rating: null,
      ratingCount: 0,
    );

void main() {
  late _MockAuthRepo auth;
  late _MockProfileRepo profiles;
  late AuthController controller;

  setUp(() {
    auth = _MockAuthRepo();
    profiles = _MockProfileRepo();
    controller = AuthController(auth, profiles);
  });

  group('signUp', () {
    test('writes the date of birth after creating the account', () async {
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => Ok(_session()));
      when(() => profiles.patch(dateOfBirth: any(named: 'dateOfBirth')))
          .thenAnswer((_) async => Ok(_profile(dob: '1990-12-10')));

      await controller.signUp(
        email: 'a@b.com',
        password: 'pw',
        fullName: 'Ada',
        dateOfBirth: DateTime(1990, 12, 10),
      );

      verify(() => profiles.patch(dateOfBirth: '1990-12-10')).called(1);
      expect(controller.state.status, AuthStatus.signedIn);
    });

    test('lands in profileIncomplete when the DOB write fails', () async {
      // The account now exists. Signing the rider out would strand them with
      // an account they cannot recreate; the app must let them retry instead.
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => Ok(_session()));
      when(() => profiles.patch(dateOfBirth: any(named: 'dateOfBirth')))
          .thenAnswer((_) async =>
              Err(ApiException('INTERNAL', 'network error', 0)));

      await controller.signUp(
        email: 'a@b.com',
        password: 'pw',
        fullName: 'Ada',
        dateOfBirth: DateTime(1990, 12, 10),
      );

      expect(controller.state.status, AuthStatus.profileIncomplete);
      expect(controller.state.error?.code, 'INTERNAL');
    });

    test('surfaces a missing profile row rather than continuing', () async {
      // Migration 124's failure mode: auth user created, trigger swallowed
      // its own error, no public.users row. Every later call would 404.
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => Ok(_session()));
      when(() => profiles.patch(dateOfBirth: any(named: 'dateOfBirth')))
          .thenAnswer((_) async => Err(
              ApiException('USER_NOT_FOUND', 'profile not found', 404)));

      await controller.signUp(
        email: 'a@b.com',
        password: 'pw',
        fullName: 'Ada',
        dateOfBirth: DateTime(1990, 12, 10),
      );

      expect(controller.state.status, AuthStatus.profileIncomplete);
      expect(controller.state.error?.code, 'USER_NOT_FOUND');
    });

    test('a transient profile failure does not read as a broken account',
        () async {
      // This stranded a rider with a perfectly good account on the sign-up
      // screen: every profile read failure — a network drop, a 5xx, CORS on
      // the web build — was treated as "your account is half-made", and
      // profileIncomplete forces the router to /signup. Only a profile that
      // genuinely is not there means that.
      when(() => auth.signIn(any(), any()))
          .thenAnswer((_) async => Ok(_session()));
      when(() => profiles.get()).thenAnswer(
          (_) async => Err(ApiException('NETWORK', 'Connection failed', 0)));

      await controller.signIn('a@b.com', 'pw');

      expect(controller.state.status, isNot(AuthStatus.profileIncomplete),
          reason: 'a network blip must not send the rider to sign up');
      expect(controller.state.error?.code, 'NETWORK');
    });

    test('a genuinely missing profile still reads as incomplete', () async {
      when(() => auth.signIn(any(), any()))
          .thenAnswer((_) async => Ok(_session()));
      when(() => profiles.get()).thenAnswer((_) async =>
          Err(ApiException('USER_NOT_FOUND', 'profile not found', 404)));

      await controller.signIn('a@b.com', 'pw');

      expect(controller.state.status, AuthStatus.profileIncomplete);
    });

    test('does not attempt the DOB write when signup itself failed', () async {
      when(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async =>
              Err(ApiException('EMAIL_TAKEN', 'User already registered', 422)));

      await controller.signUp(
        email: 'a@b.com',
        password: 'pw',
        fullName: 'Ada',
        dateOfBirth: DateTime(1990, 12, 10),
      );

      verifyNever(() => profiles.patch(dateOfBirth: any(named: 'dateOfBirth')));
      expect(controller.state.status, AuthStatus.signedOut);
      expect(controller.state.error?.code, 'EMAIL_TAKEN');
    });

    test('refuses an under-13 date without calling the network', () async {
      await controller.signUp(
        email: 'a@b.com',
        password: 'pw',
        fullName: 'Ada',
        dateOfBirth: DateTime(2020, 1, 1),
      );

      verifyNever(() => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
            phone: any(named: 'phone'),
          ));
      expect(controller.state.error?.code, 'VALIDATION_FAILED');
    });
  });

  group('signIn', () {
    test('flags an incomplete profile so the app can recover it', () async {
      when(() => auth.signIn(any(), any()))
          .thenAnswer((_) async => Ok(_session()));
      when(() => profiles.get())
          .thenAnswer((_) async => Ok(_profile(dob: null)));

      await controller.signIn('a@b.com', 'pw');

      expect(controller.state.status, AuthStatus.profileIncomplete,
          reason: 'a null DOB means the age gate is unenforced for this rider');
    });

    test('signs in cleanly when the profile is complete', () async {
      when(() => auth.signIn(any(), any()))
          .thenAnswer((_) async => Ok(_session()));
      when(() => profiles.get())
          .thenAnswer((_) async => Ok(_profile(dob: '1990-12-10')));

      await controller.signIn('a@b.com', 'pw');

      expect(controller.state.status, AuthStatus.signedIn);
      expect(controller.state.profile?.dateOfBirth, '1990-12-10');
    });

    test('stays signed out and reports the error on bad credentials',
        () async {
      when(() => auth.signIn(any(), any())).thenAnswer((_) async =>
          Err(ApiException('INVALID_CREDENTIALS', 'Invalid login', 400)));

      await controller.signIn('a@b.com', 'wrong');

      expect(controller.state.status, AuthStatus.signedOut);
      expect(controller.state.error?.code, 'INVALID_CREDENTIALS');
      verifyNever(() => profiles.get());
    });
  });

  group('completeProfile', () {
    test('retries the DOB write and reaches signedIn', () async {
      when(() => profiles.patch(dateOfBirth: any(named: 'dateOfBirth')))
          .thenAnswer((_) async => Ok(_profile(dob: '1990-12-10')));

      await controller.completeProfile(DateTime(1990, 12, 10));

      expect(controller.state.status, AuthStatus.signedIn);
      expect(controller.state.error, isNull);
    });
  });
}
