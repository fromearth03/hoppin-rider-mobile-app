// COMMS-01 — the BOUND baseline that had never been asserted.
//
// `RidesRepository.messages()` / `sendMessage()` are genuinely bound to
// `GET|POST /rides/:id/messages`, the screen polls every 3s, and the route is
// live — yet chat shipped with ZERO tests (Phase-11 gate-audit finding). This
// file pins the working path: the thread renders, the composer sends the exact
// body typed, the composer clears, and the 3s poll refreshes the thread.
//
// Bounded pumps ONLY — the chat poll is an infinite `while (true)` stream and
// NEVER settles, so `pumpAndSettle` would hang forever.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/chat_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

void main() {
  testWidgets('the scripted thread renders — chat is BOUND and the bubbles '
      'are the repo\'s real messages', (tester) async {
    final repo = _RecordingRidesRepo(thread: [_msg('m1', 'driver-1', 'On my way')]);
    await _pumpChat(tester, repo);

    expect(find.text('On my way'), findsOneWidget,
        reason: 'the thread returned by messages() must render as a bubble — '
            'this is the BOUND path and it must stay bound');

    await _unmount(tester);
  });

  testWidgets('typing a body and tapping send calls sendMessage with that '
      'EXACT body, and the composer clears', (tester) async {
    final repo = _RecordingRidesRepo();
    await _pumpChat(tester, repo);

    await tester.enterText(find.byType(TextField), 'I am by the blue door');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.sent, hasLength(1),
        reason: 'tapping send must reach the BOUND sendMessage exactly once');
    expect(repo.sent.single.body, 'I am by the blue door',
        reason: 'the body sent must be verbatim what the rider typed — no '
            'prefix, no paraphrase');
    expect(repo.sent.single.rideId, 'ride-1',
        reason: 'the send must be scoped to the ride the screen was opened on');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'a successful send clears the composer',
    );

    await _unmount(tester);
  });

  testWidgets('the 3s poll refreshes the thread — a message that arrives '
      'after mount appears without any user action', (tester) async {
    final repo = _RecordingRidesRepo(thread: [_msg('m1', 'driver-1', 'On my way')]);
    await _pumpChat(tester, repo);

    expect(find.text('Two minutes away'), findsNothing,
        reason: 'precondition: the later message has not been polled yet');

    // The driver posts while the rider watches.
    repo.thread = [
      _msg('m1', 'driver-1', 'On my way'),
      _msg('m2', 'driver-1', 'Two minutes away'),
    ];

    // Bounded pumps across the 3s poll beat — never pumpAndSettle: the poll
    // loop is infinite by design.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Two minutes away'), findsOneWidget,
        reason: 'the 3s poll is the transport floor for chat — a new message '
            'must appear with no user action');

    await _unmount(tester);
  });

  testWidgets('an empty composer never sends — whitespace is not a message',
      (tester) async {
    final repo = _RecordingRidesRepo();
    await _pumpChat(tester, repo);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.sent, isEmpty,
        reason: 'a whitespace-only body must never reach the endpoint');

    await _unmount(tester);
  });

  testWidgets('dark theme: the chat surface pumps clean', (tester) async {
    final repo = _RecordingRidesRepo(thread: [_msg('m1', 'driver-1', 'Hello')]);
    await _pumpChat(tester, repo, theme: _dark);

    expect(find.text('Hello'), findsOneWidget,
        reason: 'the thread renders identically in dark mode');
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
  // The first poll tick lands; the thread paints.
  await tester.pump(const Duration(milliseconds: 50));
}

/// Unmounts so the infinite 3s poll dies with the provider scope before
/// teardown's pending-timer check. The poll's in-flight `Future.delayed(3s)`
/// outlives the dispose (the generator is suspended inside it), so the tree is
/// torn down and then pumped past the beat to let the cancelled generator
/// actually finish.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

/// Repo-level recording fake — the ONLY injection point (never a Dio or
/// MethodChannel stub). Records every `sendMessage`, serves a scripted thread,
/// and can be told to throw on send.
class _RecordingRidesRepo implements RidesRepository {
  _RecordingRidesRepo({List<RideMessage> thread = const []})
      : thread = List.of(thread);

  List<RideMessage> thread;

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
    final m =
        RideMessage(id: 'sent-${sent.length}', senderId: 'rider-1', body: body);
    thread = [...thread, m];
    return m;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal auth double — the chat screen reads only `userId` (to decide which
/// bubbles are "mine").
class _StubAuth implements AuthService {
  @override
  String? get userId => 'rider-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
