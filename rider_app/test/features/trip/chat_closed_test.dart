// COMMS-01 — the `409 CHAT_CLOSED` contract, asserted for the first time.
//
// `POST /rides/:id/messages` returns `409 CHAT_CLOSED` once the ride ends
// (docs/04). Chat shipped funnelling that into `friendlyErrorMessage(e)` → a
// generic snackbar over a LIVE composer, so a permanently-closed thread looked
// like a flaky network and the rider kept retyping into a channel that would
// never accept them. Restricted comms is a Scope-Lock non-negotiable.
//
// The contract these tests pin:
//   * 409 CHAT_CLOSED → a TERMINAL `ChatClosedState`. The composer AND the
//     template chips are REMOVED (findsNothing) — not disabled under a toast.
//   * The thread stays READABLE.
//   * The branch is on the exception's `code`, NOT on a message string.
//   * Every OTHER exception still surfaces as today's transient snackbar — we
//     branch, we do not swallow.
//
// Bounded pumps ONLY — the chat poll never settles.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/chat_screen.dart';
import 'package:hoppin_rider/features/trip/widgets/chat_closed_state.dart';
import 'package:hoppin_rider/features/trip/widgets/chat_templates.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// The real ride-service error shape: `{ error, code }` at a 4xx status.
const _chatClosed = ApiException(
  statusCode: 409,
  message: 'Chat is closed for this ride.',
  code: 'CHAT_CLOSED',
);

/// A DIFFERENT 409 — same status, different code. Proves we branch on `code`,
/// not on the status and not on the human-readable message.
const _otherConflict = ApiException(
  statusCode: 409,
  message: 'You already have an active trip.',
  code: 'ACTIVE_TRIP_EXISTS',
);

void main() {
  testWidgets('409 CHAT_CLOSED is TERMINAL: the composer is REMOVED, not '
      'disabled under a toast', (tester) async {
    final repo = _RecordingRidesRepo(
      thread: [_msg('m1', 'driver-1', 'Thanks, see you next time')],
      sendThrows: _chatClosed,
    );
    await _pumpChat(tester, repo);

    expect(find.byType(TextField), findsOneWidget,
        reason: 'precondition: the composer is live before the 409');

    await tester.enterText(find.byType(TextField), 'Are you still there?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ChatClosedState), findsOneWidget,
        reason: 'a 409 CHAT_CLOSED is a PERMANENT state — the rider must be '
            'told the thread is over, not shown a transient error');
    expect(find.byType(TextField), findsNothing,
        reason: 'THE contract: the composer is REMOVED. A live composer under '
            'a "chat closed" toast is the exact defect this lane exists to '
            'delete — the rider keeps typing into a channel that rejects them');

    await _unmount(tester);
  });

  testWidgets('409 CHAT_CLOSED removes the template chips too — every send '
      'affordance goes', (tester) async {
    final repo = _RecordingRidesRepo(sendThrows: _chatClosed);
    await _pumpChat(tester, repo);

    expect(find.byType(ChatTemplates), findsOneWidget,
        reason: 'precondition: the chips are live before the 409');

    await tester.tap(find.text('Where are you?'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ChatTemplates), findsNothing,
        reason: 'a chip is a send affordance — leaving it tappable on a closed '
            'thread is the same lie as leaving the composer live');
    expect(find.byType(ChatClosedState), findsOneWidget,
        reason: 'the terminal state replaces the whole send row');

    await _unmount(tester);
  });

  testWidgets('the thread stays READABLE after the 409 — closing the channel '
      'does not erase the conversation', (tester) async {
    final repo = _RecordingRidesRepo(
      thread: [
        _msg('m1', 'driver-1', 'Pulling up outside now'),
        _msg('m2', 'rider-1', 'Coming down'),
      ],
      sendThrows: _chatClosed,
    );
    await _pumpChat(tester, repo);

    await tester.enterText(find.byType(TextField), 'hello?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Pulling up outside now'), findsOneWidget,
        reason: 'the history remains readable — the rider can still review '
            'what was agreed');
    expect(find.text('Coming down'), findsOneWidget,
        reason: 'both sides of the thread survive the terminal state');

    await _unmount(tester);
  });

  testWidgets('the terminal state explains itself — a designed, non-blank '
      'surface, not a silent removal', (tester) async {
    final repo = _RecordingRidesRepo(sendThrows: _chatClosed);
    await _pumpChat(tester, repo);

    await tester.enterText(find.byType(TextField), 'hello?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    final panel = find.byType(ChatClosedState);
    final size = tester.getSize(panel);
    expect(size.width, greaterThan(0),
        reason: 'the terminal state must be a real, visible surface');
    expect(size.height, greaterThan(0),
        reason: 'the terminal state must have real height — never a collapsed '
            'box where the composer used to be');
    expect(find.text(ChatClosedState.headline), findsOneWidget,
        reason: 'the rider is told, in words, why they can no longer send');

    await _unmount(tester);
  });

  testWidgets('a NON-CHAT_CLOSED failure still surfaces as the transient '
      'snackbar — we branch on the code, we do not swallow', (tester) async {
    final repo = _RecordingRidesRepo(sendThrows: _otherConflict);
    await _pumpChat(tester, repo);

    await tester.enterText(find.byType(TextField), 'hello?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ChatClosedState), findsNothing,
        reason: 'the branch is on code == CHAT_CLOSED — a DIFFERENT 409 must '
            'NOT terminate the chat (branching on the status, or on the '
            'human-readable message, would fail here)');
    expect(find.byType(TextField), findsOneWidget,
        reason: 'a transient failure leaves the composer live — the rider can '
            'retry');
    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'a non-409-CHAT_CLOSED error keeps the existing transient '
            'snackbar behaviour');
    expect(find.text(_otherConflict.message), findsOneWidget,
        reason: 'the snackbar carries the server message');

    await _unmount(tester);
  });

  testWidgets('the 409 does NOT surface as a generic error snackbar — the '
      'permanent state is not disguised as a network hiccup', (tester) async {
    final repo = _RecordingRidesRepo(sendThrows: _chatClosed);
    await _pumpChat(tester, repo);

    await tester.enterText(find.byType(TextField), 'hello?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SnackBar), findsNothing,
        reason: 'the shipped defect was a generic snackbar over a live '
            'composer — a permanent close disguised as a flaky network');

    await _unmount(tester);
  });

  testWidgets('dark theme: the terminal state pumps clean', (tester) async {
    final repo = _RecordingRidesRepo(sendThrows: _chatClosed);
    await _pumpChat(tester, repo, theme: _dark);

    await tester.enterText(find.byType(TextField), 'hello?');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ChatClosedState), findsOneWidget,
        reason: 'the terminal state renders identically in dark mode');
    expect(tester.takeException(), isNull,
        reason: 'the dark theme must pump without exceptions');

    await _unmount(tester);
  });
}

// ── Harness ────────────────────────────────────────────────────────────────

final _light = HoppinTheme.riderLight();
final _dark = HoppinTheme.riderDark();

RideMessage _msg(String id, String senderId, String body) =>
    RideMessage(id: id, senderId: senderId, body: body);

Future<void> _pumpChat(
  WidgetTester tester,
  RidesRepository repo, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      ridesRepositoryProvider.overrideWithValue(repo),
      authServiceProvider.overrideWithValue(_StubAuth()),
    ],
    child: MaterialApp(
      theme: theme ?? _light,
      home: const ChatScreen(rideId: 'ride-1'),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

/// See `chat_send_test.dart` — the poll's in-flight `Future.delayed(3s)`
/// outlives the dispose, so pump past the beat after tearing the tree down.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

class _RecordingRidesRepo implements RidesRepository {
  _RecordingRidesRepo({List<RideMessage> thread = const [], this.sendThrows})
      : thread = List.of(thread);

  List<RideMessage> thread;

  /// If set, every `sendMessage` throws this instead of succeeding.
  final Object? sendThrows;

  final List<({String rideId, String body})> sent = [];

  @override
  Future<List<RideMessage>> messages(String rideId, {DateTime? since}) async =>
      List.of(thread);

  @override
  Future<RideMessage> sendMessage({
    required String rideId,
    required String body,
  }) async {
    sent.add((rideId: rideId, body: body));
    if (sendThrows != null) throw sendThrows!;
    final m =
        RideMessage(id: 'sent-${sent.length}', senderId: 'rider-1', body: body);
    thread = [...thread, m];
    return m;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAuth implements AuthService {
  @override
  String? get userId => 'rider-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
