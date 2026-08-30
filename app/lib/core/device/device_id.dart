import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The value of `X-Hoppin-Device-ID`, stable for the life of an install.
///
/// The backend's DeviceBlacklistGate is **fail-open on a missing header**: no
/// header means the check is skipped entirely. So an empty or absent device id
/// does not fail loudly — it silently disables a security control. Every
/// authenticated request must carry one.
///
/// Read once at startup and cached, because the header is needed on every call
/// and secure storage is not free.
class DeviceIdProvider {
  static const _key = 'hoppin_device_id';

  final FlutterSecureStorage _storage;
  final DeviceInfoPlugin _info;
  String? _cached;

  DeviceIdProvider(this._storage, this._info);

  String? get cached => _cached;

  /// Resolves the id, preferring the platform's own hardware identifier and
  /// falling back to a stored value.
  ///
  /// Android's `id` and iOS's `identifierForVendor` both survive app restarts,
  /// which is what the blacklist needs — an id regenerated per launch would let
  /// a blocked device walk straight past the gate. iOS clears
  /// `identifierForVendor` when the last app from a vendor is uninstalled, so
  /// the stored copy is what keeps it stable across a reinstall.
  Future<String> resolve() async {
    if (_cached != null) return _cached!;

    final stored = await _storage.read(key: _key);
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    final id = await _platformId();
    await _storage.write(key: _key, value: id);
    _cached = id;
    return id;
  }

  Future<String> _platformId() async {
    try {
      if (Platform.isAndroid) {
        final a = await _info.androidInfo;
        if (a.id.isNotEmpty) return a.id;
      } else if (Platform.isIOS) {
        final i = await _info.iosInfo;
        final v = i.identifierForVendor;
        if (v != null && v.isNotEmpty) return v;
      }
    } catch (_) {
      // Fall through — a generated id is better than no header at all.
    }
    return 'hop-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  }
}

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

final deviceIdProvider = Provider<DeviceIdProvider>(
  (ref) => DeviceIdProvider(ref.watch(secureStorageProvider), DeviceInfoPlugin()),
);
