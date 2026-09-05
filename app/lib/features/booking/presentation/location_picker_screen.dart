import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/result.dart';
import '../../../core/theme/colors.dart';
import '../data/places_repository.dart';
import 'widgets/rider_map.dart';

/// A point chosen on the map, with the address we resolved for it.
class PickedPoint {
  final String label;
  final double lat;
  final double lng;

  const PickedPoint({required this.label, required this.lat, required this.lng});
}

/// Pick one location by tapping the map.
///
/// The rider can already save a place by typing an address, but a lot of real
/// places are easier to point at than to name — a side entrance, an unnamed
/// car park, "the corner by the church". Tapping drops the pin and we
/// reverse-geocode it so the saved place still carries a human-readable
/// address rather than bare coordinates.
///
/// Pops with a [PickedPoint], or null if the rider backs out.
class LocationPickerScreen extends ConsumerStatefulWidget {
  /// Shown in the app bar — "Pick your pickup", "Save a place", etc.
  final String title;

  const LocationPickerScreen({super.key, this.title = 'Choose on map'});

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  gmaps.LatLng? _point;
  String? _address;
  bool _resolving = false;
  RiderMapController? _map;

  Future<void> _pick(gmaps.LatLng at) async {
    setState(() {
      _point = at;
      _resolving = true;
      _address = null;
    });
    _map?.moveTo(gmaps.CameraPosition(target: at, zoom: 16));

    final res = await ref
        .read(placesRepositoryProvider)
        .reverse(at.latitude, at.longitude);
    if (!mounted) return;
    setState(() {
      _resolving = false;
      // A failed lookup is not a failed pick — the coordinates are still valid,
      // so fall back to showing them rather than refusing to save the place.
      _address = switch (res) {
        Ok(:final value) => value.label,
        Err() =>
          '${at.latitude.toStringAsFixed(5)}, ${at.longitude.toStringAsFixed(5)}',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    final markers = <gmaps.Marker>{
      if (point != null && RiderMap.mapSupported)
        gmaps.Marker(
          markerId: const gmaps.MarkerId('pickup'),
          position: point,
        ),
    };

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          Positioned.fill(
            child: RiderMap(
              markers: markers,
              onMapCreated: (c) => _map = c,
              onTap: _pick,
              padding: const EdgeInsets.only(bottom: 190),
            ),
          ),
          if (point == null)
            const Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: _Hint(),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: PointerInterceptor(
              child: _Confirm(
                address: _address,
                resolving: _resolving,
                onConfirm: point == null || _resolving
                    ? null
                    : () => Navigator.of(context).pop(PickedPoint(
                          label: _address ?? 'Dropped pin',
                          lat: point.latitude,
                          lng: point.longitude,
                        )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 3,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 20, color: AppColors.navy),
              SizedBox(width: 10),
              Expanded(
                child: Text('Tap anywhere on the map to drop a pin',
                    style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
      );
}

class _Confirm extends StatelessWidget {
  final String? address;
  final bool resolving;
  final VoidCallback? onConfirm;

  const _Confirm({this.address, required this.resolving, this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined,
                      size: 20, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: resolving
                        ? const Text('Finding the address…',
                            style: TextStyle(fontSize: 15))
                        : Text(
                            address ?? 'No pin yet',
                            style: TextStyle(
                              fontSize: 15,
                              color: address == null
                                  ? AppColors.lightTextSecondary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onConfirm,
                child: const Text('Use this location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
