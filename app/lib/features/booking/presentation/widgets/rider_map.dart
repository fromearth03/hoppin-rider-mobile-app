import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
class RiderMap extends StatefulWidget {
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

  const RiderMap({
    super.key,
    this.camera,
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onTap,
    this.padding = EdgeInsets.zero,
  });

  static bool get mapSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  State<RiderMap> createState() => _RiderMapState();
}

class _RiderMapState extends State<RiderMap> {
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

  @override
  void initState() {
    super.initState();
    if (!RiderMap.mapSupported) return;
    if (_engine == 'osm') {
      _useGoogle = false;
      return;
    }
    if (!kIsWeb || _engine == 'google') {
      _useGoogle = true;
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

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!RiderMap.mapSupported) return const MapPlaceholder();

    return switch (_useGoogle) {
      null => const MapPlaceholder(),
      true => GoogleMap(
          initialCameraPosition: widget.camera ?? RiderMap.initialCamera,
          markers: widget.markers,
          polylines: widget.polylines,
          onMapCreated: (c) =>
              widget.onMapCreated?.call(RiderMapController._google(c)),
          onTap: widget.onTap,
          padding: widget.padding,
          // The booking sheet owns the bottom of the screen; keep Google's
          // zoom chrome out from underneath it.
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Location layer needs runtime permissions that are not requested
          // yet — leaving it off beats a crash on first open.
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
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
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
            fmap.TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}
