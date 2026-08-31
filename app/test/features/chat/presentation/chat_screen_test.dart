import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/chat/data/chat_repository.dart';
import 'package:hoppin_rider/features/chat/presentation/chat_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockChat extends Mock implements ChatRepository {}

RideMessage _message({
  required String id,
  required String role,
  DateTime? at,
  String body = 'Lorem Ipsum has been the industry\'s standard dummy text',
}) =>
    RideMessage(
      id: id,
      body: body,
      senderRole: role,
      createdAt: at ?? DateTime.now(),
      status: null,
      replyToId: null,
      replyToPreview: null,
    );

void main() {
  late _MockChat repo;

  setUp(() {
    repo = _MockChat();
    when(() => repo.messages(any(), since: any(named: 'since')))
        .thenAnswer((_) async => const Ok(<RideMessage>[]));
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ChatScreen(rideId: 'r1', driverName: 'George'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an empty ride id never hits the network', (tester) async {
    // Only a hand-typed URL produces this; the request it would send is
    // /rides//messages — malformed. The screen must not fire it or poll it.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ChatScreen(rideId: '', driverName: 'Driver'),
        ),
      ),
    );
    await tester.pump();

    verifyZeroInteractions(repo);
    expect(find.byType(Scaffold), findsOneWidget);
  });

  group('design fidelity', () {
    testWidgets('a bubble hugs its text rather than filling the row',
        (tester) async {
      // Full-width bubbles were the original build. A bubble with no side to
      // it reads as a log, not a conversation.
      when(() => repo.messages(any(), since: any(named: 'since')))
          .thenAnswer((_) async => Ok([_message(id: '1', role: 'driver')]));

      await pump(tester);
      await tester.pump();

      final width = tester.getSize(find.byType(ListView)).width;
      final bubble = tester.getSize(
        find.ancestor(
          of: find.textContaining('Lorem Ipsum'),
          matching: find.byType(Container),
        ).first,
      );

      expect(bubble.width, lessThan(width * 0.80));
    });

    testWidgets('the driver gets an avatar and the rider does not',
        (tester) async {
      when(() => repo.messages(any(), since: any(named: 'since')))
          .thenAnswer((_) async => Ok([
                _message(id: '1', role: 'driver'),
                _message(id: '2', role: 'rider'),
              ]));

      await pump(tester);
      await tester.pump();

      // One avatar inside the list, for the driver's message only — the design
      // puts none beside the rider's own bubbles. Scoped to the ListView
      // because the AppBar carries the same initial.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('G'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a day separator heads the conversation', (tester) async {
      when(() => repo.messages(any(), since: any(named: 'since')))
          .thenAnswer((_) async => Ok([_message(id: '1', role: 'driver')]));

      await pump(tester);
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('messages from different days get their own separators',
        (tester) async {
      // The design draws a fixed "Today". A ride's chat can straddle
      // midnight, so the label has to be computed.
      final now = DateTime.now();
      when(() => repo.messages(any(), since: any(named: 'since')))
          .thenAnswer((_) async => Ok([
                _message(
                    id: '1',
                    role: 'driver',
                    at: now.subtract(const Duration(days: 1))),
                _message(id: '2', role: 'rider', at: now),
              ]));

      await pump(tester);
      await tester.pump();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('one separator only for messages on the same day',
        (tester) async {
      final now = DateTime.now();
      when(() => repo.messages(any(), since: any(named: 'since')))
          .thenAnswer((_) async => Ok([
                _message(id: '1', role: 'driver', at: now),
                _message(id: '2', role: 'rider', at: now),
              ]));

      await pump(tester);
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
    });
  });
}
