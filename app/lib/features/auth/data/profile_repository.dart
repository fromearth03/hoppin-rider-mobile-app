import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
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

  /// `YYYY-MM-DD`, or null when never set. A null DOB is treated by the
  /// booking guard as ALLOWED, so null here means the age gate is unenforced
  /// for this rider — see [needsDateOfBirth].
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
