import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/result.dart';
import '../domain/notification_item.dart';

/// Empty-or-absent to null. Matches on the type rather than casting: `as
/// String?` throws on a non-string JSON value, which would make a hardening
/// helper the thing that crashes.
String? _orNull(Object? v) => switch (v) {
      String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    };

/// Rows the server sent that are not JSON objects at all.
///
/// `List.cast<Map<String, dynamic>>()` is LAZY in Dart: it validates nothing
/// at the call and throws a TypeError later, when `map` pulls an element. That
/// throw would escape a method whose signature promises a `Result`.
Iterable<Map<String, dynamic>> _objects(Object? raw) =>
    (raw is List ? raw : const []).whereType<Map<String, dynamic>>();

/// The day heading the design groups rows under.
///
/// The server sends only `created_at`, so the label is derived here rather
/// than in the widget - one place decides, and the tests can pin it without a
/// pump. Matches the chat screen's day pill so the two agree.
String dayLabelFor(DateTime createdAt, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final local = createdAt.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final delta = startOfToday.difference(day).inDays;

  if (delta == 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  return DateFormat('d MMM').format(day);
}

/// One page of the notification centre.
///
/// `unreadCount` is the whole feed's unread total, not this page's - the
/// server computes it separately for exactly that reason.
class NotificationsPage {
  final List<NotificationItem> items;
  final int unreadCount;
  final String? nextCursor;
  final bool hasMore;

  const NotificationsPage({
    this.items = const [],
    this.unreadCount = 0,
    this.nextCursor,
    this.hasMore = false,
  });
}

/// GET /me/notifications returns
/// `{"notifications":[...], "next_cursor":…, "has_more":…, "unread_count":N}`
/// with each row shaped by the Go `notificationItem`:
/// `{id, type, title, body, ride_id, deep_link, read_at, read, created_at}`.
class NotificationsRepository {
  final ApiClient _api;
  const NotificationsRepository(this._api);

  Future<Result<NotificationsPage>> list({String? cursor, int? limit}) async {
    final result = await _api.get<dynamic>('/me/notifications', query: {
      if (cursor != null) 'cursor': cursor,
      if (limit != null) 'limit': limit,
    });

    return switch (result) {
      Ok(:final value) => Ok(_page(value)),
      Err(:final error) => Err(error),
    };
  }

  /// Accepts the wrapper and a bare array, so a server-side shape change
  /// cannot silently empty the centre (it has happened on this API before -
  /// see the emergency-contacts note in `safety_repository.dart`).
  NotificationsPage _page(Object? value) {
    final map = value is Map ? value : const {};
    final raw = value is List ? value : map['notifications'];
    final now = DateTime.now();

    return NotificationsPage(
      items: _objects(raw)
          .map((j) => _tryItem(j, now))
          .whereType<NotificationItem>()
          .toList(growable: false),
      unreadCount: switch (map['unread_count']) {
        final num n => n.toInt(),
        _ => 0,
      },
      nextCursor: _orNull(map['next_cursor']),
      hasMore: map['has_more'] == true,
    );
  }

  /// Null for a row that cannot be rendered or acted on:
  ///
  /// - no `id`: it could never be marked read or dismissed, so the tap would
  ///   be a dead control;
  /// - no parseable `created_at`: it cannot be grouped under a day heading;
  /// - neither title nor body: an empty card that says nothing.
  static NotificationItem? _tryItem(Map<String, dynamic> json, DateTime now) {
    final id = _orNull(json['id']);
    if (id == null) return null;

    final createdAt = DateTime.tryParse(_orNull(json['created_at']) ?? '');
    if (createdAt == null) return null;

    final title = _orNull(json['title']) ?? '';
    final body = _orNull(json['body']) ?? '';
    if (title.isEmpty && body.isEmpty) return null;

    // read_at is the durable column; `read` is derived from it server-side.
    // Trusting the timestamp first means a stale flag cannot resurrect a row
    // in the Unread tab.
    final readAt = _orNull(json['read_at']);

    return NotificationItem(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt.toLocal(),
      isRead: readAt != null || json['read'] == true,
      dayLabel: dayLabelFor(createdAt, now: now),
    );
  }

  Future<Result<void>> markRead(String id) async {
    final result = await _api.patch<dynamic>('/me/notifications/$id/read');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> markAllRead() async {
    final result = await _api.post<dynamic>('/me/notifications/read-all');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// Dismisses one row. Soft-delete server-side: the row keeps its audit
  /// value, the list just stops showing it.
  Future<Result<void>> dismiss(String id) async {
    final result = await _api.delete<dynamic>('/me/notifications/$id');
    return switch (result) {
      Ok() => const Ok(null),
      Err(:final error) => Err(error),
    };
  }

  /// Clears the whole centre and reports how many rows went. Zero is a valid,
  /// successful answer.
  Future<Result<int>> clearAll() async {
    final result = await _api.delete<dynamic>('/me/notifications');
    return switch (result) {
      Ok(:final value) => Ok(switch ((value is Map ? value : const {})['deleted']) {
          final num n => n.toInt(),
          _ => 0,
        }),
      Err(:final error) => Err(error),
    };
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
    (ref) => NotificationsRepository(ref.watch(apiClientProvider)));
