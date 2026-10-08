import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/auth/account_generation.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/notifications/application/notifications_controller.dart';
import 'package:hoppin_rider/features/notifications/data/notifications_source.dart';
import 'package:hoppin_rider/features/notifications/domain/notification_item.dart';
import 'package:mocktail/mocktail.dart';

class _Source extends Mock implements NotificationsSource {}

void main() {
  test('an old account response cannot repopulate notifications after switching', () async {
    final source = _Source();
    final response = Completer<Result<List<NotificationItem>>>();
    when(() => source.list()).thenAnswer((_) => response.future);
    final container = ProviderContainer(overrides: [
      notificationsSourceProvider.overrideWithValue(source),
    ]);
    addTearDown(container.dispose);
    final old = container.read(notificationsControllerProvider.notifier);
    final loading = old.load();
    container.read(accountGenerationProvider.notifier).state++;
    final current = container.read(notificationsControllerProvider.notifier);
    expect(identical(old, current), isFalse);
    response.complete(const Ok(<NotificationItem>[]));
    await loading;
    expect(container.read(notificationsControllerProvider).isLoading, isFalse);
    expect(container.read(notificationsControllerProvider).items, isEmpty);
  });
}
