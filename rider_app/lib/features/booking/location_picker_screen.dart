import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../providers.dart';
import 'place.dart';

/// Map pin location picker. A map fills the top with a fixed centre pin: the
/// rider drags the map under the pin, the settled centre is reverse-geocoded
/// (self-hosted Nominatim, via `GET /geocode/reverse`) to a real address, and
/// "Set this location" returns the chosen [Place]. Saved places and popular
/// spots stay below as one-tap shortcuts. Returns the chosen [Place] via
/// `Navigator.pop`.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({required this.title, super.key});

  final String title;

  /// Pushes the picker on the ROOT navigator so it covers the whole shell, and
  /// resolves to the chosen place (null if dismissed).
  static Future<Place?> pick(BuildContext context, {required String title}) {
    return Navigator.of(context, rootNavigator: true).push<Place>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(title: title),
      ),
    );
  }

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Wolverhampton city centre — the map opens here so the pin lands in-area.
  static const _initialCentre = HopGeoPoint(52.5862, -2.1288);
  HopGeoPoint _centre = _initialCentre;
  String? _label;
  bool _resolving = false;
  bool _follow = true;
  Timer? _debounce;
  int _resolveGen = 0;

  // ── Address autocomplete (GET /geocode/search, fronting Photon) ──────────
  // Separate debounce and generation counter from the reverse-geocode pair
  // above: typing and dragging are independent, and sharing either would let a
  // map drag cancel an in-flight search (or vice versa).
  Timer? _searchDebounce;
  int _searchGen = 0;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Name the initial centre so the confirm bar is never empty on open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve(_centre));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Debounced type-ahead. 300 ms and a two-character floor: every keystroke is
  /// a network round trip otherwise, and the server answers shorter queries
  /// with nothing anyway.
  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();

    final q = value.trim();
    if (q.length < 2) {
      // Bump the generation so a search already in flight cannot land after
      // the box has been cleared and repopulate it.
      _searchGen++;
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce =
        Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final gen = ++_searchGen;
    // Bias results toward where the rider is looking, so "station" ranks the
    // local one first. This biases, never bounds — a cross-country address is
    // still reachable.
    final hits = await ref.read(ridesRepositoryProvider).searchPlaces(
          q,
          lat: _centre.lat,
          lng: _centre.lng,
        );
    // Drop a stale response: the rider has typed again since this went out.
    if (!mounted || gen != _searchGen) return;
    setState(() {
      _suggestions = hits;
      _searching = false;
    });
  }

  void _onCameraIdle(HopGeoPoint centre) {
    _centre = centre;
    // Debounce: the rider may drag several times before settling.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _resolve(centre));
    setState(() => _follow = false);
  }

  Future<void> _resolve(HopGeoPoint p) async {
    final gen = ++_resolveGen;
    setState(() => _resolving = true);
    final res =
        await ref.read(ridesRepositoryProvider).reverseGeocode(p.lat, p.lng);
    if (!mounted || gen != _resolveGen) return;
    setState(() {
      _resolving = false;
      _label = res?.label ??
          'Pinned location (${p.lat.toStringAsFixed(4)}, '
              '${p.lng.toStringAsFixed(4)})';
    });
  }

  void _confirmPin() {
    Navigator.of(context).pop(
      Place(label: _label ?? 'Pinned location', lat: _centre.lat, lng: _centre.lng),
    );
  }

  bool _matches(String label) =>
      _query.isEmpty || label.toLowerCase().contains(_query.toLowerCase());

  /// True once the rider has typed enough for the geocoder to answer. Below the
  /// two-character floor the screen stays in its browse state rather than
  /// flashing an empty result list on the first letter.
  bool get _isSearching => _query.trim().length >= 2;

  /// The address hits, or the empty/pending state that replaces them. Returned
  /// as a list so the caller can spread it straight into the existing ListView.
  List<Widget> _searchResults(HoppinColors colors, HoppinTokens hoppin) {
    if (_suggestions.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: hoppin.spacing.gutter,
            vertical: hoppin.spacing.lg,
          ),
          child: Text(
            _searching
                ? 'Searching…'
                : 'No places match that. Try fewer words, or drag the map to '
                    'drop a pin instead.',
            style: hoppin.type.body.copyWith(color: colors.textMid),
          ),
        ),
      ];
    }
    return [
      const _SectionHeader('Search results'),
      for (var i = 0; i < _suggestions.length; i++) ...[
        if (i > 0) const Divider(height: 1),
        _PlaceRow(
          // A saved place gets the same star it has in the browse list, so the
          // rider recognises their own "Home" among street matches.
          icon: _suggestions[i].isSaved
              ? Icons.star_outline
              : Icons.place_outlined,
          label: _suggestions[i].label,
          trailing: _suggestions[i].postcode,
          onTap: () => Navigator.of(context).pop(
            Place(
              label: _suggestions[i].label,
              // Use the geocoder's coordinates verbatim — re-geocoding the
              // label would round-trip through a second lookup that can resolve
              // somewhere else entirely.
              lat: _suggestions[i].lat,
              lng: _suggestions[i].lng,
            ),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final saved = ref.watch(savedLocationsProvider);
    final presets =
        wolverhamptonPresets.where((p) => _matches(p.label)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          // ── The map + fixed centre pin ─────────────────────────────────
          SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                HopMap(
                  pins: const [],
                  track: null,
                  carPosition: null,
                  carHeading: null,
                  cameraIntent: const FitPoints([_initialCentre]),
                  follow: _follow,
                  interactive: true,
                  onUserGesture: () => setState(() => _follow = false),
                  onCameraIdle: _onCameraIdle,
                ),
                // The fixed centre pin: it never moves; the map moves under it.
                // Offset up by half the glyph so the tip marks the exact centre.
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Icon(
                      Icons.location_on,
                      size: 40,
                      color: colors.accent,
                      shadows: [
                        Shadow(
                          color: colors.scrim.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Resolved address + confirm ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(hoppin.spacing.gutter),
            decoration: BoxDecoration(
              color: colors.card,
              border: Border(bottom: BorderSide(color: colors.hairline)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 18, color: colors.textMid),
                    SizedBox(width: hoppin.spacing.sm),
                    Expanded(
                      child: _resolving && _label == null
                          ? Text(
                              'Finding this spot…',
                              style: hoppin.type.body
                                  .copyWith(color: colors.textMid),
                            )
                          : Text(
                              _label ?? 'Drag the map to place the pin',
                              style: hoppin.type.body
                                  .copyWith(color: colors.textHi),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                    if (_resolving && _label != null)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textMid,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: hoppin.spacing.md),
                HopButton.primary(
                  label: 'Set this location',
                  onPressed: _resolving && _label == null ? null : _confirmPin,
                ),
              ],
            ),
          ),
          // ── Saved + popular shortcuts ──────────────────────────────────
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: hoppin.spacing.sm),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    hoppin.spacing.gutter,
                    hoppin.spacing.sm,
                    hoppin.spacing.gutter,
                    hoppin.spacing.sm,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onQueryChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search for an address or place',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (_query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _onQueryChanged('');
                                  },
                                )),
                    ),
                  ),
                ),
                // While there is a live query, the geocoder owns this list —
                // showing saved/popular underneath a set of address hits reads
                // as two competing answers to the same question.
                if (_isSearching) ..._searchResults(colors, hoppin),
                if (!_isSearching) saved.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (list) {
                    final visible =
                        list.where((s) => _matches(s.label)).toList();
                    if (visible.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionHeader('Saved places'),
                        for (var i = 0; i < visible.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _PlaceRow(
                            icon: Icons.star_outline,
                            label: visible[i].label,
                            onTap: () => Navigator.of(context)
                                .pop(visible[i].toPlace()),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                if (!_isSearching && presets.isNotEmpty) ...[
                  const _SectionHeader('Popular in Wolverhampton'),
                  for (var i = 0; i < presets.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _PlaceRow(
                      icon: Icons.place_outlined,
                      label: presets[i].label,
                      onTap: () => Navigator.of(context).pop(presets[i]),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable result row: quiet glyph, body label.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Optional quiet suffix (a postcode). Absent for most rows.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: hoppin.spacing.gutter,
            vertical: hoppin.spacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.textMid),
              SizedBox(width: hoppin.spacing.md),
              Expanded(
                child: Text(
                  label,
                  style: hoppin.type.body.copyWith(color: colors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: hoppin.spacing.sm),
                Text(
                  trailing!,
                  style: hoppin.type.labelSmall.copyWith(color: colors.textMid),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet micro section header.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        hoppin.spacing.gutter,
        hoppin.spacing.lg,
        hoppin.spacing.gutter,
        hoppin.spacing.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: hoppin.type.labelSmall.copyWith(
          color: hoppin.colors.textMid,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
