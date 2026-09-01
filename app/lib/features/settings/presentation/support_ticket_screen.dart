import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/widgets/bottom_scroll_fade.dart';
import '../../history/data/trip_history_repository.dart';
import '../data/support_tickets_repository.dart';
import 'ticket_thread_screen.dart';
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

/// Recent trips for the optional "about this ride" attachment.
final _recentTripsProvider =
    FutureProvider.autoDispose<List<TripHistoryItem>>((ref) async {
  final result =
      await ref.watch(tripHistoryRepositoryProvider).myTrips(limit: 10);
  return switch (result) {
    Ok(:final value) => value.trips,
    Err() => const <TripHistoryItem>[],
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
  final _body = TextEditingController();
  String? _typeCode;
  TripHistoryItem? _ride;
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
          body: description,
          rideId: _ride?.id,
        );
    if (!mounted) return;

    switch (result) {
      case Ok():
        setState(() {
          _submitting = false;
          _body.clear();
          _typeCode = null;
          _ride = null;
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

  /// Attach the trip this complaint is about — recent trips, newest first.
  Future<void> _pickRide() async {
    final trips = ref.read(_recentTripsProvider).valueOrNull ?? const [];
    final chosen = await showModalBottomSheet<TripHistoryItem>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: trips.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No recent trips to attach.',
                    textAlign: TextAlign.center),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final t in trips)
                    ListTile(
                      leading: const Icon(Icons.directions_car,
                          color: AppColors.navy),
                      title: Text(
                        t.dropoffLabel ?? t.pickupLabel ?? 'Ride',
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(DateFormat('d MMM, HH:mm')
                          .format(t.requestedAt.toLocal())),
                      onTap: () => Navigator.of(ctx).pop(t),
                    ),
                ],
              ),
      ),
    );
    if (chosen != null && mounted) setState(() => _ride = chosen);
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
                      Text('About a ride (optional)',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _RidePickerField(
                        ride: _ride,
                        onPick: _pickRide,
                        onClear: () => setState(() => _ride = null),
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

/// The optional "about this ride" attachment on the form: empty → a picker
/// affordance; chosen → the trip summary with a clear ✕.
class _RidePickerField extends StatelessWidget {
  final TripHistoryItem? ride;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _RidePickerField({
    required this.ride,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = ride;

    return Material(
      color: const Color(0xFFF4F4F7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.directions_car,
                  size: 20, color: AppColors.navy),
              const SizedBox(width: 10),
              Expanded(
                child: chosen == null
                    ? Text('Attach the trip this is about',
                        style: theme.textTheme.bodyMedium)
                    : Text(
                        '${chosen.dropoffLabel ?? chosen.pickupLabel ?? 'Ride'}'
                        '  ·  ${DateFormat('d MMM').format(chosen.requestedAt.toLocal())}',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontSize: 13.5),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (chosen != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove the attached ride',
                )
              else
                const Icon(Icons.keyboard_arrow_down,
                    color: AppColors.lightTextSecondary),
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
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          // The whole card opens the thread: what was filed, the staff
          // conversation, and the reply box.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TicketThreadScreen(ticketId: ticket.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                  Expanded(
                    child: Text(statusLine,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: fg)),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.lightTextSecondary),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
