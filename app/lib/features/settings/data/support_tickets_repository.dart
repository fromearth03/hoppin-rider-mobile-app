import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
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

  const SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.body,
    required this.createdAt,
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
    );
  }
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

  Future<Result<void>> open({
    required String subject,
    String? typeCode,
    String? body,
  }) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/me/support-tickets',
      body: {
        'subject': subject,
        if (typeCode != null && typeCode.isNotEmpty) 'type_code': typeCode,
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      },
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
