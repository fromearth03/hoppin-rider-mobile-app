import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/api/error_codes.dart';
import '../../../../core/result.dart';
import '../../../../core/theme/colors.dart';
import '../../data/places_repository.dart';

/// A place the rider picked from search, ready to be named and saved.
class ChosenPlace {
  final String label;
  final double lat;
  final double lng;

  const ChosenPlace({required this.label, required this.lat, required this.lng});
}

/// Prompts for a new label on an existing place. Returns the trimmed label,
/// or null if the rider cancelled.
Future<String?> showRenamePlaceDialog(
  BuildContext context, {
  required String initialLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RenameDialog(initialLabel: initialLabel),
  );
}

class _RenameDialog extends StatefulWidget {
  final String initialLabel;
  const _RenameDialog({required this.initialLabel});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialLabel);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename this place'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Label'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final label = _controller.text.trim();
            Navigator.of(context).pop(label.isEmpty ? null : label);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Search-and-name flow for adding a saved place. Coordinates come from a
/// real search result — the repository requires lat/lng, and inventing a
/// coordinate for a typed label would silently save the wrong place. Returns
/// null if the rider cancelled.
Future<ChosenPlace?> showAddPlaceDialog(BuildContext context) {
  return showDialog<ChosenPlace>(
    context: context,
    builder: (context) => const _AddPlaceDialog(),
  );
}

class _AddPlaceDialog extends ConsumerStatefulWidget {
  const _AddPlaceDialog();

  @override
  ConsumerState<_AddPlaceDialog> createState() => _AddPlaceDialogState();
}

class _AddPlaceDialogState extends ConsumerState<_AddPlaceDialog> {
  final _search = TextEditingController();
  final _label = TextEditingController();

  Timer? _debounce;
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  ApiException? _searchError;
  PlaceSuggestion? _chosen;
  String? _saveError;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _label.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    setState(() => _chosen = null);
    if (query.trim().length < kMinQueryLength) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 250), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);

    final result = await ref.read(placesRepositoryProvider).search(query);
    if (!mounted) return;

    setState(() {
      _searching = false;
      switch (result) {
        case Ok(:final value):
          _results = value;
          _searchError = null;
        case Err(:final error):
          _results = const [];
          _searchError = error;
      }
    });
  }

  void _choose(PlaceSuggestion place) {
    setState(() {
      _chosen = place;
      _results = const [];
      _label.text = place.label;
    });
  }

  void _save() {
    final chosen = _chosen;
    if (chosen == null) return;
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _saveError = 'Give this place a name.');
      return;
    }
    Navigator.of(context)
        .pop(ChosenPlace(label: label, lat: chosen.lat, lng: chosen.lng));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = _chosen;

    return AlertDialog(
      title: const Text('Add a place'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Search for a place',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            _resultsArea(theme),
            if (chosen != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Save as'),
              ),
            ],
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Text(_saveError!, style: const TextStyle(color: AppColors.negative)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: chosen == null ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _resultsArea(ThemeData theme) {
    if (_chosen != null) return const SizedBox.shrink();

    if (_searchError != null) {
      return Text(
        RiderErrorCopy.messageFor(_searchError!),
        style: const TextStyle(color: AppColors.negative),
      );
    }
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_results.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final result = _results[index];
          return ListTile(
            dense: true,
            leading: Icon(
              result.isSaved ? Icons.star_outline : Icons.location_on_outlined,
              color: result.isSaved ? AppColors.accent : null,
            ),
            title: Text(result.label, overflow: TextOverflow.ellipsis),
            subtitle: result.postcode == null ? null : Text(result.postcode!),
            onTap: () => _choose(result),
          );
        },
      ),
    );
  }
}
