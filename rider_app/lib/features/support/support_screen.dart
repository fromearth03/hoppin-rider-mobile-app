import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'support_categories.dart';

/// My tickets — `GET /me/support-tickets`.
final ticketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) {
  return ref.watch(supportRepositoryProvider).myTickets();
});

final complaintTypesProvider =
    FutureProvider.autoDispose<List<ComplaintTypeOption>>((ref) {
      return ref.watch(ridesRepositoryProvider).complaintTypes();
    });

/// Support hub (SUPPORT-01): ticket list + open a new ticket.
///
/// **This is the one fully end-to-end BOUND cluster in the release-gate phase.**
/// `POST/GET /me/support-tickets` genuinely round-trips: the rider opens a
/// ticket, a human reads it, the reply comes back on the thread. Everything on
/// this screen is real.
///
/// Two deliberate omissions, both of them the honest call:
///
///   * **The Figma "Automated Support" frame is NOT built.** It shows a
///     four-tile picker over "Recent Issues" cards reading *"£5.00 refund
///     issued automatically"*. That resolution engine does not exist. Rendering
///     it would advertise refunds the backend cannot issue. The manual ticket
///     list below IS the honest surface.
///
///   * **There is no resolution-preference picker.** The Figma report-issue
///     modal offers one; `POST /me/support-tickets` has no field to carry it. A
///     picker whose value is silently discarded is a control that lies. The
///     rider says what outcome they want in the free-text body instead — which
///     a human actually reads.
///
/// And one deliberate inclusion: the disclosure that a **person** reads every
/// ticket. Scope-Lock §3.2 asks for "No Human Interaction"; we do not have an
/// automated resolver, so we say so. It is true, it is the better experience,
/// and it is why every support outcome today is decided by a human.
class SupportScreen extends ConsumerWidget {
  /// Creates the support hub.
  const SupportScreen({super.key});

  /// The §3.2 disclosure. A virtue, not an apology — and it is what makes the
  /// deletion route credible: the rider must believe a human will act.
  static const String humanSupportDisclosure =
      'A person reads every ticket. We aim to reply within 24 hours.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final tickets = ref.watch(ticketsProvider);

    // Every inset on this screen comes off the spacing scale. There is not a
    // raw pixel anywhere in this feature — a design change is a token re-map.
    final gutter = EdgeInsets.symmetric(
      horizontal: hoppin.spacing.gutter,
      vertical: hoppin.spacing.gutter,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // NO HopTopBar HERE. `/support` is a shell tab, and RiderShell
            // already renders the bar (title, bell, avatar) above every tab.
            // This screen used to build a SECOND one, so the rider saw the
            // header twice — the shell's, with the real unread badge, stacked
            // on this one, without it. The shell owns the chrome; a tab must
            // not draw its own.
            Padding(
              padding: EdgeInsets.fromLTRB(
                hoppin.spacing.gutter,
                hoppin.spacing.sm,
                hoppin.spacing.gutter,
                hoppin.spacing.sm,
              ),
              child: const HopBanner.notice(message: humanSupportDisclosure),
            ),
            Expanded(
              child: RefreshIndicator(
                color: colors.accent,
                backgroundColor: colors.card,
                onRefresh: () async => ref.invalidate(ticketsProvider),
                // ERROR IS ASKED FIRST — deliberately, and NOT a `.when` ladder.
                //
                // Riverpod 3 delivers a failed future as AsyncLoading carrying
                // the error: `isLoading` stays TRUE. A loading-first ladder
                // therefore routes a FAILURE into the spinner branch, and the
                // rider watches a spinner that never resolves. That reads as a
                // hang, not a failure — so they never learn the call died, and
                // they never retry. `GET /me/support-tickets` is BOUND and can
                // genuinely be down; this is the branch that says so.
                child: switch (tickets) {
                  AsyncValue(:final error?) => ListView(
                    padding: gutter,
                    children: [
                      HopBanner.error(
                        message: friendlyErrorMessage(error),
                        actionLabel: 'Retry',
                        onAction: () => ref.invalidate(ticketsProvider),
                      ),
                    ],
                  ),
                  AsyncValue(:final value?) =>
                    value.isEmpty
                        ? ListView(
                            padding: gutter,
                            children: [
                              SizedBox(height: hoppin.spacing.xl),
                              // Honest, and provably so: `GET /me/support-tickets`
                              // is BOUND, so an empty list is a FACT — not the
                              // ignorance the notification centre has to disclose.
                              const HopEmptyState(
                                headline: 'No tickets yet',
                                supporting:
                                    'Need help with a trip? Open a ticket and a '
                                    'person will pick it up.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: gutter,
                            itemCount: value.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: hoppin.spacing.sm),
                            itemBuilder: (context, i) =>
                                _TicketCard(ticket: value[i]),
                          ),
                  _ => Center(
                    child: CircularProgressIndicator(color: colors.accent),
                  ),
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                hoppin.spacing.gutter,
                hoppin.spacing.sm,
                hoppin.spacing.gutter,
                hoppin.spacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HopButton.primary(
                label: 'File a complaint',
                icon: Icons.add,
                expand: true,
                onPressed: () => _showNewTicketSheet(context, complaint: true),
                  ),
                  SizedBox(height: hoppin.spacing.sm),
                  HopButton.secondary(
                    label: 'New support ticket',
                    icon: Icons.support_agent_outlined,
                    expand: true,
                    onPressed: () => _showNewTicketSheet(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewTicketSheet(BuildContext context, {bool complaint = false}) {
    final colors = context.hoppin.colors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      barrierColor: colors.scrim,
      builder: (_) => HopSheet(child: _NewTicketSheet(complaint: complaint)),
    );
  }
}

/// One ticket in the list. Open tickets carry the lane accent; settled ones sit
/// back in textMid — the rider's eye should land on what is still live.
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final open = ticket.status != 'closed' && ticket.status != 'resolved';
    final accent = open ? colors.accent : colors.textMid;

    final subtitle = ticket.createdAt == null
        ? ticket.status
        : '${ticket.status} · ${formatShortDateTime(ticket.createdAt!)}';

    return HopCard(
      onTap: () => context.go('/support/${ticket.id}'),
      child: Row(
        children: [
          Icon(
            open
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
            color: accent,
          ),
          SizedBox(width: hoppin.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.subject ?? 'Ticket',
                  style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: hoppin.spacing.xs),
                Text(
                  subtitle,
                  style: hoppin.type.metaSmall.copyWith(color: colors.textMid),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.textMid),
        ],
      ),
    );
  }
}

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet({this.complaint = false});

  final bool complaint;

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String? _typeCode;

  /// The picked category — ALWAYS a value from the single-source taxonomy.
  /// The five-value map that used to live inline here is gone: it is now
  /// [SupportCategories], which Lane 12-02 imports for the legal routes.
  String _category = SupportCategories.general;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final colors = context.hoppin.colors;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      barrierColor: colors.scrim,
      builder: (_) => _CategorySheet(selected: _category),
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty) {
      setState(() => _error = 'Give your ticket a subject.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = _bodyCtrl.text.trim();
      final id = await ref
          .read(supportRepositoryProvider)
          .createTicket(
            subject: subject,
            category: _category,
            typeCode: _typeCode,
            body: body.isEmpty ? null : body,
          );
      ref.invalidate(ticketsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/support/$id');
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final types = ref.watch(complaintTypesProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.complaint ? 'File a complaint' : 'New support ticket',
            style: hoppin.type.section.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.md),
          TextField(
            key: const Key('support.newTicket.subject'),
            controller: _subjectCtrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            style: hoppin.type.body.copyWith(color: colors.textHi),
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          SizedBox(height: hoppin.spacing.sm),
          _CategoryField(
            key: const Key('support.newTicket.category'),
            category: _category,
            onTap: _busy ? null : _pickCategory,
          ),
          if (types.hasValue && types.requireValue.isNotEmpty) ...[
            SizedBox(height: hoppin.spacing.sm),
            _ComplaintTypeField(
              selected: _typeCode,
              types: types.requireValue,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _typeCode = value),
            ),
          ],
          SizedBox(height: hoppin.spacing.sm),
          TextField(
            key: const Key('support.newTicket.body'),
            controller: _bodyCtrl,
            enabled: !_busy,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: hoppin.type.body.copyWith(color: colors.textHi),
            decoration: const InputDecoration(
              // Free text, and it goes to a human. This is where a rider says
              // what outcome they want — which is why there is no picker for
              // it: the endpoint has no field to carry one.
              labelText: 'Describe the problem (optional)',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            SizedBox(height: hoppin.spacing.sm),
            HopBanner.error(message: _error!),
          ],
          SizedBox(height: hoppin.spacing.md),
          HopButton.primary(
            key: const Key('support.newTicket.submit'),
            label: widget.complaint ? 'Submit complaint' : 'Open ticket',
            expand: true,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _ComplaintTypeField extends StatelessWidget {
  const _ComplaintTypeField({
    required this.selected,
    required this.types,
    required this.onChanged,
  });
  final String? selected;
  final List<ComplaintTypeOption> types;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: selected,
    decoration: const InputDecoration(labelText: 'Complaint type'),
    items: [
      const DropdownMenuItem<String>(value: null, child: Text('Select a type')),
      for (final type in types)
        DropdownMenuItem(value: type.code, child: Text(type.label)),
    ],
    onChanged: onChanged,
  );
}

/// The category control — a tappable token-styled field, not a raw dropdown.
/// It reads its label from [SupportCategories]; it never restates one.
class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.category, this.onTap, super.key});

  final String category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(hoppin.radii.input),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Category'),
        child: Row(
          children: [
            Expanded(
              child: Text(
                SupportCategories.labelFor(category),
                style: hoppin.type.body.copyWith(color: colors.textHi),
              ),
            ),
            Icon(Icons.expand_more, color: colors.textMid),
          ],
        ),
      ),
    );
  }
}

/// The category selector sheet. Every row comes from the single-source
/// taxonomy — including the two statutory routes, which sit last because
/// deleting your account should not be one mis-tap away from "General".
class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return HopSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What is it about?',
            style: hoppin.type.section.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.sm),
          for (final value in SupportCategories.values)
            HopListRow(
              icon: _iconFor(value),
              label: SupportCategories.labelFor(value),
              divider: value != SupportCategories.values.last,
              trailing: value == selected
                  ? Icon(Icons.check, color: colors.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(value),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(String value) => switch (value) {
    SupportCategories.fare => Icons.receipt_long_outlined,
    SupportCategories.driver => Icons.person_outline,
    SupportCategories.lostItem => Icons.work_outline,
    SupportCategories.app => Icons.phone_iphone_outlined,
    SupportCategories.accountDeletion => Icons.person_remove_outlined,
    SupportCategories.dataExport => Icons.download_outlined,
    _ => Icons.help_outline,
  };
}
