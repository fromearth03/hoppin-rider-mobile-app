import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// The rider's own profile, mirroring what `GET /me/profile` returns and
/// nothing more.
class RiderProfile {
  final String fullName;

  /// Null when the rider has no number. The API already hides the
  /// `pending-<uid>` placeholder as `""`; we treat empty as absent so no
  /// screen renders a blank phone row.
  final String? phoneNumber;
  final String email;
  final String? avatarUrl;

  /// `YYYY-MM-DD`, or null when never set.
  ///
  /// Null is not a benign "not filled in yet" — the backend's booking guard
  /// treats a null DOB as ALLOWED, so a rider with no date of birth can book
  /// without ever passing the age check. That is why [needsDateOfBirth] exists
  /// and why the app must force collection rather than defer it.
  final String? dateOfBirth;

  /// Null until at least one driver has rated this rider. Never defaulted:
  /// a 5.0 for someone nobody has rated is a lie.
  final double? rating;
  final int ratingCount;

  const RiderProfile({
    required this.fullName,
    required this.phoneNumber,
    required this.email,
    required this.avatarUrl,
    required this.dateOfBirth,
    required this.rating,
    required this.ratingCount,
  });

  /// True exactly when [dateOfBirth] is null — meaning the app must collect
  /// a date of birth before this rider is usable, since the backend itself
  /// will not block booking on the missing value.
  bool get needsDateOfBirth => dateOfBirth == null;

  static String? _orNull(Object? v) {
    final s = v as String?;
    return (s == null || s.isEmpty) ? null : s;
  }

  factory RiderProfile.fromJson(Map<String, dynamic> json) => RiderProfile(
        fullName: (json['full_name'] as String?) ?? '',
        phoneNumber: _orNull(json['phone_number']),
        email: (json['email'] as String?) ?? '',
        avatarUrl: _orNull(json['avatar_url']),
        dateOfBirth: _orNull(json['date_of_birth']),
        rating: (json['rating'] as num?)?.toDouble(),
        ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      );
}

class ProfileRepository {
  final ApiClient _api;
  const ProfileRepository(this._api);

  Future<Result<RiderProfile>> get() async {
    final result = await _api.get<Map<String, dynamic>>('/me/profile');
    return switch (result) {
      Ok(:final value) => Ok(RiderProfile.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  /// `POST /me/avatar/upload` — multipart `file` in, the stored photo's URL
  /// out. The server persists it to `users.avatar_url`, so a follow-up
  /// profile fetch sees it everywhere avatars render.
  Future<Result<String>> uploadAvatar(Uint8List bytes,
      {String filename = 'avatar.jpg'}) async {
    final result = await _api.postFile<Map<String, dynamic>>(
      '/me/avatar/upload',
      bytes: bytes,
      filename: filename,
    );
    return switch (result) {
      Ok(:final value) => switch (value['avatar_url']) {
          String url when url.isNotEmpty => Ok(url),
          _ => const Err(
              ApiException('INTERNAL', 'upload returned no URL', 0)),
        },
      Err(:final error) => Err(error),
    };
  }

  /// Every field is optional; omitting one leaves it unchanged. An empty
  /// phone is ignored server-side and cannot clear the stored number.
  ///
  /// A `404 USER_NOT_FOUND` here means the auth user exists but its profile
  /// row does not — the failure mode migration 124 describes, where the
  /// signup trigger's exception handler swallowed the error into a warning.
  /// Callers must surface it, never retry blindly.
  Future<Result<RiderProfile>> patch({
    String? fullName,
    String? phoneNumber,
    String? dateOfBirth,
  }) async {
    final result =
        await _api.patch<Map<String, dynamic>>('/me/profile', body: {
      if (fullName != null) 'full_name': fullName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
    });
    return switch (result) {
      Ok(:final value) => Ok(RiderProfile.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
    (ref) => ProfileRepository(ref.watch(apiClientProvider)));
