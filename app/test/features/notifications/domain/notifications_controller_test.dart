import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/notifications/application/notifications_controller.dart';
import 'package:hoppin_rider/features/notifications/data/notifications_source.dart';
import 'package:hoppin_rider/features/notifications/domain/notification_item.dart';
import 'package:mocktail/mocktail.dart';

class _MockSource extends Mock implements NotificationsSource {}

NotificationItem _item(String id, {required bool isRead, String? title}) =>
    NotificationItem(
      id: id,
      title: title ?? 'Notification $id',
      body: 'body',
      createdAt: DateTime(2026, 8, 31),
      isRead: isRead,
      dayLabel: 'Today',
    );

void main() {
  late _MockSource source;
  late NotificationsController controller;

  setUp(() {
    source = _MockSource();
    when(() => source.list())
        .thenAnswer((_) async => const Ok<List<NotificationItem>>([]));
    when(() => source.markRead(any())).thenAnswer((_) async => const Ok(null));
    when(() => source.markAllRead()).thenAnswer((_) async => const Ok(null));
    when(() => source.dismiss(any())).thenAnswer((_) async => const Ok(null));
    controller = NotificationsController(source);
  });

  test('visible filters on read state for the All / Read / Unread tabs', () {
    final read = _item('1', isRead: true);
    final unread = _item('2', isRead: false);
    final all = NotificationsSnapshot(items: [read, unread]);

    expect(all.visible, [read, unread]);
    expect(all.copyWith(filter: NotificationFilter.read).visible, [read]);
    expect(all.copyWith(filter: NotificationFilter.unread).visible, [unread]);
  });

  test('load fills the list from the source', () async {
    when(() => source.list()).thenAnswer(
        (_) async => Ok<List<NotificationItem>>([_item('1', isRead: false)]));

    await controller.load();

    expect(controller.state.items, hasLength(1));
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.error, isNull);
  });

  test('a failed load keeps the server copy verbatim and empties the list',
      () async {
    when(() => source.list()).thenAnswer((_) async =>
        const Err<List<NotificationItem>>(
            ApiException('INTERNAL', 'internal server error', 500)));

    await controller.load();

    expect(controller.state.error, 'internal server error');
    expect(controller.state.items, isEmpty);
    expect(controller.state.isLoading, isFalse);
  });

  test('a reload clears a previous error', () async {
    when(() => source.list()).thenAnswer((_) async =>
        const Err<List<NotificationItem>>(ApiException('INTERNAL', 'boom', 500)));
    await controller.load();
    expect(controller.state.error, 'boom');

    when(() => source.list())
        .thenAnswer((_) async => const Ok<List<NotificationItem>>([]));
    await controller.load();

    expect(controller.state.error, isNull);
  });

  test('markRead flips the row only after the server accepts it', () async {
    when(() => source.list()).thenAnswer(
        (_) async => Ok<List<NotificationItem>>([_item('1', isRead: false)]));
    await controller.load();

    await controller.markRead('1');

    expect(controller.state.items.single.isRead, isTrue);
    verify(() => source.markRead('1')).called(1);
  });

  test('a rejected markRead leaves the row unread rather than lying', () async {
    when(() => source.list()).thenAnswer(
        (_) async => Ok<List<NotificationItem>>([_item('1', isRead: false)]));
    await controller.load();
    when(() => source.markRead(any())).thenAnswer(
        (_) async => const Err<void>(ApiException('NOT_FOUND', 'not found', 404)));

    await controller.markRead('1');

    expect(controller.state.items.single.isRead, isFalse);
    expect(controller.state.error, 'not found');
  });

  test('markRead on an already-read row does not call the server', () async {
    when(() => source.list()).thenAnswer(
        (_) async => Ok<List<NotificationItem>>([_item('1', isRead: true)]));
    await controller.load();

    await controller.markRead('1');

    verifyNever(() => source.markRead(any()));
  });

  test('markAllRead flips every row once the server accepts', () async {
    when(() => source.list()).thenAnswer((_) async =>
        Ok<List<NotificationItem>>(
            [_item('1', isRead: false), _item('2', isRead: false)]));
    await controller.load();

    await controller.markAllRead();

    expect(controller.state.items.every((n) => n.isRead), isTrue);
    verify(() => source.markAllRead()).called(1);
  });

  test('a rejected markAllRead leaves every row as it was', () async {
    when(() => source.list()).thenAnswer(
        (_) async => Ok<List<NotificationItem>>([_item('1', isRead: false)]));
    await controller.load();
    when(() => source.markAllRead()).thenAnswer(
        (_) async => const Err<void>(ApiException('INTERNAL', 'server error', 500)));

    await controller.markAllRead();

    expect(controller.state.items.single.isRead, isFalse);
    expect(controller.state.error, 'server error');
  });

  group('selection', () {
    Future<void> loadTwo() async {
      when(() => source.list()).thenAnswer((_) async =>
          Ok<List<NotificationItem>>(
              [_item('1', isRead: false), _item('2', isRead: true)]));
      await controller.load();
    }

    test('toggling select mode starts with nothing selected', () async {
      await loadTwo();

      controller.toggleSelecting();

      expect(controller.state.isSelecting, isTrue);
      expect(controller.state.selectedIds, isEmpty);
    });

    test('leaving select mode drops the selection', () async {
      await loadTwo();
      controller.toggleSelecting();
      controller.toggleSelected('1');

      controller.toggleSelecting();

      expect(controller.state.isSelecting, isFalse);
      expect(controller.state.selectedIds, isEmpty);
    });

    test('toggling a row selects then deselects it', () async {
      await loadTwo();
      controller.toggleSelecting();

      controller.toggleSelected('1');
      expect(controller.state.selectedIds, {'1'});

      controller.toggleSelected('1');
      expect(controller.state.selectedIds, isEmpty);
    });

    test('dismissing removes the selected rows and leaves select mode',
        () async {
      await loadTwo();
      controller.toggleSelecting();
      controller.toggleSelected('1');

      await controller.dismissSelected();

      expect(controller.state.items.map((n) => n.id), ['2']);
      expect(controller.state.isSelecting, isFalse);
      expect(controller.state.selectedIds, isEmpty);
      verify(() => source.dismiss('1')).called(1);
    });

    test('dismissing nothing calls no endpoint', () async {
      await loadTwo();
      controller.toggleSelecting();

      await controller.dismissSelected();

      verifyNever(() => source.dismiss(any()));
      expect(controller.state.items, hasLength(2));
    });

    test('a row the server refused to dismiss stays in the list', () async {
      await loadTwo();
      controller.toggleSelecting();
      controller.toggleSelected('1');
      controller.toggleSelected('2');
      when(() => source.dismiss('1'))
          .thenAnswer((_) async => const Ok(null));
      when(() => source.dismiss('2')).thenAnswer((_) async =>
          const Err<void>(ApiException('INTERNAL', 'could not dismiss', 500)));

      await controller.dismissSelected();

      expect(controller.state.items.map((n) => n.id), ['2'],
          reason: 'only what the server actually removed disappears');
      expect(controller.state.error, 'could not dismiss');
    });
  });
}
