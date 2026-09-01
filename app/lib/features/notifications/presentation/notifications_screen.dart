import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../application/notifications_controller.dart';
import '../domain/notification_item.dart';
import 'widgets/notification_tile.dart';

/// Notifications inbox, backed by `GET /me/notifications`.
///
/// Every row comes from the server; with an empty feed the honest empty state
/// renders rather than invented rows. The footer's two controls map to real
/// endpoints: "Mark all as read" to `POST /me/notifications/read-all`, and
/// "Select" to a selection mode that dismisses via
/// `DELETE /me/notifications/:id`.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(notificationsControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(notificationsControllerProvider);
    final notifier = ref.read(notificationsControllerProvider.notifier);

    // Group by dayLabel, preserving the order items arrived in.
    final grouped = <String, List<NotificationItem>>{};
    for (final item in state.visible) {
      grouped.putIfAbsent(item.dayLabel, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: _FilterTabs(
              filter: state.filter,
              onChanged: notifier.setFilter,
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.visible.isEmpty
                    ? _EmptyState(theme: theme, error: state.error)
                    : RefreshIndicator(
                        onRefresh: notifier.load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          children: [
                            for (final entry in grouped.entries) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8, top: 8),
                                child: Text(entry.key,
                                    style: theme.textTheme.titleMedium),
                              ),
                              for (var i = 0; i < entry.value.length; i++) ...[
                                NotificationTile(
                                  item: entry.value[i],
                                  accent: accentForIndex(i),
                                  selectable: state.isSelecting,
                                  selected: state.selectedIds
                                      .contains(entry.value[i].id),
                                  onTap: () => state.isSelecting
                                      ? notifier
                                          .toggleSelected(entry.value[i].id)
                                      : notifier.markRead(entry.value[i].id),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ],
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      // Selection is only meaningful with rows to select.
                      onPressed:
                          state.items.isEmpty ? null : notifier.toggleSelecting,
                      child: Text(state.isSelecting ? 'Cancel' : 'Select'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: state.isSelecting
                        ? OutlinedButton(
                            onPressed: state.selectedIds.isEmpty
                                ? null
                                : notifier.dismissSelected,
                            child: const Text('Delete'),
                          )
                        : OutlinedButton(
                            onPressed: state.unreadCount == 0
                                ? null
                                : notifier.markAllRead,
                            child: const Text('Mark all as read'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  final NotificationFilter filter;
  final ValueChanged<NotificationFilter> onChanged;

  const _FilterTabs({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Row(
        children: [
          _tab(context, 'All', NotificationFilter.all),
          _tab(context, 'Read', NotificationFilter.read),
          _tab(context, 'Unread', NotificationFilter.unread),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, NotificationFilter value) {
    final selected = filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyMedium?.color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing to show. Either the feed is genuinely empty - the caught-up copy -
/// or the load failed, in which case the server's own sentence renders rather
/// than a cheerful "all caught up" that would be a lie.
class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  final String? error;

  const _EmptyState({required this.theme, this.error});

  @override
  Widget build(BuildContext context) {
    final failed = error != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failed ? Icons.cloud_off : Icons.notifications_none,
                size: 56,
                color: Theme.of(context).textTheme.bodyMedium?.color),
            const SizedBox(height: 16),
            Text(
              failed
                  ? 'Notifications could not be loaded'
                  : 'No notifications yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              failed
                  ? error!
                  : "You're all caught up. New updates about your rides will appear here.",
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
