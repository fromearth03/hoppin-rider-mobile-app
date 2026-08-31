import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../application/notifications_controller.dart';
import '../domain/notification_item.dart';
import 'widgets/notification_tile.dart';

/// Notifications inbox.
///
/// There is no notifications endpoint anywhere in this API - see
/// [NotificationsSource]. The list is driven entirely by whatever source is
/// wired to [notificationsSourceProvider], which defaults to
/// [NoNotificationsSource] and therefore renders empty until a real backend
/// exists. Nothing on this screen is invented.
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
                    ? _EmptyState(theme: theme)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        children: [
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8, top: 8),
                              child: Text(entry.key,
                                  style: theme.textTheme.titleMedium),
                            ),
                            for (var i = 0; i < entry.value.length; i++) ...[
                              NotificationTile(
                                item: entry.value[i],
                                accent: accentForIndex(i),
                                onTap: () =>
                                    notifier.markRead(entry.value[i].id),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ],
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
                      onPressed: () {},
                      child: const Text('Select'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          state.items.isEmpty ? null : notifier.markAllRead,
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

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none,
                size: 56,
                color: Theme.of(context).textTheme.bodyMedium?.color),
            const SizedBox(height: 16),
            Text(
              'No notifications yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "You're all caught up. New updates about your rides will appear here.",
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
