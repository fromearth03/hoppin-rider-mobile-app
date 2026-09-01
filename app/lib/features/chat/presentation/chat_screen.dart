import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/chat_repository.dart';

/// In-ride chat with the driver.
///
/// Four things the Figma draws are NOT built, because nothing backs them:
/// the call button (no phone number is exposed by any endpoint, and there is
/// no masked-calling service), attachments and voice notes (`ride_messages`
/// has a single text column), and the "Online" presence dot (presence is
/// tracked nowhere). All four are phase 2. Drawing a call button that does
/// nothing would be worse than omitting it - a rider taps it when they need
/// the driver most.
class ChatScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String driverName;

  const ChatScreen({
    super.key,
    required this.rideId,
    this.driverName = 'Driver',
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final _messages = <RideMessage>[];
  DateTime? _since;
  Timer? _poll;
  bool _sending = false;
  ApiException? _error;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    // An empty id can only come from a hand-typed URL, and the request it
    // would send — /rides//messages — is malformed. Skip straight to the
    // error state instead of firing (and re-polling) a doomed call.
    if (widget.rideId.isEmpty) {
      _error = const ApiException(
          'RIDE_NOT_FOUND', 'This ride could not be found.', 0);
      _loadedOnce = true;
      return;
    }
    _load();
    // There is no websocket for chat; the server expects a `since` cursor.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result =
        await ref.read(chatRepositoryProvider).messages(widget.rideId,
            since: _since);
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        if (value.isEmpty) {
          if (!_loadedOnce) setState(() => _loadedOnce = true);
          return;
        }
        setState(() {
          _merge(value);
          // The cursor is the newest message we have actually seen. Messages
          // whose timestamp would not parse are dropped upstream, so this can
          // never be poisoned by one bad row.
          _since = _messages
              .map((m) => m.createdAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          _error = null;
          _loadedOnce = true;
        });
        _scrollToEnd();
      case Err(:final error):
        // A poll failure while the thread is already showing is not worth
        // interrupting the rider for; only a failure to load at all is.
        if (!_loadedOnce) setState(() => _error = error);
    }
  }

  /// Merge by id instead of appending. The `since` cursor is inclusive
  /// server-side AND a poll can be in flight while a send lands — either way
  /// the just-sent message came back a second time and showed as a duplicate
  /// bubble. A message we already hold is REPLACED, not dropped: the newer
  /// copy may carry the flipped read status for the ticks.
  void _merge(Iterable<RideMessage> incoming) {
    for (final m in incoming) {
      final i = _messages.indexWhere((e) => e.id == m.id);
      if (i >= 0) {
        _messages[i] = m;
      } else {
        _messages.add(m);
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final result =
        await ref.read(chatRepositoryProvider).send(widget.rideId, text);
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        setState(() {
          _merge([value]);
          _since = value.createdAt;
          _input.clear();
          _sending = false;
          _error = null;
        });
        _scrollToEnd();
      case Err(:final error):
        // The text stays in the field so the rider can retry without retyping.
        setState(() {
          _sending = false;
          _error = error;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Text(
                widget.driverName.characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.driverName,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body(theme)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                RiderErrorCopy.messageFor(_error!),
                style: const TextStyle(color: AppColors.negative),
              ),
            ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (!_loadedOnce && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No messages yet. Say hello to your driver.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final message = _messages[i];
        // A day separator above the first message of each day. The design
        // draws "Today"; a ride's chat can straddle midnight, so the label is
        // computed rather than fixed.
        final previous = i == 0 ? null : _messages[i - 1];
        final newDay = previous == null ||
            !_sameDay(previous.createdAt, message.createdAt);

        return Column(
          children: [
            if (newDay) _DayPill(date: message.createdAt),
            _Bubble(message: message, driverName: widget.driverName),
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Bubble extends StatelessWidget {
  final RideMessage message;
  final String driverName;
  const _Bubble({required this.message, required this.driverName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.isMine;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // The driver's avatar sits beside their bubble, as in the design.
          if (!mine) ...[
            _Avatar(name: driverName),
            const SizedBox(width: 8),
          ],
          // Bubbles hug their text and stop well short of the far edge — a
          // full-width bubble has no direction to it, and the conversation
          // stops reading as a conversation.
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? AppColors.accent : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A reply whose parent was deleted keeps its id but has no
                  // preview, so no empty quote box is drawn.
                  if (message.replyToPreview != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        message.replyToPreview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: mine ? Colors.white70 : null,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    message.body,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: mine ? Colors.white : null,
                    ),
                  ),
                  // A read tick appears only on the rider's own messages -
                  // one on the driver's would claim they read their own text.
                  if (mine && message.status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        message.status == 'read'
                            ? Icons.done_all
                            : Icons.done,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ),
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

/// The dark "Today" pill the design centres above each day's first message.
class _DayPill extends StatelessWidget {
  final DateTime date;
  const _DayPill({required this.date});

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final delta = today.difference(day).inDays;

    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    return DateFormat('d MMM').format(day);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.lightTextPrimary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Circular initial, standing in for the driver's photo — no endpoint serves
/// one, so a broken image placeholder would be worse than a letter.
class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primary,
      child: Text(
        name.characters.first.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            // A dark rounded pill, as drawn — not the app's standard boxed
            // field. The attachment and microphone icons the design puts
            // inside it are omitted: `ride_messages` holds a single text
            // column, so neither could send anything.
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.lightTextPrimary,
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    hintText: 'Enter your message',
                    hintStyle:
                        TextStyle(color: Color(0xFFA0A0B0), fontSize: 15),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: AppColors.positive,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: sending ? null : onSend,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: sending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send,
                          color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
