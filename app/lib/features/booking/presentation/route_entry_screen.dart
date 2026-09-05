import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../../core/api/api_exception.dart';
import '../../../core/api/error_codes.dart';
import '../../../core/geo.dart';
import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_drawer.dart';
import '../../../shared/nav/app_router.dart';
import '../../../shared/widgets/collapsible_sheet.dart';
import '../data/places_repository.dart';
import 'home_screen.dart' show MapCircleButton;
import 'widgets/map_markers.dart';
import 'widgets/rider_map.dart';

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

/// ONE end of a trip, known up front — booking from (or to) a saved place,
/// where the other end is still the rider's to choose.
///
/// Distinct from [ChosenRoute], which is a complete route being re-edited: a
/// prefill leaves the opposite field blank and focused, so the rider lands in
/// the picker already typing the half that is actually missing.
class RoutePrefill {
  final RoutePoint? pickup;
  final RoutePoint? dropoff;
  const RoutePrefill({this.pickup, this.dropoff});
}

/// Where to, and via where — a collapsible sheet over the FULL live map.
///
/// The design shows Suggestion and Saved as tabs. They are one response
/// filtered two ways, not two calls: `/geocode/search` returns `source` on
/// every row and already ranks saved places first.
///
/// The map is a first-class input here, not a backdrop: collapse the sheet
/// and TAP the map to fill the active field (reverse-geocoded), and every
/// chosen point pins itself (A / 1 / 2 / B) with the camera following.
class RouteEntryScreen extends ConsumerStatefulWidget {
  /// When true, confirming POPS with the [ChosenRoute] as the result instead
  /// of pushing fare-confirm — for callers (scheduling) that need a route
  /// picked but own what happens next themselves.
  final bool pickMode;

  /// A route to EDIT: both ends (and stops) arrive filled in, so re-opening
  /// the picker from a form that already holds a route never restarts the
  /// rider from blank fields.
  final ChosenRoute? initial;

  /// Only one end known — see [RoutePrefill]. Ignored when [initial] is set,
  /// which already fills both.
  final RoutePrefill? prefill;

  const RouteEntryScreen(
      {super.key, this.pickMode = false, this.initial, this.prefill});

  @override
  ConsumerState<RouteEntryScreen> createState() => _RouteEntryScreenState();
}

class _RouteEntryScreenState extends ConsumerState<RouteEntryScreen> {
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _stops = <TextEditingController>[];

  /// The geocoded place behind each field, or null once the rider edits the
  /// text — typed text is a query, not a place, and booking it would send
  /// stale coordinates under a fresh label.
  RoutePoint? _pickupPoint;
  RoutePoint? _dropoffPoint;
  final Map<int, RoutePoint> _stopPoints = {};

  /// Which field the suggestions currently apply to: 0 = pickup, 1 = dropoff,
  /// 2+ = the stop at index (n - 2).
  int _activeField = 1;
  bool _savedOnly = false;

  Timer? _debounce;
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  ApiException? _error;

  RiderMapController? _map;
  Set<gmaps.Marker> _markers = const {};

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _pickup.text = init.pickup.label;
      _pickupPoint = init.pickup;
      _dropoff.text = init.dropoff.label;
      _dropoffPoint = init.dropoff;
      for (final stop in init.stops) {
        _stops.add(TextEditingController(text: stop.label));
        _stopPoints[_stops.length - 1] = stop;
      }
      _refreshMarkers();
      return;
    }
    final pre = widget.prefill;
    if (pre != null) {
      if (pre.pickup != null) {
        _pickup.text = pre.pickup!.label;
        _pickupPoint = pre.pickup;
      }
      if (pre.dropoff != null) {
        _dropoff.text = pre.dropoff!.label;
        _dropoffPoint = pre.dropoff;
      }
      // Point the search at the end that is still empty, so the rider's first
      // keystroke fills the missing half rather than overwriting the place
      // they just chose.
      _activeField = pre.pickup != null ? 1 : 0;
      _refreshMarkers();
    }
  }

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
    setState(() {
      switch (_activeField) {
        case 0:
          _pickupPoint = null;
        case 1:
          _dropoffPoint = null;
        default:
          _stopPoints.remove(_activeField - 2);
      }
    });
    _refreshMarkers();
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
    final point = RoutePoint(place.label, place.position);
    switch (_activeField) {
      case 0:
        _pickup.text = place.label;
        _pickupPoint = point;
      case 1:
        _dropoff.text = place.label;
        _dropoffPoint = point;
      default:
        _stops[_activeField - 2].text = place.label;
        _stopPoints[_activeField - 2] = point;
    }
    setState(() => _results = const []);
    FocusScope.of(context).unfocus();
    // The map follows what the rider just chose.
    _map?.moveTo(gmaps.CameraPosition(
      target: gmaps.LatLng(point.position.lat, point.position.lng),
      zoom: 15,
    ));
    _refreshMarkers();
  }

  /// Map tap → reverse geocode → the ACTIVE field. The map is an input.
  Future<void> _onMapTap(gmaps.LatLng position) async {
    final result = await ref
        .read(placesRepositoryProvider)
        .reverse(position.latitude, position.longitude);
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        _choose(value);
      case Err(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RiderErrorCopy.messageFor(error))),
        );
    }
  }

  /// Pickup A (blue), stops numbered (orange), dropoff B (green) — pinned as
  /// they are chosen, cleared as they are edited away.
  Future<void> _refreshMarkers() async {
    if (!RiderMap.mapSupported) return;
    final markers = <gmaps.Marker>{};
    final pickup = _pickupPoint;
    if (pickup != null) {
      markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId('pickup'),
        position:
            gmaps.LatLng(pickup.position.lat, pickup.position.lng),
        icon: await circleLabelMarker('A', AppColors.info),
        infoWindow: gmaps.InfoWindow(title: pickup.label),
      ));
    }
    for (final entry in _stopPoints.entries) {
      markers.add(gmaps.Marker(
        markerId: gmaps.MarkerId('stop${entry.key + 1}'),
        position: gmaps.LatLng(
            entry.value.position.lat, entry.value.position.lng),
        icon: await circleLabelMarker('${entry.key + 1}', AppColors.accent),
        infoWindow: gmaps.InfoWindow(
            title: 'Stop ${entry.key + 1} — ${entry.value.label}'),
      ));
    }
    final dropoff = _dropoffPoint;
    if (dropoff != null) {
      markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId('dropoff'),
        position:
            gmaps.LatLng(dropoff.position.lat, dropoff.position.lng),
        icon: await circleLabelMarker('B', AppColors.positive),
        infoWindow: gmaps.InfoWindow(title: dropoff.label),
      ));
    }
    if (mounted) setState(() => _markers = markers);
  }

  bool get _routeComplete =>
      _pickupPoint != null &&
      _dropoffPoint != null &&
      List.generate(_stops.length, (i) => i).every(_stopPoints.containsKey);

  void _confirm() {
    final route = ChosenRoute(
      pickup: _pickupPoint!,
      dropoff: _dropoffPoint!,
      stops: [for (var i = 0; i < _stops.length; i++) _stopPoints[i]!],
    );
    if (widget.pickMode) {
      context.pop(route);
      return;
    }
    context.push(AppRoutes.fareConfirm, extra: route);
  }

  void _addStop() {
    if (_stops.length >= kMaxWaypoints) return;
    setState(() => _stops.add(TextEditingController()));
  }

  void _removeStop(int i) {
    setState(() {
      _stops.removeAt(i).dispose();
      // Shift the chosen points above the removed stop down one slot so
      // they stay attached to the fields they were picked for.
      _stopPoints.remove(i);
      final shifted = <int, RoutePoint>{
        for (final entry in _stopPoints.entries)
          entry.key > i ? entry.key - 1 : entry.key: entry.value,
      };
      _stopPoints
        ..clear()
        ..addAll(shifted);
      if (_activeField >= 2) _activeField = 1;
    });
    _refreshMarkers();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _savedOnly
        ? _results.where((p) => p.isSaved).toList(growable: false)
        : _results;

    final topInset = MediaQuery.of(context).padding.top;

    // The FULL live map behind a collapsible sheet: collapse to see and TAP
    // the map, expand to type. Drags on the sheet never reach the map.
    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: RiderMap(
              markers: _markers,
              onMapCreated: (c) => _map = c,
              onTap: _onMapTap,
            ),
          ),
          Positioned(
            top: topInset + 12,
            left: 16,
            child: Builder(
              builder: (context) => MapCircleButton(
                icon: Icons.menu,
                onTap: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ),
          CollapsibleSheet(
            title: 'Enter Your Route',
            onClose: () => Navigator.of(context).maybePop(),
            initialSize: 0.72,
            children: [
              const SizedBox(height: 4),
              _Field(
                controller: _pickup,
                hint: 'Active Location',
                icon: Icons.location_on,
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
                icon: Icons.search,
                onTap: () => setState(() => _activeField = 1),
                onChanged: _onChanged,
                // The design puts a + on the destination field. The cap is
                // five, enforced when quoting and booking.
                onAdd: _stops.length < kMaxWaypoints ? _addStop : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
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
              const SizedBox(height: 6),
              // A quiet nudge that the map itself is an input.
              Text(
                'Tip: pull this panel down and tap the map to drop a point.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
              ),
              const SizedBox(height: 4),
              ..._resultRows(theme, visible),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FilledButton(
          onPressed: _routeComplete ? _confirm : null,
          child: const Text('Confirm Route'),
        ),
      ),
    );
  }

  List<Widget> _resultRows(ThemeData theme, List<PlaceSuggestion> visible) {
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            RiderErrorCopy.messageFor(_error!),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.negative),
          ),
        ),
      ];
    }
    if (_searching) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (visible.isEmpty) {
      return [
        Padding(
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
      ];
    }

    return [
      for (final p in visible.take(25))
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            p.isSaved ? Icons.star_outline : Icons.location_on_outlined,
            color: p.isSaved ? AppColors.accent : null,
          ),
          title: Text(p.label, overflow: TextOverflow.ellipsis),
          subtitle: p.postcode == null ? null : Text(p.postcode!),
          onTap: () => _choose(p),
        ),
    ];
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
    // The frame draws each field as a white card with a hairline border and
    // soft shadow on the light sheet.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: controller,
        onTap: onTap,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8E8EC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.navy, width: 1.2),
          ),
          prefixIcon: Icon(icon,
              size: 20,
              color: icon == Icons.location_on
                  ? AppColors.navy
                  : AppColors.lightTextSecondary),
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
    // Selected chip fills the design's navy; the unselected one is a plain
    // white pill — exactly as the frame draws Suggestion/Saved.
    return Material(
      color: selected ? AppColors.navy : Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: selected ? 0 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
