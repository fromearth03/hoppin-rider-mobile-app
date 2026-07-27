import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'driver_info_provider.dart';
import 'widgets/call_unavailable_state.dart';
import 'widgets/seam_unavailable_states.dart';

/// Which of the three Figma call frames the layout is composing.
///
/// These are **LAYOUTS, not call states.** No call exists to be in a state.
/// The Figma ships three frames — `(calling)`, `(ringing)`, `(connected)` —
/// and SCOPE-TRACE row 15 only ever mentions two; the third adds the timer and
/// the mute/speaker controls. All three are built so that when the masked-call
/// proxy (#45) lands, the body swaps in behind an unchanged view.
enum CallFramePhase {
  /// Figma `(calling)` — the outbound frame.
  calling,

  /// Figma `(ringing)` — the same layout, a different status line.
  ringing,

  /// Figma `(connected)` — adds the `00:01` readout and mute/speaker.
  connected,
}

/// COMMS-02 — the masked in-trip voice surface, INERT on disclosed seam #45.
///
/// ## What this screen does not do
///
/// **It never dials.** Not through a plugin, not through a telephone URI, not
/// through anything. (The dial scheme is deliberately never spelled literally
/// anywhere in `lib/` — the phase gate greps for it, and a docstring
/// explaining the ban must not be what trips the gate.)
///
/// This is not caution; it is the requirement. There is no
/// `POST /rides/:id/call` proxy and no masked-number field on any ride payload
/// (gap #45), so the app has no masked number to reach. The only number it
/// could reach is the driver's **personal** one — which is the precise exposure
/// masked calling exists to prevent, and a Scope-Lock hard prohibition. A call
/// button that dialled a real driver would not be a partial implementation of
/// COMMS-02; it would be its inversion.
///
/// The property is asserted mechanically, not promised: `call_screen_test.dart`
/// injects a recording [UrlLauncher] over `urlLauncherProvider`, drives every
/// control on every frame, and requires `calls.isEmpty`.
///
/// ## What it does do
///
/// It renders the full designed surface — navy full-bleed, driver identity,
/// all three Figma frame layouts — with [CallUnavailableState] standing exactly
/// where the live status line would be, saying the true thing and handing the
/// rider the comms surface that actually works (chat is BOUND). The hangup and
/// the mute/speaker controls render at Figma fidelity and are **disabled**:
/// there is no call to hang up and no microphone to mute.
///
/// The `00:01` in the connected frame is **inert layout**. It never ticks. A
/// clock counting up would be a counterfeit call duration, and a test pins it
/// still across five seconds of pumped time.
///
/// Driver identity comes from the #5 seam ([driverInfoProvider]) and degrades
/// to [DriverUnavailableCard] on null — the same rung the trip screen uses. It
/// never fabricates a driver.
///
/// Lane E (11-05) routes this at `/trip/:id/call` and registers seam #45 with
/// [CallUnavailableState] as its `unavailableWidget`.
class CallScreen extends ConsumerStatefulWidget {
  /// Creates the inert call surface for [rideId].
  const CallScreen({required this.rideId, super.key});

  /// The ride whose driver is being (not) called.
  final String rideId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  /// The Figma frame currently composed. Selected by the rider, NEVER driven
  /// by a call lifecycle — there is no call lifecycle.
  CallFramePhase _frame = CallFramePhase.calling;

  // PUSHED, not `go`-ne to: the rider opens the chat FROM the call surface and
  // is expected to come back to it. `go` would replace this route, so the
  // chat's back button would fall through to a fallback instead of returning
  // here.
  void _openChat() => unawaited(context.push('/trip/${widget.rideId}/chat'));

  /// 🔴 THIS WAS A NO-OP, and it was the ONLY exit on the screen.
  ///
  /// The close control called `context.pop()` flat. But this surface is reached
  /// with `context.go` (see trip_router), which REPLACES rather than pushes — so
  /// there was nothing on the stack to pop, `pop()` did nothing, and the rider
  /// was stranded on a call frame that never dials. The end-call button is no
  /// escape either: it is DELIBERATELY disabled on seam #45 (there is no call to
  /// hang up), so it cannot be, and must not become, the way out.
  ///
  /// So the exit is made unconditional: pop when there genuinely is a stack,
  /// otherwise return to the trip this call belongs to.
  void _close() =>
      context.canPop() ? context.pop() : context.go('/trip/${widget.rideId}');

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final driver = ref.watch(driverInfoProvider(widget.rideId)).value;

    return Scaffold(
      // The Figma call frame is navy full-bleed in both themes — it is a
      // chrome-less surface, not a themed page.
      backgroundColor: hoppin.colors.accent,
      body: Column(
        children: [
          // The exit. It is the design-system bar, not a hand-rolled icon,
          // because the rule for every off-shell screen is the same and this
          // screen is no exception (shell_chrome_test enforces it): outside the
          // shell there is no bottom nav and no shell header, so the screen owes
          // its own bar with an UNCONDITIONAL back intent, or the rider is
          // stranded. The end-call button is not an exit — it is DELIBERATELY
          // disabled on seam #45 (there is no call to hang up), so it cannot be,
          // and must not become, the way out.
          //
          // [_NavyChrome] re-tones the bar to the navy full-bleed frame so the
          // Figma surface survives: same component, same behaviour, the frame's
          // own palette. It replaces the hand-rolled close X that used to sit
          // here — one screen, one exit; two back controls side by side is just
          // noise, and the hand-rolled one was the broken one.
          _NavyChrome(
            child: HopTopBar(key: const Key('call.close'), onBack: _close),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(hoppin.spacing.gutter),
                child: Column(
                  children: [
                    SizedBox(height: hoppin.spacing.lg),

                    // 1 — driver identity, degrading on seam #5 rather than
                    // inventing anyone.
                    if (driver != null)
                      _CallIdentity(info: driver)
                    else
                      const DriverUnavailableCard(),

                    SizedBox(height: hoppin.spacing.xl),

                    // 2 — the frame selector. This is what makes all three Figma
                    // layouts reachable without a call lifecycle to drive them.
                    _FrameSelector(
                      selected: _frame,
                      onSelect: (f) => setState(() => _frame = f),
                    ),
                    SizedBox(height: hoppin.spacing.lg),

                    // 3 — the frame body. The Figma status line ("Calling….")
                    // lives here; the #45 rung replaces it, because none of
                    // those words is true.
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          key: Key('call.frame.body.${_frame.name}'),
                          children: [
                            if (_frame == CallFramePhase.connected)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: hoppin.spacing.md,
                                ),
                                // INERT LAYOUT. No Timer, no ticking, no fake
                                // call duration — the Figma numeral, still.
                                child: Text(
                                  '00:00',
                                  key: const Key('call.connected.timer'),
                                  style: hoppin.type.numeralCaption.copyWith(
                                    color: hoppin.colors.onAccent.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            // THE MOUNT SITE for seam #45 (Group C).
                            _OnNavy(
                              child: CallUnavailableState(
                                onOpenChat: _openChat,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 4 — the Figma control row: speaker / hangup / mute.
                    // Present at fidelity, DISABLED on the seam. There is no
                    // call to hang up.
                    _CallControls(frame: _frame),
                    SizedBox(height: hoppin.spacing.md),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Re-tones the design-system chrome for the navy full-bleed call frame.
///
/// [HopTopBar] paints itself on `colors.card` with `colors.textHi` glyphs — the
/// right thing on a normal page, a white slab on this one. Rather than fork the
/// component (or hand-roll a second bar that would drift from it), the two
/// surface tokens it reads are swapped for the frame's own: the bar becomes navy
/// with light glyphs, and every other token — spacing, radii, type — is
/// untouched. Same component, same behaviour, the frame's palette.
class _NavyChrome extends StatelessWidget {
  const _NavyChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.hoppin.colors;
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where((e) => e is! HoppinColors),
          colors.copyWith(card: colors.accent, textHi: colors.onAccent),
        ],
      ),
      child: child,
    );
  }
}

/// Renders the rung's typography legibly on the navy full-bleed frame.
/// The rung itself is token-driven and theme-agnostic; this only re-tints the
/// inherited text colour for the dark surface it is standing on.
class _OnNavy extends StatelessWidget {
  const _OnNavy({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return DefaultTextStyle.merge(
      style: TextStyle(color: hoppin.colors.onAccent),
      child: child,
    );
  }
}

/// Avatar + name + `★ 4.9 (1,480 trips)` — the Figma identity block.
class _CallIdentity extends StatelessWidget {
  const _CallIdentity({required this.info});

  final RideDriverInfo info;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final onNavy = hoppin.colors.onAccent;
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onNavy.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            info.initials,
            style: hoppin.type.title.copyWith(color: onNavy),
          ),
        ),
        SizedBox(height: hoppin.spacing.md),
        Text(
          info.fullName,
          style: hoppin.type.title.copyWith(
            color: onNavy,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: hoppin.spacing.xs),
        // The rating line sits at the frame's SECONDARY emphasis, not on the
        // `warn` token it used to use. `warn` resolves to the brand red
        // (#E33236), which on this navy full-bleed frame measured 2.9:1 —
        // under AA — and, worse, painted a driver's rating in the app's error
        // colour. On navy the only legible foreground is the on-accent ink;
        // secondary emphasis is carried by ALPHA, the way the rest of this
        // frame does it (see the inert timer above).
        Text(
          '★ ${info.rating.toStringAsFixed(1)} (${info.tripsCount} trips)',
          style: hoppin.type.bodySmall.copyWith(
            color: onNavy.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// The three-frame selector. Exists because there is no call lifecycle to
/// drive the frames — and building only the two frames a lifecycle could reach
/// would leave the third Figma layout unbuilt when the backend lands.
class _FrameSelector extends StatelessWidget {
  const _FrameSelector({required this.selected, required this.onSelect});

  final CallFramePhase selected;
  final ValueChanged<CallFramePhase> onSelect;

  static const _labels = {
    CallFramePhase.calling: 'Calling',
    CallFramePhase.ringing: 'Ringing',
    CallFramePhase.connected: 'Connected',
  };

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final onNavy = hoppin.colors.onAccent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final frame in CallFramePhase.values) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hoppin.spacing.xs),
            child: Material(
              color: frame == selected
                  ? onNavy.withValues(alpha: 0.18)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(hoppin.radii.control),
                side: BorderSide(color: onNavy.withValues(alpha: 0.24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('call.frame.${frame.name}'),
                onTap: () => onSelect(frame),
                // 11pt type on 8pt padding is a ~35pt tall target — under the
                // 44pt floor every other control in the app clears.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: hoppin.spacing.md,
                      vertical: hoppin.spacing.sm,
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        _labels[frame]!,
                        style: hoppin.type.labelSmall.copyWith(color: onNavy),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Speaker / hangup / mute — the Figma connected-frame control row.
///
/// Every control is **disabled**. `onPressed: null` is not an oversight: there
/// is no call to hang up, no microphone in a call to mute, and no audio route
/// to switch. A live-looking control that silently does nothing is the exact
/// dead-end the no-holes rule forbids, so these render visibly inert.
class _CallControls extends StatelessWidget {
  const _CallControls({required this.frame});

  final CallFramePhase frame;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final connected = frame == CallFramePhase.connected;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (connected) ...[
          const _CircleControl(
            controlKey: Key('call.action.speaker'),
            icon: Icons.volume_up_outlined,
            tooltip: 'Speaker (unavailable — no call is connected)',
          ),
          SizedBox(width: hoppin.spacing.lg),
        ],
        const _CircleControl(
          controlKey: Key('call.action.hangup'),
          icon: Icons.call_end,
          tooltip: 'End call (unavailable — no call is connected)',
          destructive: true,
        ),
        if (connected) ...[
          SizedBox(width: hoppin.spacing.lg),
          const _CircleControl(
            controlKey: Key('call.action.mute'),
            icon: Icons.mic_none_outlined,
            tooltip: 'Mute (unavailable — no call is connected)',
          ),
        ],
      ],
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.controlKey,
    required this.icon,
    required this.tooltip,
    this.destructive = false,
  });

  final Key controlKey;
  final IconData icon;
  final String tooltip;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final onNavy = hoppin.colors.onAccent;
    // Disabled alpha: the control is visibly inert, matching HopButton's
    // disabled treatment rather than inventing a new one.
    final fill = destructive
        ? hoppin.colors.error.withValues(alpha: 0.45)
        : onNavy.withValues(alpha: 0.10);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: false,
        label: tooltip,
        child: Container(
          key: controlKey,
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Icon(icon, size: 26, color: onNavy.withValues(alpha: 0.45)),
        ),
      ),
    );
  }
}
