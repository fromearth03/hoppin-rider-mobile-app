import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_status.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../../core/theme/colors.dart';
import 'google_maps_probe_stub.dart'
    if (dart.library.js_interop) 'google_maps_probe_web.dart';
import 'map_placeholder.dart';

/// Camera control that works over whichever engine actually rendered.
///
/// Callers never see GoogleMapController vs flutter_map's MapController —
/// they ask for a camera position or a bounds fit and the wrapper routes it.
class RiderMapController {
  final GoogleMapController? _google;
  final fmap.MapController? _osm;

  const RiderMapController._google(GoogleMapController this._google)
      : _osm = null;
  const RiderMapController._osm(fmap.MapController this._osm) : _google = null;

  void moveTo(CameraPosition position) {
    _google?.animateCamera(CameraUpdate.newCameraPosition(position));
    _osm?.move(
      ll.LatLng(position.target.latitude, position.target.longitude),
      position.zoom,
    );
  }

  void fitBounds(LatLngBounds bounds, double padding) {
    _google?.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    _osm?.fitCamera(fmap.CameraFit.bounds(
      bounds: fmap.LatLngBounds(
        ll.LatLng(bounds.southwest.latitude, bounds.southwest.longitude),
        ll.LatLng(bounds.northeast.latitude, bounds.northeast.longitude),
      ),
      padding: EdgeInsets.all(padding),
    ));
  }
}

/// The map surface every map-shaped screen shares.
///
/// Google Maps first — the native SDK on Android/iOS, the JS SDK on web.
/// When the JS SDK never materialises on web (bad key, billing-blocked
/// account, blocked CDN), the surface falls back to the SAME self-hosted map
/// stack the admin panel renders with MapLibre: plain OSM raster tiles.
/// Desktop targets and widget tests still get the honest [MapPlaceholder].
///
/// The platform check uses `dart:io`'s [Platform], not `defaultTargetPlatform`:
/// widget tests run on the host OS and must get the placeholder, and
/// `defaultTargetPlatform` lies to them (it reports android inside
/// `flutter_test`).
class RiderMap extends ConsumerStatefulWidget {
  /// Where the camera starts until a live position is known. Hoppin's launch
  /// city is Wolverhampton; its centre is the least-wrong default — the same
  /// centre the admin live map uses.
  static const CameraPosition initialCamera = CameraPosition(
    target: LatLng(52.5862, -2.1288),
    zoom: 13.5,
  );

  /// Camera override for screens that centre elsewhere (a route, a driver).
  final CameraPosition? camera;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final void Function(RiderMapController controller)? onMapCreated;

  /// Tap on the map itself — route entry uses it to pick a point directly.
  final void Function(LatLng position)? onTap;

  /// Keeps the engine's own chrome (logo, attribution) clear of a bottom
  /// sheet.
  final EdgeInsets padding;

  /// Draw the rider's own position. Only pass true once runtime location
  /// permission is actually GRANTED — the platform layer assumes it and the
  /// caller owns the asking (see LocationPermissionService).
  final bool showMyLocation;

  const RiderMap({
    super.key,
    this.camera,
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.showMyLocation = false,
  });

  static bool get mapSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  ConsumerState<RiderMap> createState() => _RiderMapState();
}

class _RiderMapState extends ConsumerState<RiderMap> {
  /// Which engine to prefer. `auto` probes Google and falls back; `osm`
  /// forces the self-hosted-stack tiles (the current web default — the
  /// Google JS plugin crashes in-browser: IntersectionObserver TypeError
  /// from maps' own main.js); `google` forces Google.
  static const _engine =
      String.fromEnvironment('MAPS_ENGINE', defaultValue: 'auto');

  /// null = still deciding (the JS script may not have finished loading when
  /// the first frame builds); true = Google; false = OSM fallback.
  bool? _useGoogle;
  Timer? _probe;

  /// Auto: set only once Google's rendered pixels prove it drew a REAL map.
  /// Until that happens the guarantee timer below forces OSM, so a grey field, a
  /// snapshot that never returns, or an onMapCreated that never fires can never
  /// leave the map stuck on grey.
  bool _googleConfirmed = false;
  Timer? _nativeDeadline;

  /// Auto-mode OSM health, from fetching one real tile: lets the resolver know
  /// whether the fallback can actually draw. null = not yet known.
  bool? _osmHealthy;

  @override
  void initState() {
    super.initState();
    if (!RiderMap.mapSupported) return;
    if (_engine == 'osm') {
      _useGoogle = false;
      return;
    }
    if (_engine == 'google') {
      _useGoogle = true;
      return;
    }
    if (!kIsWeb) {
      // Native binds the Maps SDK at build time, so there is no script to probe
      // — this used to `return` here and native was simply ASSUMED to work. It
      // is not: a missing or unauthorised API key, a disabled Maps SDK for
      // Android, or an exhausted quota all render a grey tile field.
      //
      // onMapCreated is NOT a usable health signal on its own. When the SDK
      // fails authorisation it still constructs the view and still hands back a
      // controller — the map is grey but every callback fires normally. A
      // deadline on onMapCreated therefore misses precisely the failure we care
      // about.
      //
      // So ask something that actually answers: the Maps HTTP API, with the
      // same key the SDK uses. A key that cannot geocode is a key that cannot
      // draw tiles, and a project with Maps disabled fails both. The deadline
      // stays as a second net for the case where the SDK never comes up at all.
      _useGoogle = true;
      // ABSOLUTE GUARANTEE. This is a Timer, so no hung snapshot or blocked
      // await can stop it firing. Within this window auto MUST show a working
      // map: unless Google has been positively confirmed as drawing a real map,
      // force OSM. This one line is what makes the fallback impossible to skip —
      // it catches a grey field, a takeSnapshot that never returns, and an
      // onMapCreated that never fires, all the same. It is cancelled ONLY by a
      // confirmed-real-map snapshot, never by onMapCreated (which fires on grey).
      _nativeDeadline = Timer(const Duration(seconds: 9), () {
        if (mounted && !_googleConfirmed && _useGoogle != false) {
          setState(() => _useGoogle = false);
        }
      });
      // Resolve both engines' health in parallel: Google via its snapshot (in
      // onMapCreated -> _checkGoogleThenResolve), OSM via a real tile fetch now.
      unawaited(_probeOsm());
      unawaited(_verifyGoogleUsable());
      return;
    }
    if (googleMapsJsLoaded()) {
      _useGoogle = true;
      return;
    }
    // The script tag is async: give it a moment before writing Google off.
    var attempts = 0;
    _probe = Timer.periodic(const Duration(milliseconds: 400), (t) {
      attempts++;
      if (googleMapsJsLoaded()) {
        t.cancel();
        setState(() => _useGoogle = true);
      } else if (attempts >= 6) {
        t.cancel();
        setState(() => _useGoogle = false);
      }
    });
  }

  /// Ask Google whether this key still works, and drop to the fallback if not.
  ///
  /// Cheap (one small JSON call, once per map mount) and decisive: Google
  /// answers REQUEST_DENIED for a disabled API, an unauthorised key or a
  /// billing problem, which are the states that leave the SDK drawing grey.
  /// Anything else — including a network failure — is left alone, because a
  /// flaky connection is not a reason to abandon the better renderer.
  Future<void> _verifyGoogleUsable() async {
    if (_mapsApiKey.isEmpty) return;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': 'London',
        'key': _mapsApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final status = (jsonDecode(res.body) as Map)['status'];
      if (status == 'REQUEST_DENIED' || status == 'OVER_QUERY_LIMIT') {
        if (mounted) {
          _nativeDeadline?.cancel();
          setState(() => _useGoogle = false);
        }
      }
    } catch (_) {
      // Network trouble says nothing about the key. Keep Google.
    }
  }

  /// Auto's engine resolver: prove which renderer actually works and show it,
  /// preferring Google for quality.
  ///
  /// The app cannot tell Google is broken from any callback. The real cause on
  /// this project is that the Cloud key GEOCODES fine (status OK) but its
  /// "Maps SDK for Android" is not activated, so the SDK still returns a healthy
  /// controller and fires onMapCreated while drawing a grey field. The geocode
  /// probe above needs MAPS_API_KEY, which this build does not set, so it never
  /// runs either. So judge the only honest witnesses: Google from its rendered
  /// pixels, OSM from a real tile fetch. Pick the winner:
  ///   Google draws a real map     -> Google
  ///   Google grey, OSM reachable  -> OSM
  ///   Google grey, OSM also down  -> OSM (self-hosted, most likely to recover;
  ///                                  still draws markers, routes and taps)
  /// Because Google is ALWAYS checked directly, the reverse holds for free: if
  /// OSM is the broken one and Google works, auto keeps Google. Two snapshot
  /// attempts so a real map that is merely slow to tile is not misjudged.
  Future<void> _checkGoogleThenResolve(GoogleMapController c) async {
    for (final wait in const [Duration(seconds: 2), Duration(seconds: 3)]) {
      await Future<void>.delayed(wait);
      if (!mounted || _useGoogle != true) return;
      Uint8List? bytes;
      try {
        // NEVER await the snapshot unguarded. On a broken / unauthorised Google
        // map the snapshot callback can simply never fire, and a bare await would
        // hang here forever — which is exactly why auto used to sit on grey. The
        // timeout turns a hang into "could not confirm Google", and the guarantee
        // timer above is the final backstop if even this is somehow blocked.
        bytes = await c.takeSnapshot().timeout(const Duration(seconds: 3));
      } catch (_) {
        bytes = null; // timed out / threw -> treat as not-drawing
      }
      if (bytes != null && await _looksLikeRealMap(bytes)) {
        _googleConfirmed = true; // proven real -> keep Google, disarm the timer
        _nativeDeadline?.cancel();
        return;
      }
    }
    await _resolveToOsm();
  }

  /// Google is confirmed not-drawing: settle on OSM. Waits briefly for the tile
  /// probe if it is still in flight (only to record health / choose a fallback),
  /// then switches. OSM is the least-bad surface once Google is grey, so we
  /// switch whether or not its tiles are reachable — an unreachable tile server
  /// may recover, and the map still functions for markers and taps meanwhile.
  Future<void> _resolveToOsm() async {
    var waited = 0;
    while (_osmHealthy == null && waited < 6000) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      waited += 300;
    }
    if (mounted && _useGoogle != false) {
      _nativeDeadline?.cancel();
      setState(() => _useGoogle = false);
    }
  }

  /// Health-check the OSM fallback the way the app will actually use it: fetch
  /// one real tile from the configured tile server for the launch centre. Sets
  /// [_osmHealthy]. This is the other half of a bidirectional auto — we must
  /// know OSM can draw before leaning on it, and (via [_googleHealthy]) never
  /// sit on empty OSM tiles when Google is the one that works.
  Future<void> _probeOsm() async {
    try {
      const z = 13;
      final lat = RiderMap.initialCamera.target.latitude;
      final lon = RiderMap.initialCamera.target.longitude;
      const n = 1 << z;
      final x = ((lon + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
      final latRad = lat * math.pi / 180.0;
      final y = ((1 -
                  math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
              2 *
              n)
          .floor()
          .clamp(0, n - 1);
      final url = _tileUrl
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      _osmHealthy = res.statusCode == 200 &&
          (res.headers['content-type']?.startsWith('image/') ?? false) &&
          res.bodyBytes.length > 500;
    } catch (_) {
      _osmHealthy = false;
    }
  }

  /// True when a decoded map snapshot carries real map content. Samples the
  /// central 60% (so the Google logo bottom-left and attribution bottom-right
  /// cannot lend colour to a grey field) and counts distinct quantised colours.
  /// A real map's centre has roads, water, parks and labels — many colours; the
  /// grey unavailable-field is near-uniform, one to three. Robust to the exact
  /// shade of grey because it tests richness, not a specific colour.
  Future<bool> _looksLikeRealMap(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width, h = img.height;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (data == null || w == 0 || h == 0) return false;

    final x0 = (w * 0.2).floor(), x1 = (w * 0.8).floor();
    final y0 = (h * 0.2).floor(), y1 = (h * 0.8).floor();
    final seen = <int>{};
    const grid = 10;
    for (var gy = 0; gy < grid; gy++) {
      for (var gx = 0; gx < grid; gx++) {
        final x = x0 + ((x1 - x0) * gx) ~/ grid;
        final y = y0 + ((y1 - y0) * gy) ~/ grid;
        final o = (y * w + x) * 4;
        final r = data.getUint8(o), g = data.getUint8(o + 1), b = data.getUint8(o + 2);
        seen.add(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)); // quantise 4bpc
      }
    }
    // Grey/blank fields are 1-3 distinct colours; a real map is far richer.
    return seen.length >= 5;
  }

  @override
  void dispose() {
    _probe?.cancel();
    _nativeDeadline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!RiderMap.mapSupported) return const MapPlaceholder();

    // The server's choice outranks everything the device worked out for itself.
    //
    // This is the only reliable lever when Google is broken: a failed Maps SDK
    // authorisation still builds the view, still returns a controller and still
    // fires every callback, so the app sees a perfectly healthy map that
    // happens to be grey. Ops sets app_configurations.maps_engine and every
    // installed app switches on its next status poll, with no release.
    //
    // 'google' is honoured too, for pinning the engine while debugging. Only a
    // build that hardcoded MAPS_ENGINE wins over this, because that is someone
    // deliberately overriding for one build.
    if (_engine == 'auto') {
      final serverEngine =
          ref.watch(appStatusProvider).valueOrNull?.mapsEngine ?? '';
      if (serverEngine == 'osm' && _useGoogle != false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _useGoogle = false);
        });
      } else if (serverEngine == 'google' && _useGoogle != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _useGoogle = true);
        });
      }
    }

    return switch (_useGoogle) {
      null => const MapPlaceholder(),
      true => GoogleMap(
          initialCameraPosition: widget.camera ?? RiderMap.initialCamera,
          markers: widget.markers,
          polylines: widget.polylines,
          onMapCreated: (c) {
            // The SDK constructed a view — but it fires this even when the map
            // rendered grey, so this is NOT proof Google works and must NOT
            // cancel the guarantee timer. Only a confirmed-real-map snapshot
            // (in _checkGoogleThenResolve) cancels it.
            widget.onMapCreated?.call(RiderMapController._google(c));
            if (_engine == 'auto' && !kIsWeb) {
              unawaited(_checkGoogleThenResolve(c));
            }
          },
          onTap: widget.onTap,
          padding: widget.padding,
          // The booking sheet owns the bottom of the screen; keep Google's
          // zoom chrome out from underneath it.
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Permission IS requested now — Home asks on open via
          // LocationPermissionService — so the layer follows the grant instead
          // of being hardcoded off. It stays off until the rider has actually
          // said yes, which is what the old comment here was really protecting
          // against: enabling a layer nothing had permission for.
          myLocationEnabled: widget.showMyLocation,
          myLocationButtonEnabled: widget.showMyLocation,
        ),
      false => _OsmMap(
          camera: widget.camera ?? RiderMap.initialCamera,
          markers: widget.markers,
          polylines: widget.polylines,
          onMapCreated: widget.onMapCreated,
          onTap: widget.onTap,
        ),
    };
  }
}

/// Raster tile source for the fallback map.
///
/// Defaults to the public OSM community server, which is what shipped — but
/// that is explicitly against OSM's tile usage policy for app traffic, and they
/// block by User-Agent, which this sends as `tech.hoppin.hoppin_rider`. So the
/// fallback would fail exactly when it was needed most.
///
/// The fleet already runs TileServer GL on the VM covering all of Great
/// Britain, serving raster at
/// `/styles/basic-preview/256/{z}/{x}/{y}.png`. It is tailnet-only today, so a
/// rider on mobile data cannot reach it — point TILE_URL at it once it is
/// published through the Cloudflare tunnel:
///
///   --dart-define=TILE_URL=https://tiles.hoppin.tech/styles/basic-preview/256/{z}/{x}/{y}.png
/// The same key the Android/iOS SDK is configured with, so the probe tests the
/// credential that actually draws the map.
const _mapsApiKey = String.fromEnvironment('MAPS_API_KEY');

const _tileUrl = String.fromEnvironment(
  'TILE_URL',
  // Our own TileServer GL (all of Great Britain), published through the
  // Cloudflare tunnel and cached at the edge. Replaces the public OSM server,
  // whose usage policy forbids app traffic and which blocks by User-Agent.
  defaultValue:
      'https://tiles.hoppin.tech/styles/basic-preview/256/{z}/{x}/{y}.png',
);

/// The self-hosted-stack fallback: flutter_map over the OSM raster tiles the
/// admin panel already uses. Speaks the same gmaps marker/polyline types as
/// the callers so no screen knows which engine drew it.
class _OsmMap extends StatefulWidget {
  final CameraPosition camera;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final void Function(RiderMapController controller)? onMapCreated;
  final void Function(LatLng position)? onTap;

  const _OsmMap({
    required this.camera,
    required this.markers,
    required this.polylines,
    this.onMapCreated,
    this.onTap,
  });

  @override
  State<_OsmMap> createState() => _OsmMapState();
}

class _OsmMapState extends State<_OsmMap> {
  final _controller = fmap.MapController();
  bool _announced = false;

  ll.LatLng _p(LatLng p) => ll.LatLng(p.latitude, p.longitude);

  /// Circle pin with a label — the widget twin of `circleLabelMarker`.
  Widget _circlePin(String label, Color color) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Semantic ids shared with the Google engine: pickup / stopN / dropoff /
    // driver. Anything else renders as the navy pin.
    final markers = <fmap.Marker>[
      for (final m in widget.markers)
        fmap.Marker(
          point: _p(m.position),
          width: 34,
          height: 34,
          child: switch (m.markerId.value) {
            'driver' => SvgPicture.asset('assets/vehicles/car_orange.svg',
                width: 32, height: 22),
            'pickup' => _circlePin('A', AppColors.info),
            'dropoff' => _circlePin('B', AppColors.positive),
            final id when id.startsWith('stop') =>
              _circlePin(id.substring(4), AppColors.accent),
            _ =>
              const Icon(Icons.location_pin, size: 32, color: AppColors.navy),
          },
        ),
    ];

    return fmap.FlutterMap(
      mapController: _controller,
      options: fmap.MapOptions(
        initialCenter: _p(widget.camera.target),
        initialZoom: widget.camera.zoom,
        onTap: (_, point) =>
            widget.onTap?.call(LatLng(point.latitude, point.longitude)),
        onMapReady: () {
          if (_announced) return;
          _announced = true;
          widget.onMapCreated?.call(RiderMapController._osm(_controller));
        },
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: 'tech.hoppin.hoppin_rider',
        ),
        if (widget.polylines.isNotEmpty)
          fmap.PolylineLayer(
            polylines: [
              for (final line in widget.polylines)
                fmap.Polyline(
                  points: [for (final p in line.points) _p(p)],
                  color: line.color,
                  strokeWidth: line.width.toDouble(),
                ),
            ],
          ),
        if (markers.isNotEmpty) fmap.MarkerLayer(markers: markers),
        const fmap.RichAttributionWidget(
          attributions: [
            // Required by the data licences: the basemap is OpenMapTiles
            // vector data built from OpenStreetMap (ODbL).
            fmap.TextSourceAttribution('OpenMapTiles'),
            fmap.TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}
