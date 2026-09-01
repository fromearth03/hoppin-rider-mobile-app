import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/support_tickets_repository.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';

/// The rider's tickets, refreshed after every submission.
final _ticketsProvider =
    FutureProvider.autoDispose<List<SupportTicket>>((ref) async {
  final result = await ref.watch(supportTicketsRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

final _typesProvider =
    FutureProvider.autoDispose<List<ComplaintType>>((ref) async {
  final result =
      await ref.watch(supportTicketsRepositoryProvider).complaintTypes();
  return switch (result) {
    Ok(:final value) => value,
    Err() => const <ComplaintType>[],
  };
});

/// Open Ticket — the rider ticket flow behind Help & Support's card.
///
/// `Support.png` supplies the SKELETON only (a form card above a "Recent
/// Issues" list): its copy is the driver app's ("Generate Payout", "Low
/// Rating Appeal") and is NOT rendered here — designer question 11. The
/// form carries what `POST /me/support-tickets` actually takes: a subject
/// (required), a typed reason from `GET /complaint-types`, a description.
/// The frame's "Preferred Resolution" dropdown has no field on the wire and
/// is omitted rather than faked.
class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({super.key});

  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _typeCode;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    if (subject.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref.read(supportTicketsRepositoryProvider).open(
          subject: subject,
          typeCode: _typeCode,
          body: _body.text,
        );
    if (!mounted) return;

    switch (result) {
      case Ok():
        setState(() {
          _submitting = false;
          _subject.clear();
          _body.clear();
          _typeCode = null;
        });
        ref.invalidate(_ticketsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Ticket opened. A representative will respond in 24 hours.')),
        );
      case Err(:final error):
        setState(() {
          _submitting = false;
          _error = RiderErrorCopy.messageFor(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final types = ref.watch(_typesProvider).valueOrNull ?? const [];
    final tickets = ref.watch(_ticketsProvider);

    return Scaffold(
      appBar: const SettingsHeader(title: 'Open Ticket'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SettingsCard(children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child:
                    Text('New Ticket', style: theme.textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _subject,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(hintText: 'Subject'),
                    ),
                    const SizedBox(height: 14),
                    if (types.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _typeCode,
                        decoration: const InputDecoration(
                            hintText: 'Select an issue category'),
                        items: [
                          for (final t in types)
                            DropdownMenuItem(
                                value: t.code, child: Text(t.label)),
                        ],
                        onChanged: (code) =>
                            setState(() => _typeCode = code),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _body,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          hintText: 'Please describe the issue…'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style:
                              const TextStyle(color: AppColors.negative)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      onPressed: _subject.text.trim().isEmpty || _submitting
                          ? null
                          : _submit,
                      child: Text(
                          _submitting ? 'Submitting…' : 'Submit Ticket'),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            SettingsCard(children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Text('Recent Issues',
                    style: theme.textTheme.titleMedium),
              ),
              tickets.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Could not load your tickets.',
                      style: theme.textTheme.bodyMedium),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('No tickets yet.',
                            style: theme.textTheme.bodyMedium),
                      )
                    : Column(children: [
                        for (final ticket in list)
                          _TicketRow(ticket: ticket),
                      ]),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  final SupportTicket ticket;
  const _TicketRow({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Status → the frame's card tinting: resolved green, open amber,
    // anything terminal-but-unhappy muted red.
    final (Color tint, Color fg, String statusLine) =
        switch (ticket.status) {
      'resolved' || 'closed' => (
          AppColors.positive.withValues(alpha: 0.12),
          AppColors.positive,
          'Resolved by the team',
        ),
      'rejected' => (
          AppColors.negative.withValues(alpha: 0.10),
          AppColors.negative,
          'Ticket was rejected',
        ),
      _ => (
          AppColors.warning.withValues(alpha: 0.12),
          AppColors.warning,
          'Your ticket is being processed',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ticket.subject, style: theme.textTheme.titleMedium),
            if (ticket.body != null) ...[
              const SizedBox(height: 2),
              Text(ticket.body!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Icon(
                  ticket.status == 'resolved' || ticket.status == 'closed'
                      ? Icons.check_circle
                      : Icons.schedule,
                  size: 16,
                  color: fg),
              const SizedBox(width: 6),
              Text(statusLine,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: fg)),
            ]),
          ],
        ),
      ),
    );
  }
}
