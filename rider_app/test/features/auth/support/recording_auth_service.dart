import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A recording test double for [AuthService] used by the Lane-A screen tests.
///
/// It `implements` the service (same implicit-interface trick as
/// `DemoAuthService`) and records the auth calls the signup / OTP screens make,
/// so a widget test can assert "submitting called signUpRider" without any
/// Supabase round-trip.
class RecordingAuthService implements AuthService {
  RecordingAuthService({this.signUpThrows, this.verifyThrows});

  /// If set, [signUpRider] throws this — lets a test drive the error path.
  final Object? signUpThrows;

  /// If set, [verifyOtp] throws this.
  final Object? verifyThrows;

  final List<({String email, String password, String? fullName})> signUpCalls =
      [];
  final List<({String phone, String token})> verifyCalls = [];
  final List<String> otpStartCalls = [];
  int signOutCount = 0;

  @override
  Future<AuthResponse> signUpRider({
    required String email,
    required String password,
    String? fullName,
  }) async {
    signUpCalls.add((email: email, password: password, fullName: fullName));
    if (signUpThrows != null) throw signUpThrows!;
    return AuthResponse();
  }

  @override
  Future<void> signInWithOtp({required String phone}) async {
    otpStartCalls.add(phone);
  }

  @override
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) async {
    verifyCalls.add((phone: phone, token: token));
    if (verifyThrows != null) throw verifyThrows!;
    return AuthResponse();
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
  }

  // ── Unused by the Lane-A screens — satisfy the interface, never called. ──

  @override
  Session? get currentSession => null;

  @override
  String? get accessToken => null;

  @override
  bool get isSignedIn => false;

  @override
  String? get userId => null;

  @override
  String? get fullName => null;

  @override
  String? get email => null;

  /// Null is the HONEST default, and it is also the common one: only OTP-signup
  /// riders have a phone on the session at all. A consumer must omit the field,
  /// never dash it.
  @override
  String? get phone => null;

  @override
  DateTime? get createdAt => null;

  @override
  AppRole get role => AppRole.rider;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> refreshSession() async {}
}
