import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notification_item.dart';

/// Where the Notifications screen gets its rows.
///
/// There is no notifications endpoint in this API - searched `app/lib` and
/// the backend contracts recorded in `docs/SCREEN-DECISIONS.md`, neither has
/// one. [NoNotificationsSource] is the only implementation today and always
/// returns an empty list, so the screen renders its honest empty state
/// rather than inventing rows that look live.
///
/// When a real endpoint exists, add a `RemoteNotificationsSource` here and
/// swap the provider override below - the screen and controller do not
/// change.
abstract class NotificationsSource {
  Future<List<NotificationItem>> list();

  /// Marks one notification read. A no-op source has nothing to persist to,
  /// so it simply returns - the controller still updates local state so the
  /// UI reflects the tap.
  Future<void> markRead(String id) async {}

  Future<void> markAllRead() async {}
}

/// The only implementation until a backend exists. Deliberately named so it
/// cannot be mistaken for a real data source.
class NoNotificationsSource implements NotificationsSource {
  const NoNotificationsSource();

  @override
  Future<List<NotificationItem>> list() async => const [];

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}
}

final notificationsSourceProvider = Provider<NotificationsSource>(
    (ref) => const NoNotificationsSource());
