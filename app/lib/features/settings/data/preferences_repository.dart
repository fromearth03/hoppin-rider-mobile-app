import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';

/// A JSON value that is genuinely a bool, or null.
///
/// `users.preferences` is free-form JSONB and only PATCH validates against the
/// server's whitelist, so a row written by another client can hold anything.
/// Matching on the type rather than casting keeps a stray `"yes"` from turning
/// a hardening helper into the thing that throws.
bool? _boolOrNull(Object? v) => v is bool ? v : null;

/// The subset of `GET /me/preferences` this app actually renders.
///
/// Every field is nullable and that is the point: the handler documents that
/// keys the rider has never set are simply ABSENT, and "the app applies its own
/// defaults". Collapsing absent to `false` would tell a rider notifications are
/// off when the server never said so, and their first tap would then look like
/// it changed nothing.
///
/// The server's whitelist (`preferences_handler.go`) is role-agnostic and wider
/// than this — `push_promotions`, `push_payouts`, `email_receipts`,
/// `sms_trip_updates`, `marketing_consent`, `theme`, `language` — but only the
/// two keys the Setting screen draws a control for are modelled here. Adding a
/// field without a control would be a preference the rider cannot reach.
class RiderPreferences {
  /// `push_trip_updates` — the screen's "Notification" toggle.
  final bool? pushTripUpdates;

  /// `sound_offer_chime` — the screen's "Driver Arrived Sound" toggle. The
  /// only sound key on the server's whitelist, and role-agnostic by design.
  final bool? soundOfferChime;

  const RiderPreferences({
    required this.pushTripUpdates,
    required this.soundOfferChime,
  });

  static const empty =
      RiderPreferences(pushTripUpdates: null, soundOfferChime: null);

  factory RiderPreferences.fromJson(Map<String, dynamic> json) =>
      RiderPreferences(
        pushTripUpdates: _boolOrNull(json['push_trip_updates']),
        soundOfferChime: _boolOrNull(json['sound_offer_chime']),
      );
}

/// `GET`/`PATCH /me/preferences` — per-user app preferences stored as
/// `users.preferences` JSONB.
class PreferencesRepository {
  final ApiClient _api;
  const PreferencesRepository(this._api);

  /// Both endpoints answer with `{"preferences": {...}}`.
  static RiderPreferences _unwrap(Object? value) {
    final envelope = value is Map ? value['preferences'] : null;
    if (envelope is! Map) return RiderPreferences.empty;
    return RiderPreferences.fromJson(Map<String, dynamic>.from(envelope));
  }

  Future<Result<RiderPreferences>> read() async {
    final result = await _api.get<dynamic>('/me/preferences');
    return switch (result) {
      Ok(:final value) => Ok(_unwrap(value)),
      Err(:final error) => Err(error),
    };
  }

  /// Patches only the keys the caller named.
  ///
  /// The server merges with JSONB `||`, so an omitted key keeps whatever it
  /// held. Sending the whole object would write values the rider never touched
  /// and the server had deliberately left unset.
  ///
  /// The response is the FULL merged object, so the screen can settle on server
  /// truth rather than on its own optimistic guess.
  Future<Result<RiderPreferences>> update({
    bool? pushTripUpdates,
    bool? soundOfferChime,
  }) async {
    final body = <String, dynamic>{
      if (pushTripUpdates != null) 'push_trip_updates': pushTripUpdates,
      if (soundOfferChime != null) 'sound_offer_chime': soundOfferChime,
    };
    // An empty PATCH is a no-op the server would answer by echoing the current
    // object; not making the round trip at all is the same answer, faster.
    if (body.isEmpty) return const Ok(RiderPreferences.empty);

    final result = await _api.patch<dynamic>('/me/preferences', body: body);
    return switch (result) {
      Ok(:final value) => Ok(_unwrap(value)),
      Err(:final error) => Err(error),
    };
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
    (ref) => PreferencesRepository(ref.watch(apiClientProvider)));
