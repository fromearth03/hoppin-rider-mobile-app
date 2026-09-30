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

    final name = s.peerName.isNotEmpty
        ? s.peerName
        : switch (s.peerRole) {
            'support' => CallController.supportName,
            'rider' => 'Your rider',
            _ => 'Your driver',
          };
    final ringing =
        s.phase == CallPhase.placing ||
        s.phase == CallPhase.ringing ||
        s.phase == CallPhase.incoming;
    final statusColor = switch (s.phase) {
      CallPhase.reconnecting => Colors.amber,
      CallPhase.ended => const Color(0xFFFF8A9A),
      CallPhase.connected => const Color(0xFF25D366),
      _ => Colors.white70,
    };

    // Styled after a WhatsApp voice call, so it reads as a phone call at a
    // glance: dark teal gradient, the caller large in the middle with rings
    // while it rings, and the controls in a bar at the bottom.
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F2C34), Color(0xFF0B141A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Hoppin voice call',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                switch (s.peerRole) {
                  'support' => 'Hoppin safety and support team',
                  'rider' => 'Rider',
                  _ => 'Driver',
                },
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _status(s),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: statusColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              _PulsingAvatar(
                initial: name.characters.first.toUpperCase(),
                pulsing: ringing,
              ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundButton(
                      icon: s.speaker ? Icons.volume_up : Icons.volume_down,
                      label: 'Speaker',
                      active: s.speaker,
                      onTap: s.isActive ? calls.toggleSpeaker : null,
                    ),
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
                      background: const Color(0xFFEA0038),
                      onTap: s.isActive ? calls.hangUp : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The other person's initial in a large circle, with WhatsApp-style rings
/// expanding outward while the call is ringing.
class _PulsingAvatar extends StatefulWidget {
  final String initial;
  final bool pulsing;
  const _PulsingAvatar({required this.initial, required this.pulsing});

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat();
  }

  @override
  void didUpdateWidget(_PulsingAvatar old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) _c.repeat();
    if (!widget.pulsing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 128.0;
    return SizedBox(
      width: size + 90,
      height: size + 90,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          Widget ring(double phase) {
            final t = (_c.value + phase) % 1.0;
            return Opacity(
              opacity: widget.pulsing ? (1 - t) * 0.5 : 0,
              child: Container(
                width: size + 90 * t,
                height: size + 90 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF25D366), width: 2),
                ),
              ),
            );
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              ring(0),
              ring(0.5),
              Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF31048A),
                ),
                child: Text(
                  widget.initial,
                  style: const TextStyle(
                    fontSize: 52,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
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
        (active ? Colors.white : Colors.white.withValues(alpha: 0.12));
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
