import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../data/notifications_source.dart';
import '../domain/notification_item.dart';

class NotificationsSnapshot {
  final List<NotificationItem> items;
  final NotificationFilter filter;
  final bool isLoading;

  /// The server's own words when a call failed, null otherwise. Never a
  /// client-written sentence - the API owns this copy.
  final String? error;

  /// The "Select" mode the design's footer button enters.
  final bool isSelecting;
  final Set<String> selectedIds;

  const NotificationsSnapshot({
    this.items = const [],
    this.filter = NotificationFilter.all,
    this.isLoading = false,
    this.error,
    this.isSelecting = false,
    this.selectedIds = const {},
  });

  List<NotificationItem> get visible => switch (filter) {
        NotificationFilter.all => items,
        NotificationFilter.read => items.where((n) => n.isRead).toList(),
        NotificationFilter.unread =>
          items.where((n) => !n.isRead).toList(),
      };

  int get unreadCount => items.where((n) => !n.isRead).length;

  NotificationsSnapshot copyWith({
    List<NotificationItem>? items,
    NotificationFilter? filter,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isSelecting,
    Set<String>? selectedIds,
  }) =>
      NotificationsSnapshot(
        items: items ?? this.items,
        filter: filter ?? this.filter,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        isSelecting: isSelecting ?? this.isSelecting,
        selectedIds: selectedIds ?? this.selectedIds,
      );
}

class NotificationsController extends StateNotifier<NotificationsSnapshot> {
  final NotificationsSource _source;

  NotificationsController(this._source)
      : super(const NotificationsSnapshot());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    switch (await _source.list()) {
      case Ok(:final value):
        state = state.copyWith(items: value, isLoading: false);
      case Err(:final error):
        // The list is emptied rather than left stale: the screen's empty
        // state plus the server's message is honest, a stale list is not.
        state = state.copyWith(
            items: const [], isLoading: false, error: error.message);
    }
  }

  void setFilter(NotificationFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// Marks one row read. Local state moves only once the server has accepted
  /// it - an optimistic flip would show a row as read that the next load
  /// brings back unread.
  Future<void> markRead(String id) async {
    final current = state.items.where((n) => n.id == id).firstOrNull;
    if (current == null || current.isRead) return;

    switch (await _source.markRead(id)) {
      case Ok():
        state = state.copyWith(items: [
          for (final n in state.items)
            if (n.id == id) n.copyWith(isRead: true) else n,
        ]);
      case Err(:final error):
        state = state.copyWith(error: error.message);
    }
  }

  Future<void> markAllRead() async {
    switch (await _source.markAllRead()) {
      case Ok():
        state = state.copyWith(
          items: [for (final n in state.items) n.copyWith(isRead: true)],
          clearError: true,
        );
      case Err(:final error):
        state = state.copyWith(error: error.message);
    }
  }

  void toggleSelecting() {
    state = state.copyWith(
      isSelecting: !state.isSelecting,
      selectedIds: const {},
      clearError: true,
    );
  }

  void toggleSelected(String id) {
    final next = {...state.selectedIds};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(selectedIds: next);
  }

  /// Dismisses the selected rows (DELETE /me/notifications/:id each).
  ///
  /// Only the rows the server actually removed leave the list; one that was
  /// refused stays visible with the server's message, rather than vanishing
  /// locally and reappearing on the next load.
  Future<void> dismissSelected() async {
    final ids = state.selectedIds;
    if (ids.isEmpty) {
      state = state.copyWith(isSelecting: false, selectedIds: const {});
      return;
    }

    final removed = <String>{};
    String? failure;
    for (final id in ids) {
      switch (await _source.dismiss(id)) {
        case Ok():
          removed.add(id);
        case Err(:final error):
          failure ??= error.message;
      }
    }

    state = state.copyWith(
      items: [
        for (final n in state.items)
          if (!removed.contains(n.id)) n,
      ],
      isSelecting: false,
      selectedIds: const {},
      error: failure,
      clearError: failure == null,
    );
  }
}

final notificationsControllerProvider =
    StateNotifierProvider<NotificationsController, NotificationsSnapshot>(
  (ref) => NotificationsController(ref.watch(notificationsSourceProvider)),
);
