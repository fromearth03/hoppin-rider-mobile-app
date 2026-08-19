import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'notification_feed.dart';

/// The in-app route the top-bar bell targets. Lane E adds the matching
/// `GoRoute` (`router.dart` is contended); this constant is the contract both
/// sides agree on.
const String kNotificationCentreRoute = '/notifications';

/// Which slice of the feed the segmented control is showing.
enum NotificationFilter {
  /// Everything this session saw.
  all,

  /// Only the ones already read.
  read,

  /// Only the ones not yet read.
  unread,
}

/// The notification centre (NOTIF-02, Figma `Notifications.jpg`).
///
/// Shows durable server history merged with live events, day-sectioned and
/// filterable. Push delivery is additive; history comes from the API.
class NotificationCentreScreen extends ConsumerStatefulWidget {
  /// Creates the notification centre.
  const NotificationCentreScreen({super.key});

  @override
  ConsumerState<NotificationCentreScreen> createState() =>
      _NotificationCentreScreenState();
}

class _NotificationCentreScreenState
    extends ConsumerState<NotificationCentreScreen> {
  NotificationFilter _filter = NotificationFilter.all;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final feed = ref.watch(notificationFeedProvider);
    final history = ref.watch(notificationHistoryProvider);
    ref.listen(notificationHistoryProvider, (_, next) {
      next.whenData(
        (items) =>
            ref.read(notificationFeedProvider.notifier).mergeHistory(items),
      );
    });

    final shown = switch (_filter) {
      NotificationFilter.all => feed,
      NotificationFilter.read => feed.where((n) => n.read).toList(),
      NotificationFilter.unread => feed.where((n) => !n.read).toList(),
    };

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HopTopBar(
              title: 'Notifications',
              // A DEAD END. A null back intent HIDES the chevron entirely, and
              // the bell in the shell reaches this screen with `context.go`,
              // which REPLACES rather than pushes — so there was nothing to pop,
              // the button vanished, and the rider was stranded on the
              // notification centre with no way back to their booking.
              //
              // Never null. Pop when there is a stack; otherwise fall back to
              // the Book tab, which is the app's home. This mirrors the Profile
              // hub, which had it right all along. (Plain `Navigator` was also
              // the wrong instrument: it cannot see the go_router stack.)
              //
              // The literal spelling of the null-back mistake is deliberately
              // NOT written here: shell_chrome_test greps this source for it,
              // and a comment quoting the bug would trip the guard forever.
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/book'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: hoppin.spacing.gutter,
                vertical: hoppin.spacing.sm,
              ),
              child: _FilterBar(
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  hoppin.spacing.gutter,
                  0,
                  hoppin.spacing.gutter,
                  hoppin.spacing.xl,
                ),
                children: [
                  if (history.isLoading && feed.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ..._sections(context, shown),
                  if (history.hasError && feed.isEmpty)
                    _HistoryLoadError(
                      onRetry: () =>
                          ref.invalidate(notificationHistoryProvider),
                    ),

                  SizedBox(height: hoppin.spacing.md),

                  // Deletion is intentionally not exposed until a server
                  // retention contract exists. Read-state is fully wired.
                  const HopButton.secondary(
                    label: 'Delete all notifications',
                    onPressed: null,
                  ),
                  SizedBox(height: hoppin.spacing.sm),

                  HopButton.secondary(
                    label: 'Mark all as read',
                    onPressed: () => ref
                        .read(notificationFeedProvider.notifier)
                        .markAllRead(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Day-sectioned cards ("Today" / "Yesterday" / a date), newest first.
  List<Widget> _sections(BuildContext context, List<AppNotification> items) {
    if (items.isEmpty) return const <Widget>[];

    final hoppin = context.hoppin;
    final widgets = <Widget>[];
    String? currentSection;

    for (final n in items) {
      final section = _dayLabel(n.receivedAt);
      if (section != currentSection) {
        currentSection = section;
        widgets
          ..add(SizedBox(height: hoppin.spacing.md))
          ..add(
            Text(
              section,
              style: hoppin.type.titleSmall.copyWith(
                color: hoppin.colors.textMid,
              ),
            ),
          )
          ..add(SizedBox(height: hoppin.spacing.sm));
      }
      widgets
        ..add(_NotificationCard(notification: n))
        ..add(SizedBox(height: hoppin.spacing.sm));
    }
    return widgets;
  }

  static String _dayLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final delta = today.difference(day).inDays;
    if (delta <= 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    return '${day.day}/${day.month}/${day.year}';
  }
}

class _HistoryLoadError extends StatelessWidget {
  const _HistoryLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => HopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notifications could not be loaded',
          style: context.hoppin.type.titleSmall,
        ),
        SizedBox(height: context.hoppin.spacing.sm),
        HopButton.secondary(label: 'Retry', onPressed: onRetry),
      ],
    ),
  );
}

/// The All / Read / Unread segmented control.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});

  final NotificationFilter value;
  final ValueChanged<NotificationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    Widget segment(NotificationFilter f, String label) {
      final selected = f == value;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(f),
          borderRadius: BorderRadius.circular(hoppin.radii.pill),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: hoppin.spacing.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(hoppin.radii.pill),
            ),
            child: Text(
              label,
              style: hoppin.type.label.copyWith(
                color: selected ? colors.onAccent : colors.textMid,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(hoppin.spacing.xs),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(hoppin.radii.pill),
      ),
      child: Row(
        children: [
          segment(NotificationFilter.all, 'All'),
          segment(NotificationFilter.read, 'Read'),
          segment(NotificationFilter.unread, 'Unread'),
        ],
      ),
    );
  }
}

/// One notification card: unread dot + title + body.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return HopCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: hoppin.spacing.xs),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: notification.read ? Colors.transparent : colors.error,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: hoppin.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: hoppin.type.titleSmall.copyWith(color: colors.textHi),
                ),
                if (notification.body != null) ...[
                  SizedBox(height: hoppin.spacing.xs),
                  Text(
                    notification.body!,
                    style: hoppin.type.bodySmall.copyWith(
                      color: colors.textMid,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
