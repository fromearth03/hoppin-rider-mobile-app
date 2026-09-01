import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../domain/notification_item.dart';
import 'notifications_repository.dart';

/// What the Notifications screen loads.
///
/// A thin seam over [NotificationsRepository] so the screen and its goldens
/// can be driven from a fake without a network. The repository owns the wire
/// format; this owns nothing but the shape the controller wants. Failure
/// stays a [Result] all the way to the controller, which renders the server's
/// own words rather than a swallowed exception.
abstract class NotificationsSource {
  Future<Result<List<NotificationItem>>> list();

  Future<Result<void>> markRead(String id);

  Future<Result<void>> markAllRead();

  /// Dismisses one row (soft-delete server-side).
  Future<Result<void>> dismiss(String id);
}

/// The live implementation: `GET /me/notifications` and its mutations.
class RemoteNotificationsSource implements NotificationsSource {
  final NotificationsRepository _repo;
  const RemoteNotificationsSource(this._repo);

  @override
  Future<Result<List<NotificationItem>>> list() async =>
      switch (await _repo.list()) {
        Ok(:final value) => Ok(value.items),
        Err(:final error) => Err(error),
      };

  @override
  Future<Result<void>> markRead(String id) => _repo.markRead(id);

  @override
  Future<Result<void>> markAllRead() => _repo.markAllRead();

  @override
  Future<Result<void>> dismiss(String id) => _repo.dismiss(id);
}

final notificationsSourceProvider = Provider<NotificationsSource>((ref) =>
    RemoteNotificationsSource(ref.watch(notificationsRepositoryProvider)));
