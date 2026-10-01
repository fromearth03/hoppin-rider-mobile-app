import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../result.dart';
import 'device_id.dart';

/// Reports this install's fingerprint to `POST /me/device` — the ingestion
/// path behind the admin panel's Device Fingerprints screen. Without this
/// call a brand-new account signs up, books and rides while that screen
/// never hears of the device: the id was only riding along as the
/// `X-Hoppin-Device-ID` header, which the blacklist GATE reads but nothing
/// ever RECORDS.
///
/// Fire-and-forget on every arrival at signed-in (fresh sign-in, sign-up and
/// session restore alike) and again whenever the app returns to the
/// foreground, at most every [refreshEvery]. A failure never blocks auth; it
/// is retried with back-off.
class DeviceCheckin {
  final ApiClient _api;
  final DeviceIdProvider _device;
  final Duration Function(int attempt) _backoff;

  /// When this session's check-in last reached the server.
  DateTime? _lastOk;
  bool _inFlight = false;

  DeviceCheckin(this._api, this._device, {Duration Function(int attempt)? backoff})
      : _backoff = backoff ?? ((n) => Duration(seconds: 5 * n * n));

  static const _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// How often a running app re-reports (on returning to the foreground), so
  /// the panel's last-seen time and IP follow the rider.
  static const refreshEvery = Duration(minutes: 15);

  /// Reports the fingerprint, retrying a failure a few times with back-off.
  /// It used to latch "done" BEFORE sending, so one failure (an outage, a
  /// tunnel, a throw) meant no check-in for the rest of the session.
  Future<void> report({bool force = false}) async {
    if (_inFlight) return;
    final last = _lastOk;
    if (!force && last != null && DateTime.now().difference(last) < refreshEvery) {
      return;
    }
    _inFlight = true;
    try {
      for (var attempt = 1; attempt <= 4; attempt++) {
        if (await _send()) {
          _lastOk = DateTime.now();
          return;
        }
        if (attempt < 4) await Future<void>.delayed(_backoff(attempt));
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<bool> _send() async {
    try {
      final id = await _device.resolve();
      final result = await _api.post<Map<String, dynamic>>(
        '/me/device',
        body: {
          'device_hardware_id': id,
          'operating_system': _operatingSystem(),
          'app_version': _appVersion,
          'is_emulator': false,
        },
      );
      // DEVICE_BLACKLISTED (403) is a real answer, not a failure to retry;
      // every ride endpoint enforces the blacklist server-side anyway.
      return switch (result) {
        Ok() => true,
        Err(:final error) => error.code == 'DEVICE_BLACKLISTED',
      };
    } catch (e) {
      debugPrint('device check-in failed: $e');
      return false;
    }
  }

  static String _operatingSystem() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name; // android / iOS / linux / ...
  }
}

final deviceCheckinProvider = Provider<DeviceCheckin>(
  (ref) => DeviceCheckin(
    ref.watch(apiClientProvider),
    ref.watch(deviceIdProvider),
  ),
);
