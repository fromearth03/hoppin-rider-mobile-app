import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_placeholder.dart';

/// The map surface every map-shaped screen shares.
///
/// Renders the real Google map where the Maps SDK exists — Android and iOS —
/// and the honest [MapPlaceholder] everywhere else. There is no Maps SDK for
/// web or Windows in this app (the web key would be a separate, separately
/// billed product), so those targets say what they are instead of pretending.
///
/// The platform check uses `dart:io`'s [Platform], not `defaultTargetPlatform`:
/// widget tests run on the host OS and must get the placeholder, and
/// `defaultTargetPlatform` lies to them (it reports android inside
/// `flutter_test`).
class RiderMap extends StatelessWidget {
  /// Where the camera starts until live location wiring lands. Hoppin
  /// operates in the UK; central London is the least-wrong default.
  static const CameraPosition initialCamera = CameraPosition(
    target: LatLng(51.5074, -0.1278),
    zoom: 13,
  );

  const RiderMap({super.key});

  static bool get _nativeMapSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  Widget build(BuildContext context) {
    if (!_nativeMapSupported) return const MapPlaceholder();

    return const GoogleMap(
      initialCameraPosition: initialCamera,
      // The booking sheet owns the bottom of the screen; keep Google's
      // zoom chrome out from underneath it.
      zoomControlsEnabled: false,
      // Location layer needs runtime permissions that are not requested
      // yet — leaving it off beats a crash on first open.
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
    );
  }
}
