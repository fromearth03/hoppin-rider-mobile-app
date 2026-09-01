import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/result.dart';

/// One of the rider's support tickets, as `GET /me/support-tickets` returns
/// it (`models.SupportTicket`: id, subject, category, priority, status,
/// body, created_at).
class SupportTicket {
  final String id;
  final String subject;
  final String? category;
  final String status;
  final String? body;
  final DateTime? createdAt;

  /// The ride this complaint is about, when one was attached.
  final String? rideId;

  /// Staff-written outcome, shown once support resolves the ticket.
  final String? resolutionNotes;

  const SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.body,
    required this.createdAt,
    this.rideId,
    this.resolutionNotes,
  });

  static SupportTicket? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return SupportTicket(
      id: id,
      subject: (json['subject'] as String?) ?? '',
      category: switch (json['category']) {
        String s when s.isNotEmpty => s,
        _ => null,
      },
      status: (json['status'] as String?) ?? 'open',
      body: switch (json['body']) {
        String s when s.isNotEmpty => s,
        _ => null,
      },
      createdAt: switch (json['created_at']) {
        String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      },
      rideId: switch (json['ride_id']) {
        String s when s.isNotEmpty => s,
        _ => null,
      },
      resolutionNotes: switch (json['resolution_notes']) {
        String s when s.trim().isNotEmpty => s,
        _ => null,
      },
    );
  }
}

/// One message on a ticket thread — rider or staff.
class TicketMessage {
  final String id;
  final bool isStaff;
  final String body;
  final DateTime? createdAt;

  /// On the rider's OWN messages: 'sent' until staff read it, then 'read'.
  final String? status;

  const TicketMessage({
    required this.id,
    required this.isStaff,
    required this.body,
    required this.createdAt,
    this.status,
  });

  static TicketMessage? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return TicketMessage(
      id: id,
      isStaff: json['is_staff'] == true,
      body: (json['body'] as String?) ?? '',
      createdAt: switch (json['created_at']) {
        String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      },
      status: switch (json['status']) {
        String s when s.isNotEmpty => s,
        _ => null,
      },
    );
  }
}

/// An importance tag from `GET /complaint-tags`; chosen names ride along on
/// ticket creation.
class ComplaintTag {
  final String name;
  final String label;

  const ComplaintTag({required this.name, required this.label});

  static ComplaintTag? tryFromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final label = switch (json['label']) {
      String s when s.trim().isNotEmpty => s,
      _ => name,
    };
    return ComplaintTag(name: name, label: label);
  }
}

/// A ticket with its full message thread — `GET /me/support-tickets/:id`.
class TicketDetail {
  final SupportTicket ticket;
  final List<TicketMessage> messages;
  const TicketDetail({required this.ticket, required this.messages});
}

/// A typed complaint reason from `GET /complaint-types`; the chosen `code`
/// goes back as `type_code` on ticket creation.
class ComplaintType {
  final String code;
  final String label;

  const ComplaintType({required this.code, required this.label});

  static ComplaintType? tryFromJson(Map<String, dynamic> json) {
    final code = json['code'];
    if (code is! String || code.isEmpty) return null;
    final label = switch (
        json['label'] ?? json['name'] ?? json['description']) {
      String s when s.trim().isNotEmpty => s,
      _ => code,
    };
    return ComplaintType(code: code, label: label);
  }
}

/// `POST/GET /me/support-tickets` + `GET /complaint-types` — the rider
/// ticket surface (`selfservice_handler.go`). `subject` is the one required
/// field; everything else is optional on the wire.
class SupportTicketsRepository {
  final ApiClient _api;
  const SupportTicketsRepository(this._api);

  Future<Result<List<ComplaintType>>> complaintTypes() async {
    final result = await _api.get<Map<String, dynamic>>('/complaint-types');
    return switch (result) {
      Ok(:final value) => Ok(((value['complaint_types'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) =>
              ComplaintType.tryFromJson(Map<String, dynamic>.from(row)))
          .whereType<ComplaintType>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<List<ComplaintTag>>> complaintTags() async {
    final result = await _api.get<Map<String, dynamic>>('/complaint-tags');
    return switch (result) {
      Ok(:final value) => Ok(((value['complaint_tags'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) =>
              ComplaintTag.tryFromJson(Map<String, dynamic>.from(row)))
          .whereType<ComplaintTag>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> open({
    required String subject,
    String? typeCode,
    String? body,
    String? rideId,
    List<String> tags = const [],
    // 'complaint' | 'support' — one table server-side, but the app keeps
    // the two flows (and their lists) apart by this field.
    String? category,
  }) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/me/support-tickets',
      body: {
        'subject': subject,
        if (category != null && category.isNotEmpty) 'category': category,
        if (typeCode != null && typeCode.isNotEmpty) 'type_code': typeCode,
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
        // A complaint about a specific trip carries the trip.
        if (rideId != null && rideId.isNotEmpty) 'ride_id': rideId,
        if (tags.isNotEmpty) 'tags': tags,
      },
    );
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// One ticket + its whole thread. Opening it also marks the thread read
  /// server-side.
  Future<Result<TicketDetail>> get(String id) async {
    final result =
        await _api.get<Map<String, dynamic>>('/me/support-tickets/$id');
    return switch (result) {
      Ok(:final value) => () {
          final ticket = value['ticket'] is Map
              ? SupportTicket.tryFromJson(
                  Map<String, dynamic>.from(value['ticket'] as Map))
              : null;
          if (ticket == null) {
            return const Err<TicketDetail>(
                ApiException('NOT_FOUND', 'ticket not found', 404));
          }
          final messages = ((value['messages'] as List?) ?? const [])
              .whereType<Map>()
              .map((row) =>
                  TicketMessage.tryFromJson(Map<String, dynamic>.from(row)))
              .whereType<TicketMessage>()
              .toList(growable: false);
          return Ok(TicketDetail(ticket: ticket, messages: messages));
        }(),
      Err(:final error) => Err(error),
    };
  }

  /// `POST /me/support-tickets/:id/messages` — the rider's reply on the
  /// thread.
  Future<Result<void>> reply(String id, String body) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/me/support-tickets/$id/messages',
      body: {'body': body.trim()},
    );
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// The list endpoint answers a BARE ARRAY of tickets.
  Future<Result<List<SupportTicket>>> list() async {
    final result = await _api.get<List<dynamic>>('/me/support-tickets');
    return switch (result) {
      Ok(:final value) => Ok(value
          .whereType<Map>()
          .map((row) =>
              SupportTicket.tryFromJson(Map<String, dynamic>.from(row)))
          .whereType<SupportTicket>()
          .toList(growable: false)),
      Err(:final error) => Err(error),
    };
  }
}

final supportTicketsRepositoryProvider = Provider<SupportTicketsRepository>(
    (ref) => SupportTicketsRepository(ref.watch(apiClientProvider)));
