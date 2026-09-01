import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/notifications/data/notifications_source.dart';
import 'package:hoppin_rider/features/notifications/domain/notification_item.dart';
import 'package:hoppin_rider/features/notifications/presentation/notifications_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockSource extends Mock implements NotificationsSource {}

final _sampleItems = [
  NotificationItem(
    id: '1',
    title: 'Driver Arrived',
    body: 'Your driver is arrived, Feel free to contact your driver',
    createdAt: DateTime(2026, 8, 31, 9),
    isRead: false,
    dayLabel: 'Today',
  ),
  NotificationItem(
    id: '2',
    title: 'New Message',
    body: 'You have a new message from George',
    createdAt: DateTime(2026, 8, 31, 8),
    isRead: true,
    dayLabel: 'Today',
  ),
];

Widget _harness(NotificationsSource source,
        {Brightness brightness = Brightness.light}) =>
    ProviderScope(
      overrides: [
        notificationsSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const NotificationsScreen(),
      ),
    );

void main() {
  late _MockSource source;

  setUp(() {
    source = _MockSource();
    when(() => source.list())
        .thenAnswer((_) async => const Ok<List<NotificationItem>>([]));
    when(() => source.markRead(any())).thenAnswer((_) async => const Ok(null));
    when(() => source.markAllRead()).thenAnswer((_) async => const Ok(null));
    when(() => source.dismiss(any())).thenAnswer((_) async => const Ok(null));
  });

  testWidgets('has a const constructor taking only a key', (tester) async {
    const screen = NotificationsScreen(key: Key('n'));
    expect(screen.key, const Key('n'));
  });

  testWidgets('loads from the live source on open', (tester) async {
    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    verify(() => source.list()).called(1);
  });

  testWidgets('renders an honest empty state when the feed is empty',
      (tester) async {
    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    // No invented rows: nothing that looks like a notification card appears.
    expect(find.text('Driver Arrived'), findsNothing);
    expect(find.textContaining('No notifications'), findsOneWidget);
  });

  testWidgets('a failed load renders the server copy verbatim', (tester) async {
    when(() => source.list()).thenAnswer((_) async =>
        const Err<List<NotificationItem>>(
            ApiException('INTERNAL', 'internal server error', 500)));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('internal server error'), findsOneWidget);
    // and NOT the cheerful empty copy, which would be a lie here
    expect(find.textContaining("all caught up"), findsNothing);
  });

  testWidgets('renders populated notifications grouped under a day label',
      (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<NotificationItem>>(_sampleItems));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Driver Arrived'), findsOneWidget);
    expect(find.text('New Message'), findsOneWidget);
  });

  testWidgets('All / Read / Unread tabs filter the list', (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<NotificationItem>>(_sampleItems));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('Driver Arrived'), findsOneWidget);
    expect(find.text('New Message'), findsOneWidget);

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('Driver Arrived'), findsOneWidget);
    expect(find.text('New Message'), findsNothing);

    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.text('Driver Arrived'), findsNothing);
    expect(find.text('New Message'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Driver Arrived'), findsOneWidget);
    expect(find.text('New Message'), findsOneWidget);
  });

  testWidgets('tapping a row marks it read against the endpoint',
      (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<NotificationItem>>(_sampleItems));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Driver Arrived'));
    await tester.pumpAndSettle();

    verify(() => source.markRead('1')).called(1);
  });

  testWidgets('Mark all as read calls read-all', (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<NotificationItem>>(_sampleItems));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    verify(() => source.markAllRead()).called(1);
  });

  testWidgets('Mark all as read is disabled once nothing is unread',
      (tester) async {
    when(() => source.list()).thenAnswer(
        (_) async => Ok<List<NotificationItem>>([_sampleItems[1]]));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    // The glass pill renders inert: tapping it must not call read-all.
    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    verifyNever(() => source.markAllRead());
  });

  testWidgets('Select is disabled with no rows to select', (tester) async {
    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    // With nothing to select the pill is inert — select mode never opens.
    // (The empty state shows no footer at all; guard both shapes.)
    if (tester.any(find.text('Select'))) {
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('Select mode dismisses the chosen rows', (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<NotificationItem>>(_sampleItems));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    // The footer swaps to Cancel / Delete, and Delete waits for a selection:
    // tapping it with nothing chosen must dismiss nothing.
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    verifyNever(() => source.dismiss(any()));

    await tester.tap(find.text('Driver Arrived'));
    await tester.pumpAndSettle();
    // In select mode a tap selects; it must NOT quietly mark the row read.
    verifyNever(() => source.markRead(any()));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => source.dismiss('1')).called(1);
    expect(find.text('Driver Arrived'), findsNothing);
    expect(find.text('New Message'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
  });

  testWidgets('Cancel leaves select mode without dismissing anything',
      (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<NotificationItem>>(_sampleItems));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver Arrived'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => source.dismiss(any()));
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(find.text('Driver Arrived'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(source, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
