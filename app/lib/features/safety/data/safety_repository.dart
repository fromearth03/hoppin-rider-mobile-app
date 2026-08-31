import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

String? _orNull(Object? v) {
  final s = v as String?;
  return (s == null || s.trim().isEmpty) ? null : s;
}

class EmergencyContact {
  final String id;
  final String name;
  final String phone;

  /// Null when unset, so the row renders no relationship line at all.
  final String? relationship;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        relationship: _orNull(json['relationship']),
      );
}

/// A live-tracking link the rider can share. The token alone authorizes it.
class ShareLink {
  final String token;
  final String url;

  const ShareLink({required this.token, required this.url});

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
        token: (json['token'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
      );
}

/// Support and emergency numbers, read live so ops can change them without
/// an app release.
class PlatformContacts {
  final String? supportEmail;
  final String? supportPhone;
  final String? emergencyPhone;
  final String? whatsappNumber;

  const PlatformContacts({
    required this.supportEmail,
    required this.supportPhone,
    required this.emergencyPhone,
    required this.whatsappNumber,
  });

  factory PlatformContacts.fromJson(Map<String, dynamic> json) =>
      PlatformContacts(
        supportEmail: _orNull(json['support_email']),
        supportPhone: _orNull(json['support_phone']),
        emergencyPhone: _orNull(json['emergency_phone']),
        whatsappNumber: _orNull(json['whatsapp_number']),
      );
}

class SafetyRepository {
  final ApiClient _api;
  const SafetyRepository(this._api);

  /// Raises a panic alert, which surfaces on the admin safety dashboard.
  ///
  /// Every field is optional. A rider in danger with no GPS fix must still be
  /// able to call for help - sending 0,0 rather than omitting the position
  /// would place them in the Atlantic on the dashboard, which is worse than
  /// no position at all.
  Future<Result<Map<String, dynamic>>> raiseSos({
    String? rideId,
    double? lat,
    double? lng,
  }) =>
      _api.post<Map<String, dynamic>>('/me/sos', body: {
        if (rideId != null) 'ride_id': rideId,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      });

  Future<Result<List<EmergencyContact>>> listContacts() async {
    final result =
        await _api.get<Map<String, dynamic>>('/me/emergency-contacts');
    return switch (result) {
      Ok(:final value) => Ok(((value['contacts'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(EmergencyContact.fromJson)
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// A contact with no name or no number cannot be called in an emergency,
  /// so it is refused here rather than stored as a row that looks usable.
  Future<Result<EmergencyContact>> addContact({
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
      return Err(ApiException('VALIDATION_FAILED',
          'A contact needs both a name and a phone number.', 0));
    }

    final result = await _api
        .post<Map<String, dynamic>>('/me/emergency-contacts', body: {
      'name': trimmedName,
      'phone': trimmedPhone,
      if (relationship != null && relationship.trim().isNotEmpty)
        'relationship': relationship.trim(),
    });

    return switch (result) {
      Ok(:final value) => Ok(EmergencyContact.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> deleteContact(String id) async {
    final result =
        await _api.delete<dynamic>('/me/emergency-contacts/$id');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<ShareLink>> createShareLink(String rideId) async {
    final result =
        await _api.post<Map<String, dynamic>>('/rides/$rideId/share-link');
    return switch (result) {
      Ok(:final value) => Ok(ShareLink.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> revokeShareLink(String rideId) async {
    final result = await _api.delete<dynamic>('/rides/$rideId/share-link');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// Public endpoint - the safety screen needs these numbers whether or not
  /// the rider is signed in.
  Future<Result<PlatformContacts>> platformContacts() async {
    final result = await _api.get<Map<String, dynamic>>('/contacts');
    return switch (result) {
      Ok(:final value) => Ok(PlatformContacts.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final safetyRepositoryProvider = Provider<SafetyRepository>(
    (ref) => SafetyRepository(ref.watch(apiClientProvider)));
