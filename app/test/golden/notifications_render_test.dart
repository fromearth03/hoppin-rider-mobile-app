@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/notifications/data/notifications_source.dart';
import 'package:hoppin_rider/features/notifications/data/promotions_source.dart';
import 'package:hoppin_rider/features/notifications/domain/notification_item.dart';
import 'package:hoppin_rider/features/notifications/domain/promotion_item.dart';
import 'package:hoppin_rider/features/notifications/presentation/notifications_screen.dart';
import 'package:hoppin_rider/features/notifications/presentation/promotional_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockNotificationsSource extends Mock implements NotificationsSource {}

class _MockPromotionsSource extends Mock implements PromotionsSource {}

/// Renders Notifications and Promotional so they can be put side by side
/// with `docs/figma/extracted/`. See `auth_render_test.dart` for why these
/// are renders, not assertions.
void main() {
  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.light,
    // The Figma frames are 430x932. A 320-wide render is not a Figma frame —
    // it exists to surface the class of bug a fixed-height Row with a
    // squeezed flexible child produces, which only shows up under narrower
    // constraints than the design ships at.
    double width = 430,
  }) async {
    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: screen,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  final notifications = [
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
      createdAt: DateTime(2026, 8, 31, 8, 45),
      isRead: false,
      dayLabel: 'Today',
    ),
    NotificationItem(
      id: '3',
      title: 'Rate your driver',
      body: 'How your trip went? Give driver a rating.',
      createdAt: DateTime(2026, 8, 31, 8, 30),
      isRead: true,
      dayLabel: 'Today',
    ),
    NotificationItem(
      id: '4',
      title: 'Issue Resolved',
      body: '-£ 12.36 refunded in your wallet.',
      createdAt: DateTime(2026, 8, 31, 8),
      isRead: true,
      dayLabel: 'Today',
    ),
  ];

  final promotions = [
    PromotionItem(
      id: '1',
      title: 'First Ride Discount',
      description: "Get 10% off on your first ride with Hoppin'",
      status: PromotionStatus.active,
      validUntil: DateTime(2026, 9, 2),
    ),
    PromotionItem(
      id: '2',
      title: 'First Ride Discount',
      description: "Get 10% off on your first ride with Hoppin'",
      status: PromotionStatus.availed,
      validUntil: DateTime(2026, 9, 2),
    ),
    PromotionItem(
      id: '3',
      title: 'First Ride Discount',
      description: "Get 10% off on your first ride with Hoppin'",
      status: PromotionStatus.expired,
      validUntil: DateTime(2026, 9, 2),
    ),
  ];

  testWidgets('notifications light', (t) async {
    final source = _MockNotificationsSource();
    when(() => source.list()).thenAnswer((_) async => notifications);
    when(() => source.markRead(any())).thenAnswer((_) async {});
    when(() => source.markAllRead()).thenAnswer((_) async {});

    await shoot(
      t,
      ProviderScope(
        overrides: [notificationsSourceProvider.overrideWithValue(source)],
        child: const NotificationsScreen(),
      ),
      'notifications_light',
    );
  });

  testWidgets('notifications narrow', (t) async {
    final source = _MockNotificationsSource();
    when(() => source.list()).thenAnswer((_) async => notifications);
    when(() => source.markRead(any())).thenAnswer((_) async {});
    when(() => source.markAllRead()).thenAnswer((_) async {});

    await shoot(
      t,
      ProviderScope(
        overrides: [notificationsSourceProvider.overrideWithValue(source)],
        child: const NotificationsScreen(),
      ),
      'notifications_narrow',
      width: 320,
    );
  });

  testWidgets('promotional light', (t) async {
    final source = _MockPromotionsSource();
    when(() => source.list()).thenAnswer((_) async => promotions);

    await shoot(
      t,
      ProviderScope(
        overrides: [promotionsSourceProvider.overrideWithValue(source)],
        child: const PromotionalScreen(),
      ),
      'promotional_light',
    );
  });

  testWidgets('promotional narrow', (t) async {
    final source = _MockPromotionsSource();
    when(() => source.list()).thenAnswer((_) async => promotions);

    await shoot(
      t,
      ProviderScope(
        overrides: [promotionsSourceProvider.overrideWithValue(source)],
        child: const PromotionalScreen(),
      ),
      'promotional_narrow',
      width: 320,
    );
  });
}
