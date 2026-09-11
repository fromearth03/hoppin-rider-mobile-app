import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/call_controller.dart';
import 'call_screen.dart';

/// Shows the call screen over the whole app for as long as a call exists.
///
/// State, not navigation. A route pushed for the call can be wiped by any
/// `context.go` — answering from the ring screen brings the app forward, the
/// home screen "resumes the active ride" with a go, and the call screen was
/// gone: the rider sat on the ride page with a live call and no way to hang
/// up. Sitting above the router, this cannot be navigated away from.
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCall = ref.watch(
      callControllerProvider.select((s) => s.phase != CallPhase.idle),
    );
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: inCall ? const CallScreen() : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
