import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// The outcome of a location-permission request, normalised away from the
/// plugin's enum so widgets and tests never import geolocator directly.
enum LocationPermissionResult {
  /// The rider granted while-in-use (or always) access.
  granted,

  /// The rider declined this time — can be asked again later.
  denied,

  /// The rider declined permanently — must be changed in OS settings.
  deniedForever,

  /// Location services are switched off at the OS level.
  serviceDisabled,
}

/// The rider-app-only seam over the OS location + permission plugins
/// (COMPLY-02). Kept behind this interface so:
///   * `geolocator`/`permission_handler` imports never leak into
///     `hoppin_shared`/`hoppin_demo` (the isolation grep stays clean), and
///   * widget tests inject a fake and never touch real OS APIs.
abstract class LocationService {
  /// Requests OS location permission (while-in-use). Called ONLY after the JIT
  /// purpose text has been shown and the rider taps allow.
  Future<LocationPermissionResult> requestPermission();

  /// Whether permission is already granted — lets a caller skip the JIT prompt.
  Future<bool> hasPermission();

  /// The device's current coordinates, or `null` when unavailable (permission
  /// denied/denied-forever, services off, timeout, browser refusal). NEVER
  /// throws — a location failure must DEGRADE the SOS payload, never BLOCK the
  /// SOS (SAFETY-01 hard requirement).
  ///
  /// It also NEVER prompts: if permission is absent it returns `null`
  /// immediately. The OS permission dialog must never be the thing standing
  /// between a frightened rider and the SOS button. Callers that WANT consent
  /// (the JIT prompt) ask for it explicitly via [requestPermission].
  Future<({double lat, double lng})?> currentPosition({
    Duration timeout = const Duration(seconds: 5),
  });
}

/// Reads a single OS position fix within [timeout]. Injected so every failure
/// path (throw, hang, refusal) is drivable from a test without a MethodChannel
/// mock — the project injects fakes, it never channel-mocks.
typedef PositionReader = Future<Position> Function({required Duration timeout});

/// Probes whether location permission is already granted. Injected for the
/// same reason as [PositionReader].
typedef PermissionProbe = Future<bool> Function();

/// The live implementation over `geolocator`. The rider app wires this; the
/// demo composition supplies its own fake, so this class is never reached off
/// the live path.
class GeolocatorLocationService implements LocationService {
  /// The live service. The two seams default to the real geolocator statics;
  /// tests inject scripted ones to drive every failure path.
  const GeolocatorLocationService({
    PositionReader? readPosition,
    PermissionProbe? checkPermission,
  })  : _readPosition = readPosition ?? _geolocatorRead,
        _checkPermission = checkPermission ?? _geolocatorHasPermission;

  final PositionReader _readPosition;
  final PermissionProbe _checkPermission;

  static Future<Position> _geolocatorRead({required Duration timeout}) {
    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
  }

  static Future<bool> _geolocatorHasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<LocationPermissionResult> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionResult.serviceDisabled;
    }
    final permission = await Geolocator.requestPermission();
    return _map(permission);
  }

  @override
  Future<bool> hasPermission() => _checkPermission();

  /// SAFETY-01. Every path out of this method returns — none throws, none is
  /// unbounded, none prompts. If any of those three were false, an SOS could
  /// be blocked by a location failure, which is a worse safety defect than the
  /// imprecise alert it would be trying to prevent.
  @override
  Future<({double lat, double lng})?> currentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      // Short-circuit rather than prompt: an `await` on an OS permission
      // dialog is an UNBOUNDED wait on a human, and on the panic path that
      // wait is the alarm not firing.
      if (!await _checkPermission()) return null;

      // Belt AND braces on the bound: `timeLimit` is the plugin's own budget,
      // and `.timeout()` guards the case where the platform never honours it
      // (web geolocation has been observed to simply never answer).
      final position = await _readPosition(timeout: timeout)
          .timeout(timeout + const Duration(milliseconds: 250));
      return (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      // Deliberately bare. TimeoutException, PermissionDeniedException,
      // LocationServiceDisabledException, a browser refusal that surfaces as an
      // untyped error — all of them mean the same thing to the caller: no fix.
      // A typed catch here would let one escape and block an SOS.
      return null;
    }
  }

  LocationPermissionResult _map(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationPermissionResult.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionResult.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionResult.denied;
    }
  }
}
