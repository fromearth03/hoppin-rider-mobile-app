import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_service.dart';

/// The rider-app-local location seam.
///
/// It lives HERE, not in `hoppin_shared/providers.dart`, on purpose: the
/// isolation contract says `geolocator`/`permission_handler` imports never leak
/// into `hoppin_shared`/`hoppin_demo`. The default IS the live implementation;
/// the demo composition overrides it with [FakeLocationService], and widget
/// tests override it with their own scripted doubles.
final locationServiceProvider =
    Provider<LocationService>((ref) => const GeolocatorLocationService());

/// The demo/dev location double — a fixed fix near the `DemoSeed` origin
/// (Wolverhampton). It never touches an OS API, so the demo build never
/// triggers a permission dialog and never depends on a machine having GPS.
///
/// Registered in `main_demo.dart` via:
/// `locationServiceProvider.overrideWithValue(const FakeLocationService())`.
class FakeLocationService implements LocationService {
  const FakeLocationService();

  /// Wolverhampton — the demo world's origin.
  static const ({double lat, double lng}) fix = (lat: 52.5862, lng: -2.1281);

  @override
  Future<LocationPermissionResult> requestPermission() async =>
      LocationPermissionResult.granted;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<({double lat, double lng})?> currentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      fix;
}
