import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// What a phone needs to enter a call: the call server's address and a
/// short-lived ticket for this call's room.
///
/// The address comes from the backend with every ticket instead of being built
/// into the app, so moving the call server never needs a new release.
class CallTicket {
  final String callId;
  final String rideId;
  final String url;
  final String token;
  final String room;

  /// The other person — first name only. They are a stranger; a surname adds
  /// nothing but exposure.
  final String peerName;

  /// `rider` or `driver`.
  final String peerRole;

  /// When an outgoing call stops ringing and counts as missed. Null on a
  /// ticket for a call you answered.
  final DateTime? ringsUntil;

  const CallTicket({
    required this.callId,
    required this.rideId,
    required this.url,
    required this.token,
    required this.room,
    required this.peerName,
    required this.peerRole,
    this.ringsUntil,
  });

  factory CallTicket.fromJson(Map<String, dynamic> j) => CallTicket(
    callId: j['call_id'] as String? ?? '',
    rideId: j['ride_id'] as String? ?? '',
    url: j['url'] as String? ?? '',
    token: j['token'] as String? ?? '',
    room: j['room'] as String? ?? '',
    peerName: j['peer_name'] as String? ?? '',
    peerRole: j['peer_role'] as String? ?? '',
    ringsUntil: DateTime.tryParse(j['rings_until'] as String? ?? '')?.toLocal(),
  );
}

/// A call as one of its two parties sees it.
class CallStatus {
  final String id;

  /// ringing · answered · declined · missed · cancelled · ended · failed
  final String status;

  /// `outgoing` if you placed it, `incoming` if you received it.
  final String direction;
  final int? durationSeconds;

  const CallStatus({
    required this.id,
    required this.status,
    required this.direction,
    this.durationSeconds,
  });

  bool get isLive => status == 'ringing' || status == 'answered';

  factory CallStatus.fromJson(Map<String, dynamic> j) => CallStatus(
    id: j['id'] as String? ?? '',
    status: j['status'] as String? ?? '',
    direction: j['direction'] as String? ?? '',
    durationSeconds: (j['duration_seconds'] as num?)?.toInt(),
  );
}

/// In-app voice calls between this rider and their driver. No phone numbers:
/// the call runs through Hoppin's own call server, and neither side ever learns
/// the other's number.
class CallsRepository {
  final ApiClient _api;
  const CallsRepository(this._api);

  /// Rings the driver. 409 `CALL_IN_PROGRESS` carries the live call's id in
  /// [ApiException.fields] — see [liveCallIdOf].
  Future<Result<CallTicket>> start(String rideId) async =>
      _ticket(await _api.post<dynamic>('/rides/$rideId/call'));

  /// Answers a call that is ringing on this phone.
  Future<Result<CallTicket>> accept(String callId) async =>
      _ticket(await _api.post<dynamic>('/calls/$callId/accept'));

  /// Turns down a ringing call; the caller is told straight away.
  Future<Result<void>> decline(String callId) async {
    final res = await _api.post<dynamic>('/calls/$callId/decline');
    return switch (res) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// Hangs up, whatever state the call is in. Safe to call twice.
  Future<Result<CallStatus>> end(String callId) async =>
      _status(await _api.post<dynamic>('/calls/$callId/end'));

  /// The polling fallback for a phone that missed a push.
  Future<Result<CallStatus>> status(String callId) async =>
      _status(await _api.get<dynamic>('/calls/$callId'));

  /// The call already ringing or connected on this ride, when [start] was
  /// refused because of it.
  static String? liveCallIdOf(ApiException e) =>
      e.code == 'CALL_IN_PROGRESS' ? e.fields['call_id'] as String? : null;

  Result<CallTicket> _ticket(Result<dynamic> res) => switch (res) {
    Ok(:final value) => Ok(CallTicket.fromJson(_map(value))),
    Err(:final error) => Err(error),
  };

  Result<CallStatus> _status(Result<dynamic> res) => switch (res) {
    Ok(:final value) => Ok(CallStatus.fromJson(_map(value))),
    Err(:final error) => Err(error),
  };
}

final callsRepositoryProvider = Provider<CallsRepository>(
  (ref) => CallsRepository(ref.watch(apiClientProvider)),
);
