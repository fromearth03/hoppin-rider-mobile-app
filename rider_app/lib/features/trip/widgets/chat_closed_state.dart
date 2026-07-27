import 'package:flutter/material.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// COMMS-01 — the TERMINAL state for a chat the server has closed.
///
/// `POST /rides/:id/messages` answers `409 CHAT_CLOSED` once the ride ends
/// (docs/04). That is a **permanent** condition, not a transient one: the
/// thread will never accept another message. It shipped as a generic
/// `friendlyErrorMessage` snackbar over a still-live composer, so a
/// permanently-closed chat read as a flaky network and the rider kept
/// retyping into a channel that would keep rejecting them.
///
/// This panel is what stands **in place of** the composer and the
/// `ChatTemplates` chip row once that 409 lands — both are REMOVED from the
/// tree, not disabled beneath a toast. The thread above it stays readable: the
/// channel closes, the conversation does not disappear.
///
/// Restricted comms is a Scope-Lock non-negotiable; this is the honest end of
/// the window.
class ChatClosedState extends StatelessWidget {
  /// Creates the closed-chat terminal panel.
  const ChatClosedState({super.key});

  /// The headline the rider reads. Exposed so the contract test can assert the
  /// exact copy the terminal state promises to show.
  static const String headline = 'This chat is closed';

  /// The supporting line — says what happened and what is still possible.
  static const String supporting =
      'Your trip has ended, so messaging your driver is no longer available. '
      'You can still read this conversation.';

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return Container(
      width: double.infinity,
      color: colors.canvas,
      padding: EdgeInsets.symmetric(
        horizontal: hoppin.spacing.gutter,
        vertical: hoppin.spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: hoppin.type.titleSmall.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.xs),
          Text(
            supporting,
            textAlign: TextAlign.center,
            style: hoppin.type.meta.copyWith(color: colors.textMid),
          ),
        ],
      ),
    );
  }
}
