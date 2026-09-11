import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/call_controller.dart';

/// The in-call screen: who you're talking to, how long for, and the three
/// controls that matter — mute, speaker, hang up. Shown by [CallOverlay]
/// whenever a call exists; it is not a route.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Redraw the call timer once a second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _status(CallState s) => switch (s.phase) {
    CallPhase.placing => 'Calling…',
    CallPhase.ringing => 'Ringing…',
    CallPhase.incoming => 'Incoming call',
    CallPhase.connecting => 'Connecting…',
    CallPhase.reconnecting => 'Reconnecting…',
    CallPhase.connected => _elapsed(s.connectedAt),
    CallPhase.ended => s.endReason ?? 'Call ended',
    CallPhase.idle => '',
  };

  static String _elapsed(DateTime? from) {
    if (from == null) return '00:00';
    final d = DateTime.now().difference(from);
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(callControllerProvider);
    final calls = ref.read(callControllerProvider.notifier);

    final scheme = Theme.of(context).colorScheme;
    final name = s.peerName.isNotEmpty
        ? s.peerName
        : (s.peerRole == 'rider' ? 'Your rider' : 'Your driver');

    return Scaffold(
      backgroundColor: const Color(0xFF14172B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 52,
                backgroundColor: scheme.primary.withValues(alpha: 0.25),
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 40,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 26,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.peerRole == 'rider' ? 'Rider' : 'Driver',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _status(s),
                style: TextStyle(
                  fontSize: 18,
                  color: s.phase == CallPhase.reconnecting
                      ? Colors.amber
                      : Colors.white70,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundButton(
                    icon: s.muted ? Icons.mic_off : Icons.mic,
                    label: s.muted ? 'Unmute' : 'Mute',
                    active: s.muted,
                    onTap: s.phase == CallPhase.connected
                        ? calls.toggleMute
                        : null,
                  ),
                  _RoundButton(
                    icon: Icons.call_end,
                    label: 'End',
                    background: const Color(0xFFD93A3A),
                    onTap: s.isActive ? calls.hangUp : null,
                  ),
                  _RoundButton(
                    icon: s.speaker ? Icons.volume_up : Icons.volume_down,
                    label: 'Speaker',
                    active: s.speaker,
                    onTap: s.isActive ? calls.toggleSpeaker : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? background;

  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final bg =
        background ??
        (active ? Colors.white : Colors.white.withValues(alpha: 0.14));
    final fg = background != null
        ? Colors.white
        : (active ? const Color(0xFF14172B) : Colors.white);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Icon(icon, color: fg, size: 30),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
