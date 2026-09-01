import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../data/support_tickets_repository.dart';

/// One ticket + its whole thread; opening it marks the thread read.
final _ticketDetailProvider = FutureProvider.autoDispose
    .family<TicketDetail, String>((ref, id) async {
  final result = await ref.watch(supportTicketsRepositoryProvider).get(id);
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// The inside of a support ticket / complaint: what was filed (with the ride
/// it is about, when one was attached), the staff conversation, and a reply
/// box. Backed by `GET /me/support-tickets/:id` +
/// `POST /me/support-tickets/:id/messages`.
class TicketThreadScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const TicketThreadScreen({super.key, required this.ticketId});

  @override
  ConsumerState<TicketThreadScreen> createState() =>
      _TicketThreadScreenState();
}

class _TicketThreadScreenState extends ConsumerState<TicketThreadScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);

    final result = await ref
        .read(supportTicketsRepositoryProvider)
        .reply(widget.ticketId, text);
    if (!mounted) return;
    setState(() => _sending = false);

    switch (result) {
      case Ok():
        _reply.clear();
        ref.invalidate(_ticketDetailProvider(widget.ticketId));
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = ref.watch(_ticketDetailProvider(widget.ticketId));

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Ticket'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not load this ticket.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.negative),
              ),
            ),
          ),
          data: (d) => Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.refresh(
                      _ticketDetailProvider(widget.ticketId).future),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      _TicketHeader(ticket: d.ticket),
                      const SizedBox(height: 12),
                      if (d.messages.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No replies yet — the team usually responds '
                            'within 24 hours.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      else
                        for (final m in d.messages) _Bubble(message: m),
                    ],
                  ),
                ),
              ),
              // Reply composer — a resolved ticket still accepts replies
              // (the backend allows it; support reopens as needed).
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Write a reply…',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppColors.navy,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending ? null : _send,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send,
                                  size: 20, color: Colors.white),
                        ),
                      ),
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

class _TicketHeader extends StatelessWidget {
  final SupportTicket ticket;
  const _TicketHeader({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color fg, String statusLine) = switch (ticket.status) {
      'resolved' || 'closed' => (AppColors.positive, 'Resolved'),
      'rejected' => (AppColors.negative, 'Rejected'),
      _ => (AppColors.warning, 'In progress'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ticket.subject,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontSize: 16, color: AppColors.navy)),
          if (ticket.body != null) ...[
            const SizedBox(height: 6),
            Text(ticket.body!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: fg),
              const SizedBox(width: 6),
              Text(statusLine,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (ticket.createdAt != null)
                Text(
                  DateFormat('d MMM, HH:mm')
                      .format(ticket.createdAt!.toLocal()),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
                ),
            ],
          ),
          // The trip this complaint is about — one tap away.
          if (ticket.rideId != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => context
                  .push('${AppRoutes.tripDetails}?ride=${ticket.rideId}'),
              child: Row(
                children: [
                  const Icon(Icons.directions_car,
                      size: 16, color: AppColors.navy),
                  const SizedBox(width: 6),
                  Text('View the ride this is about',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.navy,
                          decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ],
          if (ticket.resolutionNotes != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.positive.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resolution',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 13, color: AppColors.positive)),
                  const SizedBox(height: 4),
                  Text(ticket.resolutionNotes!,
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final TicketMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = !message.isStaff;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isStaff)
              Text('Support',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent)),
            Text(
              message.body,
              style: TextStyle(
                fontSize: 14,
                color: mine ? Colors.white : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.createdAt != null)
                  Text(
                    DateFormat('d MMM, HH:mm')
                        .format(message.createdAt!.toLocal()),
                    style: TextStyle(
                      fontSize: 10,
                      color: mine ? Colors.white70 : AppColors.lightTextSecondary,
                    ),
                  ),
                // Own messages: a second tick once staff actually read it.
                if (mine && message.status != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == 'read' ? Icons.done_all : Icons.done,
                    size: 13,
                    color: Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
