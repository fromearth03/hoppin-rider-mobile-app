import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'widgets/chat_closed_state.dart';
import 'widgets/chat_templates.dart';

/// In-trip chat — polls `GET /rides/:id/messages` every few seconds while
/// open (push replaces this later). Closed threads return `409 CHAT_CLOSED`
/// on send, which is TERMINAL: the composer and the template chips are
/// removed and [ChatClosedState] takes their place. That server 409 is the
/// AUTHORITY on the chat window; the client-side `TripState.chatOpen` phase
/// mirror only gates the entry points, and is UX, not correctness.
final chatStreamProvider = StreamProvider.autoDispose
    .family<List<RideMessage>, String>((ref, rideId) async* {
      final repo = ref.watch(ridesRepositoryProvider);
      var all = <RideMessage>[];
      while (true) {
        try {
          // Full fetch each tick — trips are short, threads are small; the
          // `since` param exists for when this needs to get smarter.
          all = await repo.messages(rideId);
          yield all;
        } on Exception {
          // transient — keep the last list on screen
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    });

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composerCtrl = TextEditingController();
  bool _sending = false;

  /// TERMINAL: the server answered `409 CHAT_CLOSED`, so this thread will
  /// never accept another message. The composer and the template chips come
  /// out of the tree entirely and [ChatClosedState] takes their place.
  ///
  /// The server's 409 is the **AUTHORITY** on whether chat is open. The
  /// client-side `TripState.chatOpen` phase mirror (which gates the chat
  /// ENTRY points, so a rider is never dropped into a thread that will reject
  /// them) is **UX only** — it is not, and must never become, the correctness
  /// check. This flag is set by the server's answer, nothing else.
  bool _chatClosed = false;

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
  }

  /// The ONE send path. The composer and every [ChatTemplates] chip go through
  /// it — so a chip gets the identical `409 CHAT_CLOSED` handling, and there is
  /// exactly one place where that contract lives.
  ///
  /// Pass [templateBody] to send a quick reply verbatim; omit it to send the
  /// composer's current text.
  Future<void> _send([String? templateBody]) async {
    if (_sending || _chatClosed) return; // one in-flight send; never after 409
    final body = (templateBody ?? _composerCtrl.text).trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(ridesRepositoryProvider)
          .sendMessage(rideId: widget.rideId, body: body);
      _composerCtrl.clear();
      ref.invalidate(chatStreamProvider(widget.rideId));
    } on ApiException catch (e) {
      // Branch on the MACHINE code, never on the human-readable message: the
      // ride-service normalises every failure to `{ error, code }`, the copy
      // is free to change, and a different 409 (e.g. ACTIVE_TRIP_EXISTS) is
      // NOT a closed chat.
      if (e.code == 'CHAT_CLOSED') {
        // TERMINAL. Not a snackbar over a live composer — that disguises a
        // permanent close as a network hiccup and the rider keeps retyping.
        if (mounted) setState(() => _chatClosed = true);
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
    } on Exception catch (e) {
      // Everything else stays transient — we branch, we do not swallow.
      messenger.showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final messagesAsync = ref.watch(chatStreamProvider(widget.rideId));
    final myId = ref.watch(authServiceProvider).userId;

    return Scaffold(
      // Named explicitly, like every other rider surface. It already resolved
      // here via `scaffoldBackgroundColor`, but the bubbles are measured
      // against this colour, so it is stated where it can be seen.
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // 🔴 THE WORST OF THE TRAPS. This bar carried no `leading` at all,
            // and a stock AppBar only auto-draws its back arrow when
            // `Navigator.canPop()` is true. Chat is reached with `context.go`
            // (see trip_router), which REPLACES rather than pushes — so canPop
            // is ALWAYS false, no arrow ever rendered, and a rider who tapped
            // "Message driver" mid-trip could not get back to the trip they
            // were on. The design-system bar with an unconditional back intent
            // is the only thing that gives it an exit: pop when there is a
            // stack, otherwise return to the trip this thread belongs to.
            HopTopBar(
              title: 'Message your driver',
              onBack: () => context.canPop()
                  ? context.pop()
                  : context.go('/trip/${widget.rideId}'),
            ),
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(context.hoppin.spacing.gutter),
                    child: HopBanner.error(message: friendlyErrorMessage(e)),
                  ),
                ),
                data: (messages) => messages.isEmpty
                    ? Center(
                        child: Padding(
                          // The empty line ran edge-to-edge on a narrow phone;
                          // it now sits inside the page gutter like every other
                          // piece of copy in the app.
                          padding: EdgeInsets.symmetric(
                            horizontal: hoppin.spacing.gutter,
                          ),
                          child: Text(
                            'Say hello — messages stay between you and '
                            'your driver.',
                            textAlign: TextAlign.center,
                            style: hoppin.type.body
                                .copyWith(color: colors.textMid),
                          ),
                        ),
                      )
                    : ListView.builder(
                        reverse: true, // newest pinned to the bottom
                        padding: EdgeInsets.all(hoppin.spacing.lg),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[messages.length - 1 - i];
                          return _ChatBubble(
                            message: m,
                            mine: m.senderId == myId,
                          );
                        },
                      ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.hairline),
            // The send surface. Once the server answers `409 CHAT_CLOSED` it
            // is REPLACED — composer and chips both leave the tree — by the
            // terminal panel. The thread above stays readable.
            if (_chatClosed)
              const ChatClosedState()
            else ...[
              // COMMS-01: the three verbatim Figma quick-replies. They share
              // `_send` with the composer, so they carry exactly the same
              // closed-chat contract.
              ChatTemplates(onSend: _send),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  hoppin.spacing.md,
                  hoppin.spacing.sm,
                  hoppin.spacing.md,
                  hoppin.spacing.md,
                ),
                child: Row(
                  // The field grows with its text; the send button must stay
                  // centred against it rather than stretch into a tall slab.
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _composerCtrl,
                        enabled: !_sending,
                        textCapitalization: TextCapitalization.sentences,
                        style: hoppin.type.body.copyWith(color: colors.textHi),
                        decoration: const InputDecoration(hintText: 'Message…'),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    SizedBox(width: hoppin.spacing.sm),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      // The busy spinner must be tinted for the FILLED slab it
                      // sits on — it was inheriting the default indicator
                      // colour (the accent), which is the same navy as the
                      // button beneath it, so pressing Send made the control
                      // look empty for the whole in-flight moment.
                      icon: _sending
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onAccent,
                              ),
                            )
                          : const Icon(Icons.send),
                      tooltip: 'Send',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One message in the thread.
///
/// 🔴 **The incoming bubble used to be INVISIBLE in light theme.** It painted
/// `colorScheme.surfaceContainerHighest`, which this theme maps to
/// `colors.card` — and in light that is pure `#FFFFFF`, sitting on the
/// `#F6FAFC` canvas this Scaffold inherits. That is a **1.03:1** fill against
/// its own background: the driver's bubble had no visible shape at all, so
/// their messages read as bare text floating on the page while the rider's own
/// messages sat in a tinted capsule. A chat where only one side has bubbles
/// does not look like a design decision, it looks broken.
///
/// Both sides now carry a real surface on the semantic tokens: the rider keeps
/// the accent tint (which is a genuine step off the canvas in both themes) and
/// the driver gets the card fill PLUS a hairline, which is exactly how the rest
/// of the app separates a card from the page when the fill alone cannot.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.mine});

  final RideMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
        padding: EdgeInsets.symmetric(
          horizontal: hoppin.spacing.md,
          vertical: hoppin.spacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: mine ? colors.accentSubtle : colors.card,
          borderRadius: BorderRadius.circular(hoppin.radii.sheet),
          // The incoming bubble's fill is a card on a canvas — in light those
          // are a hair apart, so the EDGE is what gives it a shape. The rider's
          // own bubble is already tinted and needs no line.
          border: mine ? null : Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: hoppin.type.body.copyWith(color: colors.textHi),
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
