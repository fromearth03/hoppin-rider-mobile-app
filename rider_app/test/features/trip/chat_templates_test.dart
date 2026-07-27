// COMMS-01 — the 3 verbatim Figma template chips (MISSING-FE, zero backend
// work: `sendMessage` already takes a free-text body, so a chip is literally
// `_send(templateText)`).
//
// The strings are VERBATIM from Figma `Active trip (chat).jpg`. A paraphrase
// is a spec break, so they are asserted character-for-character — both on the
// chip label and on the body that reaches the BOUND endpoint.
//
// Bounded pumps ONLY — the chat poll never settles.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/chat_screen.dart';
import 'package:hoppin_rider/features/trip/widgets/chat_templates.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

void main() {
  testWidgets('exactly THREE template chips render, with the verbatim Figma '
      'strings', (tester) async {
    await _pumpChat(tester, _RecordingRidesRepo());

    expect(find.byType(ChatTemplates), findsOneWidget,
        reason: 'the template row must be mounted on the real chat screen — a '
            'widget that exists but is never constructed is dead code');

    expect(ChatTemplates.templates, hasLength(3),
        reason: 'the Figma chat frame carries exactly three chips');
    expect(
      ChatTemplates.templates,
      const ['Where are you?', "I'm waiting", 'Running late'],
      reason: 'the chip copy is VERBATIM from Figma — no rewording, no '
          'reordering',
    );

    for (final t in ChatTemplates.templates) {
      expect(find.text(t), findsOneWidget,
          reason: 'the chip "$t" must render its exact Figma label');
    }

    await _unmount(tester);
  });

  testWidgets('tapping "Where are you?" sends that EXACT body through the '
      'BOUND sendMessage', (tester) async {
    final repo = _RecordingRidesRepo();
    await _pumpChat(tester, repo);

    await tester.tap(find.text('Where are you?'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.sent, hasLength(1),
        reason: 'a chip tap goes through the SAME send path as the composer');
    expect(repo.sent.single.body, 'Where are you?',
        reason: 'the template body must arrive verbatim — no prefix, no '
            'suffix, no paraphrase');
    expect(repo.sent.single.rideId, 'ride-1',
        reason: 'the template send is scoped to the open ride');

    await _unmount(tester);
  });

  testWidgets('tapping "I\'m waiting" sends that EXACT body', (tester) async {
    final repo = _RecordingRidesRepo();
    await _pumpChat(tester, repo);

    await tester.tap(find.text("I'm waiting"));
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.sent.single.body, "I'm waiting",
        reason: 'the apostrophe is part of the Figma copy — it must survive');

    await _unmount(tester);
  });

  testWidgets('tapping "Running late" sends that EXACT body', (tester) async {
    final repo = _RecordingRidesRepo();
    await _pumpChat(tester, repo);

    await tester.tap(find.text('Running late'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.sent.single.body, 'Running late',
        reason: 'the third chip sends its verbatim body');

    await _unmount(tester);
  });

  testWidgets('a sent template lands in the thread — the chip is a real send, '
      'not a composer prefill', (tester) async {
    final repo = _RecordingRidesRepo();
    await _pumpChat(tester, repo);

    await tester.tap(find.text('Running late'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 3)); // the poll beat
    await tester.pump(const Duration(milliseconds: 50));

    // The chip label AND the sent bubble both carry the string now.
    expect(find.text('Running late'), findsNWidgets(2),
        reason: 'the chip fires an immediate send (the message appears in the '
            'thread); it does not merely prefill the composer');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'a chip send never leaves text sitting in the composer',
    );

    await _unmount(tester);
  });

  testWidgets('dark theme: the template row pumps clean', (tester) async {
    await _pumpChat(tester, _RecordingRidesRepo(), theme: _dark);

    expect(find.byType(ChatTemplates), findsOneWidget,
        reason: 'the chips render identically in dark mode');
    expect(tester.takeException(), isNull,
        reason: 'the dark theme must pump without exceptions');

    await _unmount(tester);
  });
}

// ── Harness ────────────────────────────────────────────────────────────────

final _light = HoppinTheme.riderLight();
final _dark = HoppinTheme.riderDark();

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

class _StubAuth implements AuthService {
  @override
  String? get userId => 'rider-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
