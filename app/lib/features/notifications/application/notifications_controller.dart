import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notifications_source.dart';
import '../domain/notification_item.dart';

class NotificationsSnapshot {
  final List<NotificationItem> items;
  final NotificationFilter filter;
  final bool isLoading;

  const NotificationsSnapshot({
    this.items = const [],
    this.filter = NotificationFilter.all,
    this.isLoading = false,
  });

  List<NotificationItem> get visible => switch (filter) {
        NotificationFilter.all => items,
        NotificationFilter.read => items.where((n) => n.isRead).toList(),
        NotificationFilter.unread =>
          items.where((n) => !n.isRead).toList(),
      };

  NotificationsSnapshot copyWith({
    List<NotificationItem>? items,
    NotificationFilter? filter,
    bool? isLoading,
  }) =>
      NotificationsSnapshot(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        isLoading: isLoading ?? this.isLoading,
      );
}

class NotificationsController extends StateNotifier<NotificationsSnapshot> {
  final NotificationsSource _source;

  NotificationsController(this._source)
      : super(const NotificationsSnapshot());

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    final items = await _source.list();
    state = state.copyWith(items: items, isLoading: false);
  }

  void setFilter(NotificationFilter filter) {
    state = state.copyWith(filter: filter);
  }

  Future<void> markRead(String id) async {
    await _source.markRead(id);
    state = state.copyWith(
      items: [
        for (final n in state.items)
          if (n.id == id) n.copyWith(isRead: true) else n,
      ],
    );
  }

  Future<void> markAllRead() async {
    await _source.markAllRead();
    state = state.copyWith(
      items: [for (final n in state.items) n.copyWith(isRead: true)],
    );
  }
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsSnapshot>(
  (ref) => NotificationsController(ref.watch(notificationsSourceProvider)),
);
