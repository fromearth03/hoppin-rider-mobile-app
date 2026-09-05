import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/error_codes.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../core/geo.dart';
import '../../../shared/nav/app_router.dart';
import '../data/saved_locations_repository.dart';
import 'route_entry_screen.dart';
import 'widgets/saved_place_tile.dart';
import 'widgets/saved_place_dialogs.dart';
import '../../../shared/widgets/skeleton.dart';

/// Manage the rider's saved places: list, add, rename, remove.
///
/// The design pack (`From.png`) draws saved places inline on the location
/// picker rather than as their own management screen — the pack has no
/// dedicated "Saved Places" frame, the same way Payment Methods and Personal
/// Information diverge from their booking-step framing into real management
/// screens. This screen is that management surface, built in `From.png`'s
/// visual language (pin-style rows, plain list, minimal chrome).
///
/// `SavedLocation` carries only `id`, `label` and coordinates — there is no
/// separate Home/Work "type" field on the backend. Labelling a place Home or
/// Work is simply naming it that via rename/add; there is no dedicated
/// category control to build, so none is built here.
class SavedPlacesScreen extends ConsumerStatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  ConsumerState<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends ConsumerState<SavedPlacesScreen> {
  bool _loading = true;
  List<SavedLocation> _places = const [];
  String? _errorMessage;

  // Per-row busy state so one row's action can't be double-tapped while its
  // request is in flight, without freezing the rest of the list.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final repo = ref.read(savedLocationsRepositoryProvider);
    final result = await repo.list();
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _places = value;
        case Err(:final error):
          _errorMessage = RiderErrorCopy.messageFor(error);
      }
    });
  }

  Future<void> _confirmRemove(SavedLocation place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this place?'),
        content: Text(
          '"${place.label}" will be removed from your saved places. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.negative),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _removePlace(place);
  }

  Future<void> _removePlace(SavedLocation place) async {
    setState(() => _busyId = place.id);

    final repo = ref.read(savedLocationsRepositoryProvider);
    final result = await repo.remove(place.id);
    if (!mounted) return;

    if (result case Err(:final error)) {
      setState(() {
        _busyId = null;
        _errorMessage = RiderErrorCopy.messageFor(error);
      });
      return;
    }

    setState(() => _busyId = null);
    await _load();
  }

  Future<void> _openRename(SavedLocation place) async {
    final label = await showRenamePlaceDialog(
      context,
      initialLabel: place.label,
    );
    if (label == null || !mounted) return;
    await _renamePlace(place, label);
  }

  Future<void> _renamePlace(SavedLocation place, String label) async {
    setState(() => _busyId = place.id);

    final repo = ref.read(savedLocationsRepositoryProvider);
    final result = await repo.rename(place.id, label);
    if (!mounted) return;

    if (result case Err(:final error)) {
      setState(() {
        _busyId = null;
        _errorMessage = RiderErrorCopy.messageFor(error);
      });
      return;
    }

    setState(() => _busyId = null);
    await _load();
  }

  /// Book a ride using this place as one end. The other end is left blank and
  /// focused in the picker — a saved place is a shortcut into booking, not a
  /// separate destination list the rider has to copy an address out of.
  Future<void> _bookWith(SavedLocation place, {required bool asPickup}) async {
    final point = RoutePoint(place.label, LatLng(place.lat, place.lng));
    context.push(
      AppRoutes.route,
      extra: asPickup
          ? RoutePrefill(pickup: point)
          : RoutePrefill(dropoff: point),
    );
  }

  Future<void> _openActions(SavedLocation place) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        // Scrollable rather than a bare Column: six rows plus a long saved
        // label overflows the default sheet height on a short screen or at a
        // large text scale.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.star, color: AppColors.accent),
                title: Text(place.label),
                subtitle: Text(
                  '${place.lat.toStringAsFixed(5)}, ${place.lng.toStringAsFixed(5)}',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Ride from here'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _bookWith(place, asPickup: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('Ride to here'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _bookWith(place, asPickup: false);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _openRename(place);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.negative,
                ),
                title: const Text('Remove'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _confirmRemove(place);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAdd() async {
    final chosen = await showAddPlaceDialog(context);
    if (chosen == null || !mounted) return;
    await _addPlace(chosen);
  }

  Future<void> _addPlace(ChosenPlace chosen) async {
    final repo = ref.read(savedLocationsRepositoryProvider);
    final result = await repo.add(
      label: chosen.label,
      lat: chosen.lat,
      lng: chosen.lng,
    );
    if (!mounted) return;

    if (result case Err(:final error)) {
      setState(() => _errorMessage = RiderErrorCopy.messageFor(error));
      return;
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Saved Places'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildBody(theme)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _openAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add a place'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const SkeletonList(rows: 4, rowHeight: 68, leadingCircle: true);
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: AppColors.negative,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_places.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 40,
              color: theme.textTheme.bodyMedium?.color,
            ),
            const SizedBox(height: 12),
            Text(
              'No saved places yet',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Save your home, work or anywhere you go often — then book straight from it.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _places.length,
        itemBuilder: (context, index) {
          final place = _places[index];
          final busy = _busyId == place.id;
          return SavedPlaceTile(
            place: place,
            onTap: busy ? null : () => _openActions(place),
            onRename: busy ? null : () => _openRename(place),
            onRemove: busy ? null : () => _confirmRemove(place),
          );
        },
      ),
    );
  }
}
