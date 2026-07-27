import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// Masked-voice-call unavailable-state (seam **#45**, COMMS-02).
///
/// The Figma call frames render a live status line — "Calling….", "Ringing…",
/// "Connected" over a running `00:01`. **Every one of those is a claim the app
/// cannot make.** There is no `POST /rides/:id/call` proxy and no masked-number
/// field on any ride payload (gap #45), so no call is placed, nothing rings,
/// and nothing connects. Rendering the Figma status line verbatim would be the
/// same class of lie Wave 0 deleted (a phone icon that opened chat) — just
/// with better typography.
///
/// So this rung takes the status line's place in the layout and says the true
/// thing instead: masked calling is not live yet. And because a disclosure that
/// leaves the rider stranded is only half-honest, it hands over the comms
/// surface that **does** work — chat is BOUND (`POST /rides/:id/messages`) —
/// as a primary action rather than a consolation footnote.
///
/// The whole point of masked calling is that the rider and driver never see
/// each other's number. With no proxy to mask through, a "call" button could
/// only ever dial a **personal** number. Shipping this seam inert is not a
/// compromise; it is the requirement.
///
/// This is the fallback widget `kSeamRegistry` names for #45 (Lane E registers
/// it). Group C's reachability check requires it be CONSTRUCTED on the real
/// seam branch of a real view — that mount site is `call_screen.dart`.
class CallUnavailableState extends StatelessWidget {
  /// Creates the #45 masked-voice degrade rung.
  const CallUnavailableState({required this.onOpenChat, super.key});

  /// Opens the BOUND chat thread — the working alternative this rung offers.
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    return HopEmptyState(
      headline: 'Calling is not live yet',
      supporting:
          'Private, number-masked calling is on the way. Until it lands we '
          'will not connect you through an unmasked line — your number and '
          "your driver's stay private. Message them instead; it reaches them "
          'straight away.',
      actionLabel: 'Open chat',
      onAction: onOpenChat,
    );
  }
}
