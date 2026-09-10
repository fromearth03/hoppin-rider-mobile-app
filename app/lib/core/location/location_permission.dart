import 'package:geolocator/geolocator.dart';

/// Runtime location permission, asked at the moment the rider can understand
/// why it is being asked.
///
/// Before this existed the ONLY `Geolocator.requestPermission()` in the app sat
/// inside the live-trip location sender, reached solely from `live_trip_screen`
/// while a trip was in the `accepted` or `arriving` state. So a rider could
/// install the app, sign up, browse, and book without ever seeing the prompt —
/// and it would finally appear mid-journey, which is both the worst moment to
/// ask and easy to miss entirely on a short trip. `rider_locations` was empty
/// across the entire production database as a result.
///
/// The map's own location layer could not cover for it either: `rider_map.dart`
/// had `myLocationEnabled: false` with a comment saying the runtime permission
/// "is not requested yet", so the one component that would have triggered the
/// system prompt was switched off precisely because nothing asked.
///
/// Never throws: every call site treats a refusal as "carry on without the blue
/// dot", never as an error. Booking works with a typed address and must keep
/// working for a rider who says no.
class LocationPermissionService {
  const LocationPermissionService._();

  /// True when the app may read position right now.
  ///
  /// Asks at most once per call; a rider who has already chosen is not
  /// re-prompted, because `requestPermission` on a permanently-denied
  /// permission returns immediately without showing anything on either
  /// platform.
  static Future<bool> ensure() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      // deniedForever is deliberately NOT re-requested: the OS suppresses the
      // dialog, so asking again is a silent no-op that burns a frame. Sending
      // the rider to app settings is a decision for the screen, not for this.
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Whether permission is already granted, WITHOUT prompting. For deciding
  /// what to render before asking anything.
  static Future<bool> granted() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }
}
