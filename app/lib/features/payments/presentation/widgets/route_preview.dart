import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../../../core/geo.dart';
import '../../../../core/theme/colors.dart';
import '../../../booking/presentation/widgets/map_markers.dart';
import '../../../booking/presentation/widgets/rider_map.dart';

/// The completed journey on the REAL map — `GET /rides/:id`'s `geo.route`
/// drawn as a polyline over live tiles, camera fitted to the route, with the
/// pickup (A) and dropoff (B) pinned. Non-interactive: it is a snapshot in a
/// card, not a map to wander.
///
/// Callers must not build this with fewer than two points; a route that short
/// has no line to draw, and the screen omits the card instead.
class RoutePreview extends StatefulWidget {
  final List<LatLng> points;
  final double height;

  const RoutePreview({super.key, required this.points, this.height = 180});

  @override
  State<RoutePreview> createState() => _RoutePreviewState();
}

class _RoutePreviewState extends State<RoutePreview> {
  Set<gmaps.Marker> _markers = const {};

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  Future<void> _buildMarkers() async {
    // No engine, no bitmaps: tests and desktop render the placeholder.
    if (!RiderMap.mapSupported || widget.points.length < 2) return;
    final first = widget.points.first;
    final last = widget.points.last;
    final markers = <gmaps.Marker>{
      gmaps.Marker(
        markerId: const gmaps.MarkerId('pickup'),
        position: gmaps.LatLng(first.lat, first.lng),
        icon: await circleLabelMarker('A', AppColors.info),
      ),
      gmaps.Marker(
        markerId: const gmaps.MarkerId('dropoff'),
        position: gmaps.LatLng(last.lat, last.lng),
        icon: await circleLabelMarker('B', AppColors.positive),
      ),
    };
    if (mounted) setState(() => _markers = markers);
  }

  gmaps.LatLngBounds get _bounds {
    var minLat = widget.points.first.lat, maxLat = widget.points.first.lat;
    var minLng = widget.points.first.lng, maxLng = widget.points.first.lng;
    for (final p in widget.points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    return gmaps.LatLngBounds(
      southwest: gmaps.LatLng(minLat, minLng),
      northeast: gmaps.LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mid = widget.points[widget.points.length ~/ 2];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        // A snapshot, not a viewport: touches scroll the page, never pan the
        // map.
        child: IgnorePointer(
          child: RiderMap(
            camera: gmaps.CameraPosition(
              target: gmaps.LatLng(mid.lat, mid.lng),
              zoom: 12,
            ),
            markers: _markers,
            polylines: {
              gmaps.Polyline(
                polylineId: const gmaps.PolylineId('trip'),
                points: [
                  for (final p in widget.points) gmaps.LatLng(p.lat, p.lng),
                ],
                color: AppColors.navy,
                width: 4,
              ),
            },
            onMapCreated: (c) => c.fitBounds(_bounds, 28),
          ),
        ),
      ),
    );
  }
}
