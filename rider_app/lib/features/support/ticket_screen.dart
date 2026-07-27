import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// One ticket + its message thread — `GET /me/support-tickets/:id`.
final ticketThreadProvider = FutureProvider.autoDispose
    .family<TicketThread, String>((ref, ticketId) {
  return ref.watch(supportRepositoryProvider).thread(ticketId);
});

/// The ticket thread (SUPPORT-01) — BOUND end to end.
///
/// Everything here is real: the messages came from `GET /me/support-tickets/:id`
/// and a reply goes to `POST /me/support-tickets/:id/messages`, where a person
/// reads it. There is no automated responder on the other end and the screen
/// does not pretend there is.
class TicketScreen extends ConsumerStatefulWidget {
  /// Creates the thread view for [ticketId].
  const TicketScreen({required this.ticketId, super.key});

  /// The ticket whose thread is shown.
  final String ticketId;

  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(supportRepositoryProvider).reply(
            ticketId: widget.ticketId,
            body: body,
          );
      _replyCtrl.clear();
      ref.invalidate(ticketThreadProvider(widget.ticketId));
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final threadAsync = ref.watch(ticketThreadProvider(widget.ticketId));

    // Insets off the spacing scale — no raw pixels in this feature.
    final gutter = EdgeInsets.symmetric(
      horizontal: hoppin.spacing.gutter,
      vertical: hoppin.spacing.gutter,
    );
    final listPad = EdgeInsets.symmetric(
      horizontal: hoppin.spacing.md,
      vertical: hoppin.spacing.md,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // NO HopTopBar. `/support/:id` nests under the Support TAB, so the
            // shell already renders the bar above it. This screen used to build
            // a second one — two stacked headers, the same defect the Support
            // list had.
            //
            // The rider still needs a way back to the ticket LIST, which the
            // shell bar does not offer. That is what this row is: one control,
            // not a whole duplicate chrome.
            _BackToTickets(
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/support'),
            ),
            Expanded(
              // ERROR IS ASKED FIRST — see the note on SupportScreen. Riverpod 3
              // keeps `isLoading` true on a failed future, so a loading-first
              // `.when` ladder would show the rider an endless spinner when
              // `GET /me/support-tickets/:id` is down. A hang is a worse lie
              // than an error: the rider concludes support itself is broken.
              child: switch (threadAsync) {
                AsyncValue(:final error?) => ListView(
                    padding: gutter,
                    children: [
                      HopBanner.error(
                        message: friendlyErrorMessage(error),
                        actionLabel: 'Retry',
                        onAction: () => ref
                            .invalidate(ticketThreadProvider(widget.ticketId)),
                      ),
                    ],
                  ),
                AsyncValue(:final value?) => RefreshIndicator(
                    color: colors.accent,
                    backgroundColor: colors.card,
                    onRefresh: () async => ref
                        .invalidate(ticketThreadProvider(widget.ticketId)),
                    child: value.messages.isEmpty
                        ? ListView(
                            padding: gutter,
                            children: [
                              SizedBox(height: hoppin.spacing.lg),
                              const HopEmptyState(
                                compact: true,
                                headline: 'No replies yet',
                                supporting:
                                    'A person will pick this up and reply here.',
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: listPad,
                            itemCount: value.messages.length,
                            itemBuilder: (context, i) =>
                                _MessageBubble(message: value.messages[i]),
                          ),
                  ),
                _ => Center(
                    child: CircularProgressIndicator(color: colors.accent),
                  ),
              },
            ),
            Divider(height: 1, color: colors.hairline),
            _ReplyComposer(
              controller: _replyCtrl,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// The reply composer, pinned to the bottom (thumb zone).
class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        hoppin.spacing.md,
        hoppin.spacing.sm,
        hoppin.spacing.md,
        hoppin.spacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('support.ticket.reply'),
              controller: controller,
              enabled: !sending,
              textCapitalization: TextCapitalization.sentences,
              style: hoppin.type.body.copyWith(color: colors.textHi),
              decoration: const InputDecoration(hintText: 'Write a reply…'),
              onSubmitted: (_) => onSend(),
            ),
          ),
          SizedBox(width: hoppin.spacing.sm),
          _SendButton(
            key: const Key('support.ticket.send'),
            sending: sending,
            onSend: onSend,
          ),
        ],
      ),
    );
  }
}

/// The send affordance — a token-styled accent circle, not a raw Material
/// icon button.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.sending, required this.onSend, super.key});

  final bool sending;
  final VoidCallback onSend;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return Semantics(
      button: true,
      label: 'Send',
      child: InkWell(
        onTap: sending ? null : onSend,
        borderRadius: BorderRadius.circular(hoppin.radii.pill),
        child: Container(
          height: _size,
          width: _size,
          decoration: BoxDecoration(
            color: sending ? colors.accentSubtle : colors.accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: sending
                ? SizedBox(
                    height: hoppin.spacing.md,
                    width: hoppin.spacing.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accent,
                    ),
                  )
                : Icon(Icons.send, color: colors.onAccent, size: 20),
          ),
        ),
      ),
    );
  }
}

/// One message in the thread. Staff replies are labelled as such — the rider
/// should know when a human at Hoppin has spoken.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final TicketMessage message;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final mine = !message.isStaff;

    final bg = mine ? colors.accentSubtle : colors.card;
    final fg = colors.textHi;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
        padding: EdgeInsets.symmetric(
          horizontal: hoppin.spacing.md,
          vertical: hoppin.spacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(hoppin.radii.card),
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isStaff)
              Text(
                'Hoppin support',
                style: hoppin.type.labelSmall.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Text(
              message.body,
              style: hoppin.type.body.copyWith(color: fg),
            ),
            if (message.createdAt != null)
              Padding(
                padding: EdgeInsets.only(top: hoppin.spacing.xs),
                child: Text(
                  formatTime(message.createdAt!),
                  style: hoppin.type.metaSmall.copyWith(color: colors.textMid),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The ONE control this screen owes: a way back to the ticket list.
///
/// `/support/:id` nests under the Support tab, so `RiderShell` already renders
/// the app bar above it. This screen used to build a full second `HopTopBar` —
/// two stacked headers. The shell's bar carries the title, bell and avatar; it
/// does NOT carry a back arrow, because a tab root needs none. A nested ticket
/// does. So the fix is this row, not a duplicate chrome.
class _BackToTickets extends StatelessWidget {
  const _BackToTickets({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onBack,
        icon: Icon(Icons.arrow_back, size: 18, color: colors.textHi),
        label: Text(
          'All tickets',
          style: hoppin.type.body.copyWith(color: colors.textHi),
        ),
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: hoppin.spacing.gutter,
            vertical: hoppin.spacing.sm,
          ),
        ),
      ),
    );
  }
}
