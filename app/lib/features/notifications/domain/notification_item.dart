/// Which bucket a notification falls into for the All / Read / Unread tabs.
enum NotificationFilter { all, read, unread }

/// A single row on the Notifications screen.
///
/// There is no notifications endpoint anywhere in this API today - see
/// [NotificationsSource]. This model exists so the screen has something
/// concrete to render once a real source is plugged in; it is not fed by
/// invented data.
class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  /// Groups notifications under a day heading ("Today", "Yesterday", ...) the
  /// way the design draws them. A free-text label rather than a computed one
  /// so a real source can say "Today" without the screen re-deriving it from
  /// a timestamp and disagreeing with the server's clock.
  final String dayLabel;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.dayLabel,
  });

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        dayLabel: dayLabel,
      );
}
