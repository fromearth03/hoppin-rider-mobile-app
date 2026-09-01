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

/// The rider's tickets, refreshed after every submission.
final _ticketsProvider =
    FutureProvider.autoDispose<List<SupportTicket>>((ref) async {
  final result = await ref.watch(supportTicketsRepositoryProvider).list();
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
});

/// The rider's trips for the complaint's "about this ride" attachment —
/// ANY ride can be complained about, so this pulls the server's page cap.
final _attachableTripsProvider =
    FutureProvider.autoDispose<List<TripHistoryItem>>((ref) async {
  final result =
      await ref.watch(tripHistoryRepositoryProvider).myTrips(limit: 50);
  return switch (result) {
    Ok(:final value) => value.trips,
    Err() => const <TripHistoryItem>[],
  };
});

/// Importance tags for the complaint form's chips.
final _tagsProvider =
    FutureProvider.autoDispose<List<ComplaintTag>>((ref) async {
  final result =
      await ref.watch(supportTicketsRepositoryProvider).complaintTags();
  return switch (result) {
    Ok(:final value) => value,
    Err() => const <ComplaintTag>[],
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

/// Support and Complaints, kept apart the way riders think about them —
/// one `support_tickets` table server-side, split client-side by `category`:
///
///  * **Support** — "help me": a free subject + description.
///  * **Complaints** — "something was wrong": a typed complaint reason
///    (`/complaint-types`) plus the ride it is about.
///
/// Each tab files with its own `category` ('support' / 'complaint') and
/// lists only its own tickets; legacy rows without a category surface under
/// Support rather than vanishing. Both kinds open the same thread screen.
class SupportTicketScreen extends ConsumerStatefulWidget {
  /// 0 = Support, 1 = Complaints.
  final int initialTab;

  const SupportTicketScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _typeCode;
  TripHistoryItem? _ride;
  final Set<String> _tags = {};
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool _canSubmit(bool complaint) {
    if (_submitting) return false;
    if (complaint) return _typeCode != null;
    return _subject.text.trim().isNotEmpty || _body.text.trim().isNotEmpty;
  }

  Future<void> _submit({required bool complaint}) async {
    if (!_canSubmit(complaint)) return;

    final types = ref.read(_typesProvider).valueOrNull ?? const [];
    final categoryLabel = types
        .where((t) => t.code == _typeCode)
        .map((t) => t.label)
        .firstOrNull;
    final description = _body.text.trim();
    final typedSubject = _subject.text.trim();

    // The wire requires a subject: a complaint's is its typed reason; a
    // support ticket's is what the rider wrote (falling back to the
    // description's opening words).
    final subject = complaint
        ? (categoryLabel ?? 'Complaint')
        : (typedSubject.isNotEmpty
            ? typedSubject
            : (description.length > 60
                ? '${description.substring(0, 57)}…'
                : description));

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ref.read(supportTicketsRepositoryProvider).open(
          subject: subject.isEmpty ? 'Support request' : subject,
          category: complaint ? 'complaint' : 'support',
          typeCode: complaint ? _typeCode : null,
          body: description,
          rideId: complaint ? _ride?.id : null,
          tags: complaint ? _tags.toList() : const [],
        );
    if (!mounted) return;

    switch (result) {
      case Ok():
        setState(() {
          _submitting = false;
          _subject.clear();
          _body.clear();
          _typeCode = null;
          _ride = null;
          _tags.clear();
        });
        ref.invalidate(_ticketsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(complaint
                  ? 'Complaint filed. The team will look into it and reply.'
                  : 'Ticket opened. A representative will respond in 24 hours.')),
        );
      case Err(:final error):
        setState(() {
          _submitting = false;
          _error = RiderErrorCopy.messageFor(error);
        });
    }
  }

  /// Attach the trip this complaint is about — any of the rider's rides,
  /// newest first. AWAITED here: reading the provider's cache showed an
  /// empty sheet on first open because nothing had fetched yet.
  Future<void> _pickRide() async {
    final trips = await ref.read(_attachableTripsProvider.future);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<TripHistoryItem>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: trips.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No rides on this account yet.',
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
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('Help & Support'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          bottom: const TabBar(
            labelColor: AppColors.navy,
            indicatorColor: AppColors.navy,
            tabs: [
              Tab(text: 'Support'),
              Tab(text: 'Complaints'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _tab(complaint: false),
              _tab(complaint: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab({required bool complaint}) {
    final theme = Theme.of(context);
    final types = ref.watch(_typesProvider).valueOrNull ?? const [];
    final tickets = ref.watch(_ticketsProvider);

    return BottomScrollFade(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
        children: [
          SettingsCard(children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(complaint ? 'File a Complaint' : 'New Support Ticket',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (complaint) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _typeCode,
                      // Long labels ("Service animal refusal (regulatory
                      // breach)") overflowed the field border without this.
                      isExpanded: true,
                      decoration: const InputDecoration(
                          hintText: 'What went wrong?'),
                      icon: const Icon(Icons.keyboard_arrow_down),
                      items: [
                        for (final t in types)
                          DropdownMenuItem(
                              value: t.code,
                              child: Text(t.label,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: types.isEmpty
                          ? null
                          : (code) => setState(() => _typeCode = code),
                    ),
                  ] else ...[
                    TextField(
                      controller: _subject,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                          hintText: 'What do you need help with?'),
                    ),
                  ],
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
                  if (complaint) ...[
                    const SizedBox(height: 18),
                    Builder(builder: (context) {
                      final tags =
                          ref.watch(_tagsProvider).valueOrNull ?? const [];
                      if (tags.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tags (optional)',
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in tags)
                                FilterChip(
                                  label: Text(t.label,
                                      style:
                                          const TextStyle(fontSize: 12.5)),
                                  selected: _tags.contains(t.name),
                                  selectedColor: AppColors.navy
                                      .withValues(alpha: 0.12),
                                  checkmarkColor: AppColors.navy,
                                  onSelected: (on) => setState(() => on
                                      ? _tags.add(t.name)
                                      : _tags.remove(t.name)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    }),
                    Text('About a ride (optional)',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _RidePickerField(
                      ride: _ride,
                      onPick: _pickRide,
                      onClear: () => setState(() => _ride = null),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.negative)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: _canSubmit(complaint)
                        ? () => _submit(complaint: complaint)
                        : null,
                    child: Text(_submitting
                        ? 'Submitting…'
                        : (complaint ? 'File Complaint' : 'Submit Ticket')),
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
              child: Text(
                  complaint ? 'Your Complaints' : 'Recent Tickets',
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
              data: (list) {
                // Complaints carry category 'complaint'; everything else —
                // including legacy rows with no category — is Support.
                final mine = [
                  for (final t in list)
                    if ((t.category == 'complaint') == complaint) t,
                ];
                return mine.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                            complaint
                                ? 'No complaints filed.'
                                : 'No tickets yet.',
                            style: theme.textTheme.bodyMedium),
                      )
                    : Column(children: [
                        for (final ticket in mine) _TicketRow(ticket: ticket),
                      ]);
              },
            ),
          ]),
        ],
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
