import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// Empty-or-absent to null.
///
/// Matches on the type rather than casting: `as String?` throws on a non-string
/// JSON value, which would make a hardening helper the thing that crashes.
String? _orNull(Object? v) => switch (v) {
      String s when s.trim().isNotEmpty => s,
      _ => null,
    };

/// Rows the server sent that are not JSON objects at all.
///
/// `List.cast<Map<String, dynamic>>()` is LAZY in Dart: it validates nothing at
/// the call and throws a TypeError later, when `map` pulls an element. That
/// throw escapes a method whose signature promises a `Result`, and `ApiClient`
/// catches only `DioException` - so a single `null` in an array would propagate
/// out of code the caller believes cannot throw.
Iterable<Map<String, dynamic>> _objects(Object? raw) =>
    (raw is List ? raw : const []).whereType<Map<String, dynamic>>();

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

  /// Null for a contact that cannot actually be rung.
  ///
  /// `addContact` refuses a blank name or number on the way in, but nothing
  /// refused one on the way OUT - so a row the server returned with an empty
  /// phone rendered as a tappable contact whose call button does nothing. In
  /// an emergency that is worse than the contact being absent, because it
  /// looks usable. The id is equally required: without it the contact cannot
  /// be deleted.
  static EmergencyContact? tryFromJson(Map<String, dynamic> json) {
    final id = _orNull(json['id']);
    final name = _orNull(json['name']);
    final phone = _orNull(json['phone']);
    if (id == null || name == null || phone == null) return null;

    return EmergencyContact(
      id: id,
      name: name,
      phone: phone,
      relationship: _orNull(json['relationship']),
    );
  }

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json)!;
}

/// A raised panic alert.
///
/// Typed rather than a bare map, like every other response on this repository.
/// This is the one call whose result a rider's safety may depend on, so it is
/// the last one that should hand back an untyped blob for a screen to guess at.
class SosAlert {
  /// Null when the server did not return one. The alert was still raised - the
  /// `Ok` is what says so - we simply cannot cite a reference number.
  final String? id;

  const SosAlert(this.id);

  factory SosAlert.fromJson(Map<String, dynamic> json) =>
      SosAlert(_orNull(json['id']));
}

/// A live-tracking link the rider can share. The token alone authorizes it.
class ShareLink {
  final String token;
  final String url;

  const ShareLink({required this.token, required this.url});

  /// Null when there is no url to share. A blank link handed to the share
  /// sheet lets the rider believe someone can follow their trip when nobody
  /// can - the failure mode this feature exists to prevent.
  static ShareLink? tryFromJson(Map<String, dynamic> json) {
    final url = _orNull(json['url']);
    if (url == null) return null;
    return ShareLink(token: _orNull(json['token']) ?? '', url: url);
  }

  factory ShareLink.fromJson(Map<String, dynamic> json) => tryFromJson(json)!;
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
  ///
  /// A position is sent only when BOTH halves are known, and the spread makes
  /// that coupling explicit: two independent `if`s read as though a caller
  /// could supply a latitude alone, when in fact that silently drops both.
  Future<Result<SosAlert>> raiseSos({
    String? rideId,
    double? lat,
    double? lng,
  }) async {
    final result = await _api.post<Map<String, dynamic>>('/me/sos', body: {
      if (rideId != null) 'ride_id': rideId,
      if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
    });

    return switch (result) {
      Ok(:final value) => Ok(SosAlert.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<List<EmergencyContact>>> listContacts() async {
    final result =
        await _api.get<Map<String, dynamic>>('/me/emergency-contacts');
    return switch (result) {
      Ok(:final value) => Ok(_objects(value['contacts'])
          .map(EmergencyContact.tryFromJson)
          .whereType<EmergencyContact>()
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
      return const Err(ApiException('VALIDATION_FAILED',
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
      // A success that returns an unusable contact is a failure. Handing back
      // a row whose call button does nothing is worse than saying so.
      Ok(:final value) => switch (EmergencyContact.tryFromJson(value)) {
          final EmergencyContact c => Ok(c),
          null => const Err(ApiException('INTERNAL',
              'That contact could not be saved. Try again.', 0)),
        },
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
      // A link with no url would give the share sheet a blank to send, so the
      // rider believes someone can follow their trip when nobody can.
      Ok(:final value) => switch (ShareLink.tryFromJson(value)) {
          final ShareLink l => Ok(l),
          null => const Err(ApiException('INTERNAL',
              'Could not create a tracking link. Try again.', 0)),
        },
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
