import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/notifications/notification_centre_screen.dart';
import 'package:hoppin_rider/features/notifications/notification_feed.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// NOTIF-02 — the notification centre (#33) and durable notification history.
void main() {
  Future<void> pumpCentre(
    WidgetTester tester, {
    List<AppNotification> feed = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationFeedProvider.overrideWith(
            () => NotificationFeed.seeded(feed),
          ),
        ],
        child: MaterialApp(
          theme: HoppinTheme.riderLight(),
          home: const NotificationCentreScreen(),
        ),
      ),
    );
    // Bounded pumps only — never pumpAndSettle (project convention).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  AppNotification note(
    String id, {
    required String title,
    bool read = false,
    DateTime? at,
  }) => AppNotification(
    id: id,
    title: title,
    body: 'body of $id',
    read: read,
    receivedAt: at ?? DateTime.now(),
  );

  group('NOTIF-02: the cold-start centre loads real history', () {
    testWidgets('an empty feed does not show the old history disclosure', (
      tester,
    ) async {
      await pumpCentre(tester);

      expect(
        find.textContaining("Older notifications can't be loaded"),
        findsNothing,
      );
    });

    testWidgets('the empty centre does not assert notification emptiness', (
      tester,
    ) async {
      await pumpCentre(tester);

      expect(
        find.textContaining('no notifications', findRichText: true),
        findsNothing,
        reason: 'The history endpoint is now the source of truth.',
      );
      expect(
        find.textContaining('No notifications', findRichText: true),
        findsNothing,
        reason: 'Same lie, capitalised.',
      );
    });

    testWidgets('"Delete all notifications" is DISABLED on the empty centre', (
      tester,
    ) async {
      await pumpCentre(tester);

      final button = tester.widget<HopButton>(
        find.widgetWithText(HopButton, 'Delete all notifications'),
      );
      expect(
        button.onPressed,
        isNull,
        reason:
            'Deleting a SERVER record we cannot reach would be a lie. The '
            'control ships (the design is real) but it is inert and disclosed.',
      );
    });
  });

  group('NOTIF-02: a populated feed renders the real list', () {
    testWidgets('seeded events render as cards', (tester) async {
      await pumpCentre(
        tester,
        feed: [
          note('n1', title: 'Driver arrived'),
          note('n2', title: 'New message', read: true),
        ],
      );

      expect(find.text('Driver arrived'), findsOneWidget);
      expect(find.text('New message'), findsOneWidget);
    });

    testWidgets('a populated feed does not show the old history disclosure', (
      tester,
    ) async {
      await pumpCentre(tester, feed: [note('n1', title: 'Driver arrived')]);

      expect(
        find.textContaining("Older notifications can't be loaded"),
        findsNothing,
      );
    });

    testWidgets('the All / Read / Unread filter narrows the list', (
      tester,
    ) async {
      await pumpCentre(
        tester,
        feed: [
          note('n1', title: 'Driver arrived'),
          note('n2', title: 'New message', read: true),
        ],
      );

      // All → both.
      expect(find.text('Driver arrived'), findsOneWidget);
      expect(find.text('New message'), findsOneWidget);

      await tester.tap(find.text('Unread'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.text('Driver arrived'),
        findsOneWidget,
        reason: 'n1 is unread.',
      );
      expect(
        find.text('New message'),
        findsNothing,
        reason: 'n2 is read — the Unread filter must exclude it.',
      );

      await tester.tap(find.text('Read'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Driver arrived'), findsNothing);
      expect(find.text('New message'), findsOneWidget);
    });

    testWidgets('"Mark all as read" is ENABLED and clears the unread state', (
      tester,
    ) async {
      await pumpCentre(tester, feed: [note('n1', title: 'Driver arrived')]);

      final button = tester.widget<HopButton>(
        find.widgetWithText(HopButton, 'Mark all as read'),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason:
            'Read-state is purely LOCAL. Marking a session event read costs '
            'nothing and lies about nothing — so it stays enabled.',
      );

      await tester.tap(find.widgetWithText(HopButton, 'Mark all as read'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.text('Unread'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.text('Driver arrived'),
        findsNothing,
        reason: 'Marked read → it leaves the Unread filter.',
      );
    });
  });

  group('NOTIF-02: unreadNotificationCountProvider is a REAL count', () {
    test('an empty feed counts 0 — never a hardcoded badge', () {
      final container = ProviderContainer(
        overrides: [
          notificationFeedProvider.overrideWith(
            () => NotificationFeed.seeded(const []),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(unreadNotificationCountProvider),
        0,
        reason:
            'Wave 0 deleted a hardcoded `notificationCount: 2` that shipped a '
            'permanent fake unread badge on EVERY screen. The badge may only '
            'ever show a real count.',
      );
    });

    test('counts only the unread events', () {
      final container = ProviderContainer(
        overrides: [
          notificationFeedProvider.overrideWith(
            () => NotificationFeed.seeded([
              note('n1', title: 'a'),
              note('n2', title: 'b', read: true),
              note('n3', title: 'c'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(unreadNotificationCountProvider), 2);
    });
  });
}
