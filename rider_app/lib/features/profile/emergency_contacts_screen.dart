import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// My emergency contacts — `GET /me/emergency-contacts`.
final emergencyContactsProvider =
    FutureProvider.autoDispose<List<EmergencyContact>>((ref) {
  return ref.watch(profileRepositoryProvider).emergencyContacts();
});

/// Manage emergency contacts. With auto-share on, the platform can share
/// night-trip details with the contact.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(emergencyContactsProvider);

    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      floatingActionButton: FloatingActionButton.extended(
        // Same sheet chrome as every other rider sheet — this one was raising a
        // bare modal with the stock Material surface and barrier.
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: colors.scrim,
          builder: (_) => const HopSheet(child: _AddContactSheet()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add contact'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Off-shell: no bottom nav, no shell bar. The stock AppBar this used
            // to carry only auto-draws its back arrow when `Navigator.canPop()`
            // is true, and the screen is reached with `context.go` — which
            // REPLACES the route, so there was nothing to pop and no arrow ever
            // rendered. `onBack` is never null (null hides the button): pop when
            // there is a stack, else return to the account surface this lives
            // under.
            HopTopBar(
              title: 'Emergency contacts',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(emergencyContactsProvider),
                child: contacts.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ListView(
                    padding: EdgeInsets.all(hoppin.spacing.gutter),
                    children: [
                      StatusBanner.error(message: friendlyErrorMessage(e)),
                    ],
                  ),
                  data: (list) => list.isEmpty
                      ? ListView(
                          padding: EdgeInsets.all(hoppin.spacing.gutter),
                          children: [
                            SizedBox(height: hoppin.spacing.xl),
                            // The designed empty state, like every other empty
                            // surface in the app. This was a hand-rolled
                            // icon-over-paragraph whose glyph and copy both sat
                            // on raw ColorScheme roles rather than tokens — the
                            // only empty state in the rider app that did not
                            // speak the system's language.
                            const HopEmptyState(
                              headline: 'No emergency contacts yet',
                              supporting:
                                  'Add someone you trust — they can be looped '
                                  'in on night trips.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          // Reserve for the extended FAB, which otherwise
                          // floats over the last row's delete button.
                          padding: EdgeInsets.only(
                            bottom: hoppin.spacing.xl * 2,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final c = list[i];
                            return ListTile(
                              leading: Icon(
                                Icons.contact_phone_outlined,
                                color: colors.accent,
                              ),
                              title: Text(
                                c.contactName,
                                style: hoppin.type.bodyMedium
                                    .copyWith(color: colors.textHi),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  c.phoneNumber,
                                  if (c.relationship != null) c.relationship!,
                                  if (c.autoShareNightTrips)
                                    'night-trip sharing on',
                                ].join(' · '),
                                style: hoppin.type.metaSmall
                                    .copyWith(color: colors.textMid),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: colors.error,
                                tooltip: 'Delete',
                                onPressed: () => _delete(context, ref, c),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    EmergencyContact c,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileRepositoryProvider).deleteEmergencyContact(c.id);
      ref.invalidate(emergencyContactsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Removed ${c.contactName}')),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }
}

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet();

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _relationshipCtrl = TextEditingController();
  bool _autoShare = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _relationshipCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Name and phone number are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).addEmergencyContact(
            contactName: name,
            phoneNumber: phone,
            relationship: _relationshipCtrl.text.trim(),
            autoShareNightTrips: _autoShare,
          );
      ref.invalidate(emergencyContactsProvider);
      if (mounted) Navigator.of(context).pop();
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
    return Padding(
      // HopSheet already supplies the gutter; this only lifts the form clear of
      // the keyboard. The old 24pt-on-all-sides inset double-padded the sheet.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add emergency contact',
            style: hoppin.type.section.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.lg),
          TextField(
            controller: _nameCtrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            style: hoppin.type.body.copyWith(color: colors.textHi),
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          SizedBox(height: hoppin.spacing.md),
          TextField(
            controller: _phoneCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            style: hoppin.type.body.copyWith(color: colors.textHi),
            decoration: const InputDecoration(
              labelText: 'Phone number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          SizedBox(height: hoppin.spacing.md),
          TextField(
            controller: _relationshipCtrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            style: hoppin.type.body.copyWith(color: colors.textHi),
            decoration: const InputDecoration(
              labelText: 'Relationship (optional)',
              prefixIcon: Icon(Icons.group_outlined),
            ),
          ),
          SizedBox(height: hoppin.spacing.xs),
          SwitchListTile(
            value: _autoShare,
            onChanged: _busy ? null : (v) => setState(() => _autoShare = v),
            title: Text(
              'Share night trips automatically',
              style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
            ),
            subtitle: Text(
              'Trip details can be shared with this contact on night rides',
              style: hoppin.type.metaSmall.copyWith(color: colors.textMid),
            ),
            activeThumbColor: colors.onAccent,
            activeTrackColor: colors.accent,
            contentPadding: EdgeInsets.zero,
          ),
          if (_error != null) ...[
            SizedBox(height: hoppin.spacing.sm),
            StatusBanner.error(message: _error!),
          ],
          SizedBox(height: hoppin.spacing.md),
          // The design-system primary, matching every other save action.
          HopButton.primary(
            label: 'Save contact',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
