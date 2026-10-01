// Renders the in-call screen (WhatsApp-style) for visual review:
// ringing (outgoing to Hoppin Support), connected with a driver, and ended.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/calls/application/call_controller.dart';
import 'package:hoppin_rider/features/calls/presentation/call_screen.dart';

class _FixedCall extends CallController {
  _FixedCall(this.fixed);
  final CallState fixed;
  @override
  CallState build() => fixed;
}

void main() {
  Future<void> shoot(WidgetTester tester, String name, CallState state) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [callControllerProvider.overrideWith(() => _FixedCall(state))],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const CallScreen(),
      ),
    ));
    // The ringing rings animate forever; advance a fixed amount instead of settling.
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('call screen: ringing support', (t) => shoot(t, 'call_ringing_support',
      const CallState(phase: CallPhase.ringing, peerName: 'Hoppin Support', peerRole: 'support')));
  testWidgets('call screen: support queue', (t) => shoot(t, 'call_support_queue',
      const CallState(phase: CallPhase.ringing, peerName: 'Hoppin Support', peerRole: 'support', queuePosition: 3)));
  testWidgets('call screen: incoming from support', (t) => shoot(t, 'call_incoming_support',
      const CallState(phase: CallPhase.incoming, callId: 'c1', peerName: 'Hoppin Support', peerRole: 'support')));
  testWidgets('call screen: connected driver', (t) => shoot(t, 'call_connected_driver',
      CallState(phase: CallPhase.connected, peerName: 'Ahmed', peerRole: 'driver',
          connectedAt: DateTime.now().subtract(const Duration(seconds: 83)))));
  testWidgets('call screen: ended', (t) => shoot(t, 'call_ended',
      const CallState(phase: CallPhase.ended, peerName: 'Hoppin Support', peerRole: 'support',
          endReason: 'No one from support was free. We will call you back as soon as we can.')));
}
