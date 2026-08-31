import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/notifications/application/notifications_controller.dart';
import 'package:hoppin_rider/features/notifications/data/notifications_source.dart';
import 'package:hoppin_rider/features/notifications/domain/notification_item.dart';

void main() {
  test('NoNotificationsSource always returns an empty list', () async {
    const source = NoNotificationsSource();
    expect(await source.list(), isEmpty);
  });

  test('NotificationsSnapshot.visible filters correctly', () {
    final read = NotificationItem(
      id: '1',
      title: 'Read one',
      body: 'body',
      createdAt: DateTime(2026, 1, 1),
      isRead: true,
      dayLabel: 'Today',
    );
    final unread = NotificationItem(
      id: '2',
      title: 'Unread one',
      body: 'body',
      createdAt: DateTime(2026, 1, 1),
      isRead: false,
      dayLabel: 'Today',
    );

    final all = NotificationsSnapshot(items: [read, unread]);
    expect(all.visible, [read, unread]);

    final onlyRead = all.copyWith(filter: NotificationFilter.read);
    expect(onlyRead.visible, [read]);

    final onlyUnread = all.copyWith(filter: NotificationFilter.unread);
    expect(onlyUnread.visible, [unread]);
  });
}
