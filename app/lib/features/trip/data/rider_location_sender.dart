import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/api/api_client.dart';

/// Sends the rider's position while a driver is on the way to them.
///
/// Only in that window. The driver may not announce arrival beyond 30 m or
/// start the trip beyond 15 m, and both are a distance between two people — so
/// the platform needs to know where the rider is for exactly as long as someone
/// is driving toward them, and no longer.
///
/// Not a background service: this streams while the trip screen is open, which
/// is when the rider is waiting anyway. Following them around after pickup
/// would cost battery and collect movements nothing asks for.
class RiderLocationSender {
  final ApiClient _api;
  RiderLocationSender(this._api);

  StreamSubscription<Position>? _sub;
  String? _forRide;

  bool get isSending => _sub != null;

  /// Starts streaming for [rideId], if it is not already.
  ///
  /// Permission is requested here rather than at launch: asked cold, "Hoppin
  /// wants your location" is a reasonable thing to refuse, while asked with a
  /// driver already en route it is obviously the thing that makes the pickup
  /// work.
  Future<void> start(String rideId) async {
    if (_forRide == rideId && _sub != null) return;
    await stop();
    _forRide = rideId;

    if (!await _ensurePermission()) return;

    try {
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Metres of movement before another fix. The tightest gate is 15 m,
          // so 5 m resolves it without streaming continuously while the rider
          // stands still.
          distanceFilter: 5,
        ),
      ).listen(_send, onError: (_) {
        // A revoked permission or a dead GPS must not take the trip screen
        // down. The gates fail open, so the ride still works without this.
      });
    } catch (_) {
      // Same: the sender is an enhancement to the pickup, never a requirement.
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _forRide = null;
  }

  Future<void> _send(Position p) async {
    await _api.post<Map<String, dynamic>>('/me/location', body: {
      'lat': p.latitude,
      'lng': p.longitude,
      // Sent so the server can tell a precise fix from a vague one: a reading
      // accurate to ±50 m cannot answer a 15 m question, and the gate needs to
      // know that rather than treating it as exact.
      'accuracy_m': p.accuracy,
    });
  }

  Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }
}

final riderLocationSenderProvider = Provider<RiderLocationSender>((ref) {
  final sender = RiderLocationSender(ref.watch(apiClientProvider));
  ref.onDispose(sender.stop);
  return sender;
});
