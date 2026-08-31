import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/geo.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/places_repository.dart';

/// One chosen point on the trip.
class RoutePoint {
  final String label;
  final LatLng position;
  const RoutePoint(this.label, this.position);
}

/// The route the rider assembled: pickup, optional stops, dropoff.
class ChosenRoute {
  final RoutePoint pickup;
  final RoutePoint dropoff;
  final List<RoutePoint> stops;

  const ChosenRoute({
    required this.pickup,
    required this.dropoff,
    this.stops = const [],
  });
}

/// Where to, and via where.
///
/// The design shows Suggestion and Saved as tabs. They are one response
/// filtered two ways, not two calls: `/geocode/search` returns `source` on
/// every row and already ranks saved places first.
class RouteEntryScreen extends ConsumerStatefulWidget {
  const RouteEntryScreen({super.key});

  @override
  ConsumerState<RouteEntryScreen> createState() => _RouteEntryScreenState();
}

class _RouteEntryScreenState extends ConsumerState<RouteEntryScreen> {
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _stops = <TextEditingController>[];

  /// Which field the suggestions currently apply to: 0 = pickup, 1 = dropoff,
  /// 2+ = the stop at index (n - 2).
  int _activeField = 1;
  bool _savedOnly = false;

  Timer? _debounce;
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  ApiException? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _pickup.dispose();
    _dropoff.dispose();
    for (final c in _stops) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    // The server answers an empty list below two characters, so there is
    // nothing to fetch - but the field should still clear as the rider deletes.
    if (query.trim().length < kMinQueryLength) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    // A request per keystroke would be one per 40ms of typing.
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);

    // No position is passed: location permission is not wired yet, and the
    // repository omits the parameters rather than sending zeroes, which would
    // bias every search toward a point in the Atlantic.
    final result = await ref.read(placesRepositoryProvider).search(query);
    if (!mounted) return;

    setState(() {
      _searching = false;
      switch (result) {
        case Ok(:final value):
          _results = value;
          _error = null;
        case Err(:final error):
          _results = const [];
          _error = error;
      }
    });
  }

  void _choose(PlaceSuggestion place) {
    final controller = switch (_activeField) {
      0 => _pickup,
      1 => _dropoff,
      _ => _stops[_activeField - 2],
    };
    controller.text = place.label;
    setState(() => _results = const []);
    FocusScope.of(context).unfocus();
  }

  void _addStop() {
    if (_stops.length >= kMaxWaypoints) return;
    setState(() => _stops.add(TextEditingController()));
  }

  void _removeStop(int i) {
    setState(() {
      _stops.removeAt(i).dispose();
      if (_activeField >= 2) _activeField = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _savedOnly
        ? _results.where((p) => p.isSaved).toList(growable: false)
        : _results;

    return Scaffold(
      appBar: AppBar(title: const Text('Enter Your Route')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                _Field(
                  controller: _pickup,
                  hint: 'Active Location',
                  icon: Icons.my_location,
                  onTap: () => setState(() => _activeField = 0),
                  onChanged: _onChanged,
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < _stops.length; i++) ...[
                  _Field(
                    controller: _stops[i],
                    hint: 'Stop ${i + 1}',
                    icon: Icons.circle_outlined,
                    onTap: () => setState(() => _activeField = i + 2),
                    onChanged: _onChanged,
                    onRemove: () => _removeStop(i),
                  ),
                  const SizedBox(height: 10),
                ],
                _Field(
                  controller: _dropoff,
                  hint: 'To',
                  icon: Icons.place_outlined,
                  onTap: () => setState(() => _activeField = 1),
                  onChanged: _onChanged,
                  // The design puts a + on the destination field. The cap is
                  // five, enforced when quoting as well as when booking.
                  onAdd: _stops.length < kMaxWaypoints ? _addStop : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const SizedBox(width: 16),
              _Chip(
                label: 'Suggestion',
                selected: !_savedOnly,
                onTap: () => setState(() => _savedOnly = false),
              ),
              const SizedBox(width: 8),
              _Chip(
                label: 'Saved',
                selected: _savedOnly,
                onTap: () => setState(() => _savedOnly = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _results_(theme, visible)),
        ],
      ),
    );
  }

  Widget _results_(ThemeData theme, List<PlaceSuggestion> visible) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            RiderErrorCopy.messageFor(_error!),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.negative),
          ),
        ),
      );
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            // Deliberately not "that place doesn't exist": when the geocoder
            // is unreachable the server returns saved places alone, silently,
            // so an empty list cannot distinguish the two.
            _savedOnly
                ? 'No saved places match.'
                : 'Start typing to search for a place.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final p = visible[i];
        return ListTile(
          leading: Icon(
            p.isSaved ? Icons.star_outline : Icons.location_on_outlined,
            color: p.isSaved ? AppColors.accent : null,
          ),
          title: Text(p.label, overflow: TextOverflow.ellipsis),
          subtitle: p.postcode == null ? null : Text(p.postcode!),
          onTap: () => _choose(p),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onTap,
    required this.onChanged,
    this.onAdd,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onTap: onTap,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: switch ((onAdd, onRemove)) {
          (final add?, _) => IconButton(
              onPressed: add,
              icon: const Icon(Icons.add),
              tooltip: 'Add a stop'),
          (_, final remove?) => IconButton(
              onPressed: remove,
              icon: const Icon(Icons.close),
              tooltip: 'Remove this stop'),
          _ => null,
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primaryDark : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : theme.textTheme.bodyLarge?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
