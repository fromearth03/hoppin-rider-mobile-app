@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/chat/data/chat_repository.dart';
import 'package:hoppin_rider/features/chat/presentation/chat_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockChat extends Mock implements ChatRepository {}

/// Renders the chat screen against `docs/figma/extracted/Conversation.png`.
/// See `auth_render_test.dart` for why these are renders, not assertions.
void main() {
  testWidgets('chat light', (tester) async {
    final repo = _MockChat();
    final now = DateTime(2026, 8, 31, 12);

    when(() => repo.messages(any(), since: any(named: 'since')))
        .thenAnswer((_) async => Ok([
              RideMessage(
                id: '1',
                body: "Lorem Ipsum has been the industry's standard dummy",
                senderRole: 'driver',
                createdAt: now,
                status: null,
                replyToId: null,
                replyToPreview: null,
              ),
              RideMessage(
                id: '2',
                body: "Lorem Ipsum has been the industry's standard dummy",
                senderRole: 'rider',
                createdAt: now.add(const Duration(minutes: 1)),
                status: 'read',
                replyToId: null,
                replyToPreview: null,
              ),
            ]));

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const ChatScreen(rideId: 'r1', driverName: 'George'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/chat_light.png'),
    );
  });
}
