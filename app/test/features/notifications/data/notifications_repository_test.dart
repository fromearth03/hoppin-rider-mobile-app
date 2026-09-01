import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_client.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/notifications/data/notifications_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements ApiClient {}

/// Shapes below are the live contract, read from the Go source
/// (`ride_handler.go` ListMyNotifications + `rider_gaps.go` notificationItem):
/// {"notifications":[{id,type,title,body,ride_id,deep_link,read_at,read,
/// created_at}], "next_cursor":null, "has_more":false, "unread_count":N}
void main() {
  late _MockApi api;
  late NotificationsRepository repo;

  setUp(() {
    api = _MockApi();
    repo = NotificationsRepository(api);
  });

  Map<String, dynamic> row({
    String id = 'n1',
    String title = 'Driver Arrived',
    String body = 'Your driver is arrived',
    Object? readAt,
    bool read = false,
    String createdAt = '2026-08-31T09:00:00Z',
  }) =>
      {
        'id': id,
        'type': 'ride',
        'title': title,
        'body': body,
        'ride_id': null,
        'read_at': readAt,
        'read': read,
        'created_at': createdAt,
      };

  group('list', () {
    test('reads the wrapped shape the handler returns', () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [row()],
                'next_cursor': null,
                'has_more': false,
                'unread_count': 1,
              }));

      final page = ((await repo.list()) as Ok<NotificationsPage>).value;

      expect(page.items, hasLength(1));
      expect(page.items.first.id, 'n1');
      expect(page.items.first.title, 'Driver Arrived');
      expect(page.unreadCount, 1);
    });

    test('sends no cursor on the first page', () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => const Ok<dynamic>({'notifications': []}));

      await repo.list();

      final query = verify(() => api.get<dynamic>('/me/notifications',
          query: captureAny(named: 'query'))).captured.single as Map?;

      expect(query?.containsKey('cursor'), isFalse);
    });

    test('read state follows read_at, not just the read flag', () async {
      // The handler sets both, but read_at is the durable column; a row that
      // carries a timestamp and a stale `read:false` is read.
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [
                  row(id: 'a', readAt: '2026-08-31T10:00:00Z', read: false),
                  row(id: 'b', readAt: null, read: false),
                ],
              }));

      final items = ((await repo.list()) as Ok<NotificationsPage>).value.items;

      expect(items.map((n) => n.isRead), [true, false]);
    });

    test('a non-object row does not take down the list', () async {
      // List.cast() is lazy in Dart: it throws when map pulls the bad element,
      // escaping a method whose signature promises a Result. ApiClient catches
      // only DioException, so it would propagate to a caller that cannot see
      // it coming.
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [
                  row(id: 'a', title: 'Kept'),
                  null,
                  'not an object',
                  row(id: 'b', title: 'Also kept'),
                ],
              }));

      final items = ((await repo.list()) as Ok<NotificationsPage>).value.items;

      expect(items.map((n) => n.title), ['Kept', 'Also kept']);
    });

    test('a row with no id is dropped: it can never be marked read', () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [
                  {'title': 'No id', 'body': 'b', 'created_at': '2026-08-31T09:00:00Z'},
                  row(id: 'ok'),
                ],
              }));

      final items = ((await repo.list()) as Ok<NotificationsPage>).value.items;

      expect(items.map((n) => n.id), ['ok']);
    });

    test('a row with an unparseable created_at is dropped', () async {
      // dayLabel is derived from created_at; without one the row cannot be
      // grouped under a heading and would render orphaned.
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [
                  row(id: 'bad', createdAt: 'not a timestamp'),
                  row(id: 'ok'),
                ],
              }));

      final items = ((await repo.list()) as Ok<NotificationsPage>).value.items;

      expect(items.map((n) => n.id), ['ok']);
    });

    test('a row with no title and no body is dropped, not rendered blank',
        () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [
                  row(id: 'blank', title: '', body: ''),
                  row(id: 'ok'),
                ],
              }));

      final items = ((await repo.list()) as Ok<NotificationsPage>).value.items;

      expect(items.map((n) => n.id), ['ok']);
    });

    test('a title-only row is kept: the body line just renders empty',
        () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [row(id: 't', title: 'Driver Arrived', body: '')],
              }));

      final items = ((await repo.list()) as Ok<NotificationsPage>).value.items;

      expect(items.single.title, 'Driver Arrived');
      expect(items.single.body, isEmpty);
    });

    test('a bare array is accepted too, so a wrapper change cannot break it',
        () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>([row()]));

      final page = ((await repo.list()) as Ok<NotificationsPage>).value;

      expect(page.items, hasLength(1));
    });

    test('an empty feed is an empty page, not an error', () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => const Ok<dynamic>({
                'notifications': [],
                'unread_count': 0,
              }));

      final page = ((await repo.list()) as Ok<NotificationsPage>).value;

      expect(page.items, isEmpty);
      expect(page.unreadCount, 0);
      expect(page.hasMore, isFalse);
    });

    test('carries the cursor and has_more through for paging', () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query')))
          .thenAnswer((_) async => Ok<dynamic>({
                'notifications': [row()],
                'next_cursor': '2026-08-31T09:00:00Z',
                'has_more': true,
              }));

      final page = ((await repo.list()) as Ok<NotificationsPage>).value;

      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '2026-08-31T09:00:00Z');
    });

    test('surfaces the server failure verbatim', () async {
      when(() => api.get<dynamic>(any(), query: any(named: 'query'))).thenAnswer(
          (_) async =>
              const Err<dynamic>(ApiException('INTERNAL', 'internal server error', 500)));

      final result = await repo.list();

      expect((result as Err).error.message, 'internal server error');
    });
  });

  group('day labels', () {
    test('today, yesterday and older read as the design draws them', () {
      final now = DateTime(2026, 8, 31, 12);
      expect(dayLabelFor(DateTime(2026, 8, 31, 9), now: now), 'Today');
      expect(dayLabelFor(DateTime(2026, 8, 30, 23), now: now), 'Yesterday');
      expect(dayLabelFor(DateTime(2026, 8, 12), now: now), '12 Aug');
    });
  });

  group('mutations', () {
    test('markRead patches the row', () async {
      when(() => api.patch<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async =>
              const Ok<dynamic>({'message': 'notification marked as read'}));

      final result = await repo.markRead('n1');

      expect(result, isA<Ok>());
      verify(() => api.patch<dynamic>('/me/notifications/n1/read')).called(1);
    });

    test('markAllRead posts to read-all', () async {
      when(() => api.post<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async =>
              const Ok<dynamic>({'message': 'notifications marked as read'}));

      await repo.markAllRead();

      verify(() => api.post<dynamic>('/me/notifications/read-all')).called(1);
    });

    test('dismiss deletes one row', () async {
      when(() => api.delete<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok<dynamic>({'deleted': 1}));

      final result = await repo.dismiss('n1');

      expect(result, isA<Ok>());
      verify(() => api.delete<dynamic>('/me/notifications/n1')).called(1);
    });

    test('a 404 on dismiss surfaces rather than pretending it worked',
        () async {
      when(() => api.delete<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async =>
              const Err<dynamic>(ApiException('NOT_FOUND', 'notification not found', 404)));

      final result = await repo.dismiss('gone');

      expect((result as Err).error.code, 'NOT_FOUND');
    });

    test('clearAll reports how many rows the server dismissed', () async {
      when(() => api.delete<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok<dynamic>({'deleted': 4}));

      final n = ((await repo.clearAll()) as Ok<int>).value;

      expect(n, 4);
      verify(() => api.delete<dynamic>('/me/notifications')).called(1);
    });

    test('clearAll on an empty centre is a successful zero', () async {
      when(() => api.delete<dynamic>(any(), body: any(named: 'body')))
          .thenAnswer((_) async => const Ok<dynamic>({'deleted': 0}));

      expect(((await repo.clearAll()) as Ok<int>).value, 0);
    });
  });
}
