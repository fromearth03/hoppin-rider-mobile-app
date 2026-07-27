import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../providers.dart';
import '../booking/place.dart';

/// Manage saved places — list / add / delete over `/me/saved-locations`.
class SavedLocationsScreen extends ConsumerWidget {
  const SavedLocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedLocationsProvider);

    final hoppin = context.hoppin;

    return Scaffold(
      backgroundColor: hoppin.colors.canvas,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add place'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Off-shell: no bottom nav, no shell bar. This carried a stock
            // AppBar, whose back arrow only auto-draws when `Navigator.canPop()`
            // is true — and the screen is reached with `context.go`, which
            // REPLACES the route, so there was never anything to pop and the
            // arrow never appeared. `onBack` is never null (null hides it): pop
            // when there is a stack, else fall back to Book.
            HopTopBar(
              title: 'Saved places',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/book'),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(savedLocationsProvider),
                child: saved.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ListView(
                    padding: EdgeInsets.all(hoppin.spacing.gutter),
                    children: [
                      HopBanner.error(message: friendlyErrorMessage(e)),
                    ],
                  ),
                  data: (list) => list.isEmpty
                      ? ListView(
                          padding: EdgeInsets.all(hoppin.spacing.gutter),
                          children: [
                            SizedBox(height: hoppin.spacing.xl),
                            HopEmptyState(
                              headline: 'No saved places yet',
                              supporting: 'Add the spots you use often — home, '
                                  'work, the station.',
                              actionLabel: 'Add a place',
                              onAction: () => _showAddSheet(context, ref),
                            ),
                          ],
                        )
                      : ListView.builder(
                          // The FAB floats over the last row; without a reserve
                          // the bottom entry's delete button sits underneath it
                          // and cannot be pressed.
                          padding: EdgeInsets.only(
                            bottom: hoppin.spacing.xl * 2,
                          ),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final s = list[i];
                            final colors = hoppin.colors;
                            return ListTile(
                              leading: Icon(
                                Icons.star_outline,
                                color: colors.accent,
                              ),
                              title: Text(
                                s.label,
                                style: hoppin.type.bodyMedium
                                    .copyWith(color: colors.textHi),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${s.lat.toStringAsFixed(4)}, '
                                '${s.lng.toStringAsFixed(4)}',
                                style: hoppin.type.metaSmall
                                    .copyWith(color: colors.textMid),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: colors.error,
                                tooltip: 'Delete',
                                onPressed: () => _delete(context, ref, s),
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
    SavedLocation s,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileRepositoryProvider).deleteSavedLocation(s.id);
      ref.invalidate(savedLocationsProvider);
      messenger.showSnackBar(SnackBar(content: Text('Deleted "${s.label}"')));
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) {
    // The same sheet chrome every other rider sheet uses: HopSheet's surface on
    // a transparent host over the token scrim. This one was raising a BARE
    // modal sheet — stock Material fill, stock barrier, square top — so it was
    // the one sheet in the app that did not match the others, and in dark its
    // default surface sat at a different tier than the sheets beside it.
    final colors = context.hoppin.colors;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      barrierColor: colors.scrim,
      builder: (_) => const HopSheet(child: _AddPlaceSheet()),
    );
  }
}

class _AddPlaceSheet extends ConsumerStatefulWidget {
  const _AddPlaceSheet();

  @override
  ConsumerState<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends ConsumerState<_AddPlaceSheet> {
  final _labelCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _usePreset(Place p) {
    _latCtrl.text = p.lat.toString();
    _lngCtrl.text = p.lng.toString();
    if (_labelCtrl.text.trim().isEmpty) _labelCtrl.text = p.label;
    setState(() {});
  }

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (label.isEmpty) {
      setState(() => _error = 'Give this place a name.');
      return;
    }
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      setState(() => _error = 'Enter valid coordinates (or pick a spot).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).addSavedLocation(
            label: label,
            lat: lat,
            lng: lng,
          );
      ref.invalidate(savedLocationsProvider);
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
      // HopSheet supplies the gutter; this only has to lift the content clear
      // of the keyboard. It used to add a second 24pt inset on all four sides
      // on top of the sheet's own, which double-padded the whole form.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a place',
            style: hoppin.type.section.copyWith(color: colors.textHi),
          ),
          SizedBox(height: hoppin.spacing.lg),
          TextField(
            controller: _labelCtrl,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            style: hoppin.type.body.copyWith(color: colors.textHi),
            decoration: const InputDecoration(
              labelText: 'Name (e.g. Home, Work)',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          SizedBox(height: hoppin.spacing.md),
          // Quick-fill from a known spot (until the map picker lands).
          Wrap(
            spacing: hoppin.spacing.sm,
            runSpacing: hoppin.spacing.sm,
            children: [
              for (final p in wolverhamptonPresets)
                ActionChip(
                  label: Text(p.label),
                  onPressed: _busy ? null : () => _usePreset(p),
                ),
            ],
          ),
          SizedBox(height: hoppin.spacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  enabled: !_busy,
                  style: hoppin.type.body.copyWith(color: colors.textHi),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
              ),
              SizedBox(width: hoppin.spacing.md),
              Expanded(
                child: TextField(
                  controller: _lngCtrl,
                  enabled: !_busy,
                  style: hoppin.type.body.copyWith(color: colors.textHi),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            SizedBox(height: hoppin.spacing.md),
            HopBanner.error(message: _error!),
          ],
          SizedBox(height: hoppin.spacing.lg),
          // The design-system button, like every other primary action in the
          // app — it carries its own 52pt height, busy spinner and on-accent
          // tint, so the hand-rolled FilledButton + hand-tinted indicator this
          // replaced had three ways to drift from the rest of the app.
          HopButton.primary(
            label: 'Save place',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
