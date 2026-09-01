import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb;
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
/// Fire-and-forget, once per app session, on every arrival at signed-in
/// (fresh sign-in, sign-up and session restore alike — a fingerprint that is
/// only captured at account creation goes stale on the next phone).
/// A failure must never block auth; it clears the latch so the next
/// sign-in retries.
class DeviceCheckin {
  final ApiClient _api;
  final DeviceIdProvider _device;
  bool _reported = false;

  DeviceCheckin(this._api, this._device);

  static const _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  Future<void> report() async {
    if (_reported) return;
    _reported = true;

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
    // DEVICE_BLACKLISTED (403) intentionally does not sign the rider out
    // here — every ride endpoint enforces the blacklist server-side via the
    // header, which cannot be skipped by suppressing this call.
    if (result is Err) _reported = false;
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
