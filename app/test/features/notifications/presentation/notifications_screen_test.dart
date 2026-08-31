import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    when(() => source.list()).thenAnswer((_) async => const []);
    when(() => source.markRead(any())).thenAnswer((_) async {});
    when(() => source.markAllRead()).thenAnswer((_) async {});
  });

  testWidgets('has a const constructor taking only a key', (tester) async {
    const screen = NotificationsScreen(key: Key('n'));
    expect(screen.key, const Key('n'));
  });

  testWidgets('renders an honest empty state when the source has nothing',
      (tester) async {
    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    // No invented rows: nothing that looks like a notification card appears.
    expect(find.text('Driver Arrived'), findsNothing);
    expect(find.textContaining('No notifications'), findsOneWidget);
  });

  testWidgets('renders populated notifications grouped under a day label',
      (tester) async {
    when(() => source.list()).thenAnswer((_) async => _sampleItems);

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Driver Arrived'), findsOneWidget);
    expect(find.text('New Message'), findsOneWidget);
  });

  testWidgets('All / Read / Unread tabs filter the list', (tester) async {
    when(() => source.list()).thenAnswer((_) async => _sampleItems);

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

  testWidgets('Mark all as read calls through to the source', (tester) async {
    when(() => source.list()).thenAnswer((_) async => _sampleItems);

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    verify(() => source.markAllRead()).called(1);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(source, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
