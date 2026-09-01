import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/bottom_scroll_fade.dart';
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

/// `Support.png`, built to the frame: an "Automated Support" form (issue
/// category, description, preferred resolution) over a "Recent Issues" list
/// of status-tinted cards, with the frame's bottom scroll fade.
///
/// Wire honesty behind the drawn controls:
/// - The API's one REQUIRED field is `subject`, which the frame does not
///   draw. The subject is the chosen category's label (or the description's
///   first words), so a ticket always files with a real subject.
/// - "Preferred Resolution" has no field on `POST /me/support-tickets`; the
///   rider's choice is appended to the ticket body, so it reaches the
///   support team rather than being silently dropped. Its option copy is
///   rider-correct — the frame's "Generate Payout" is driver-app vocabulary
///   (designer question 11).
/// - The tinted issue cards carry the SERVER's ticket subjects and statuses,
///   never the frame's sample copy.
class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({super.key});

  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  static const _resolutions = [
    'Refund review',
    'Account credit',
    'A response from the team',
  ];

  final _body = TextEditingController();
  String? _typeCode;
  String? _resolution;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && (_typeCode != null || _body.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final types = ref.read(_typesProvider).valueOrNull ?? const [];
    final categoryLabel = types
        .where((t) => t.code == _typeCode)
        .map((t) => t.label)
        .firstOrNull;
    final description = _body.text.trim();

    // The wire requires a subject the frame never draws — the category
    // label is the honest one; a free-typed issue falls back to its own
    // opening words.
    final subject = categoryLabel ??
        (description.length > 60
            ? '${description.substring(0, 57)}…'
            : description);

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref.read(supportTicketsRepositoryProvider).open(
          subject: subject.isEmpty ? 'Support request' : subject,
          typeCode: _typeCode,
          body: [
            if (description.isNotEmpty) description,
            if (_resolution != null) 'Preferred resolution: $_resolution',
          ].join('\n\n'),
        );
    if (!mounted) return;

    switch (result) {
      case Ok():
        setState(() {
          _submitting = false;
          _body.clear();
          _typeCode = null;
          _resolution = null;
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
      // The frame titles this screen "Help & Support" as well.
      appBar: const SettingsHeader(title: 'Help & Support'),
      body: SafeArea(
        child: BottomScrollFade(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SettingsCard(children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Automated Support',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _typeCode,
                        decoration: const InputDecoration(
                            hintText: 'Select an issue category'),
                        icon: const Icon(Icons.keyboard_arrow_down),
                        items: [
                          for (final t in types)
                            DropdownMenuItem(
                                value: t.code, child: Text(t.label)),
                        ],
                        onChanged: types.isEmpty
                            ? null
                            : (code) => setState(() => _typeCode = code),
                      ),
                      const SizedBox(height: 18),
                      Text('Description', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _body,
                        maxLines: 5,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            hintText: 'Please describe the issue…'),
                      ),
                      const SizedBox(height: 18),
                      Text('Preferred Resolution',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _resolution,
                        decoration: const InputDecoration(
                            hintText: 'Select preferred resolution'),
                        icon: const Icon(Icons.keyboard_arrow_down),
                        items: [
                          for (final r in _resolutions)
                            DropdownMenuItem(value: r, child: Text(r)),
                        ],
                        onChanged: (r) => setState(() => _resolution = r),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style:
                                const TextStyle(color: AppColors.negative)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        onPressed: _canSubmit ? _submit : null,
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
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
    // Status → the frame's card tinting: resolved green with a check, open
    // amber with a clock, rejected a muted red.
    final (Color tint, Color fg, IconData icon, String statusLine) =
        switch (ticket.status) {
      'resolved' || 'closed' => (
          AppColors.positive.withValues(alpha: 0.12),
          AppColors.positive,
          Icons.check_circle,
          'Resolved by the team',
        ),
      'rejected' => (
          AppColors.negative.withValues(alpha: 0.10),
          AppColors.negative,
          Icons.cancel,
          'Your ticket has been rejected',
        ),
      _ => (
          AppColors.warning.withValues(alpha: 0.14),
          AppColors.warning,
          Icons.schedule,
          'Your ticket is in under process',
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
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(statusLine,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
            ]),
          ],
        ),
      ),
    );
  }
}
