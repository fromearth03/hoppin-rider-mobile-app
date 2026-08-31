import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// One message in a ride's chat thread.
///
/// Text only - `ride_messages` has a single content column. Attachments,
/// voice notes and presence are deferred to phase 2 because nothing backs
/// them.
class RideMessage {
  final String id;
  final String body;

  /// `rider` or `driver`.
  final String senderRole;
  final DateTime createdAt;

  /// `sent` or `read`, and ONLY on messages the rider sent. A tick on the
  /// driver's own message would claim they had read their own text.
  final String? status;

  /// Set when this message quotes another.
  final String? replyToId;

  /// The quoted body, for the preview above the bubble. Null when the parent
  /// was deleted - the bubble then shows no quote rather than an empty one.
  final String? replyToPreview;

  const RideMessage({
    required this.id,
    required this.body,
    required this.senderRole,
    required this.createdAt,
    required this.status,
    required this.replyToId,
    required this.replyToPreview,
  });

  bool get isMine => senderRole == 'rider';

  factory RideMessage.fromJson(Map<String, dynamic> json) {
    final parent = (json['reply_to'] as Map?)?.cast<String, dynamic>();
    return RideMessage(
      id: (json['id'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      senderRole: (json['sender_role'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      status: json['status'] as String?,
      replyToId: json['reply_to_id'] as String?,
      replyToPreview: parent?['body'] as String?,
    );
  }
}

class ChatRepository {
  final ApiClient _api;
  const ChatRepository(this._api);

  /// Messages for a ride, newest last.
  ///
  /// Pass [since] to fetch only what has arrived since the last poll. It is
  /// omitted on a first load - an empty `since` is rejected as a malformed
  /// timestamp rather than treated as "everything".
  ///
  /// Opening the thread clears `chat_unread` on `GET /rides/:id` server-side.
  Future<Result<List<RideMessage>>> messages(
    String rideId, {
    DateTime? since,
  }) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/rides/$rideId/messages',
      query: {
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(((value['messages'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(RideMessage.fromJson)
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  /// Sends a message, optionally quoting another.
  ///
  /// An empty body is refused here rather than sent: the server rejects it
  /// too, but a round trip to learn what the client already knows is waste,
  /// and the rider sees the refusal instantly.
  Future<Result<RideMessage>> send(
    String rideId,
    String body, {
    String? replyToId,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return Err(ApiException(
          'VALIDATION_FAILED', 'Type a message before sending.', 0));
    }

    final result = await _api.post<Map<String, dynamic>>(
      '/rides/$rideId/messages',
      body: {
        'body': trimmed,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    );

    return switch (result) {
      Ok(:final value) => Ok(RideMessage.fromJson(value)),
      Err(:final error) => Err(error),
    };
  }
}

final chatRepositoryProvider = Provider<ChatRepository>(
    (ref) => ChatRepository(ref.watch(apiClientProvider)));
