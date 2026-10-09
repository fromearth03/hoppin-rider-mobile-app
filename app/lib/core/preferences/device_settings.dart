import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum DistanceUnit { miles, kilometres }

enum NavigationApp { system, googleMaps, appleMaps, waze }

class DeviceSettings {
  final bool keepAwake;
  final DistanceUnit distanceUnit;
  final NavigationApp navigation;
  final String language;
  const DeviceSettings({
    this.keepAwake = false,
    this.distanceUnit = DistanceUnit.miles,
    this.navigation = NavigationApp.system,
    this.language = 'en',
  });

  DeviceSettings copyWith({
    bool? keepAwake,
    DistanceUnit? distanceUnit,
    NavigationApp? navigation,
    String? language,
  }) => DeviceSettings(
    keepAwake: keepAwake ?? this.keepAwake,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    navigation: navigation ?? this.navigation,
    language: language ?? this.language,
  );

  Map<String, Object> toJson() => {
    'keepAwake': keepAwake,
    'distanceUnit': distanceUnit.name,
    'navigation': navigation.name,
    'language': language,
  };

  factory DeviceSettings.fromJson(Map<String, dynamic> json) => DeviceSettings(
    keepAwake: json['keepAwake'] == true,
    distanceUnit:
        DistanceUnit.values
            .where((v) => v.name == json['distanceUnit'])
            .firstOrNull ??
        DistanceUnit.miles,
    navigation:
        NavigationApp.values
            .where((v) => v.name == json['navigation'])
            .firstOrNull ??
        NavigationApp.system,
    language: const ['en', 'ur', 'hi'].contains(json['language'])
        ? json['language'] as String
        : 'en',
  );
}

class DeviceSettingsStore {
  final FlutterSecureStorage storage;
  const DeviceSettingsStore([this.storage = const FlutterSecureStorage()]);
  static const key = 'hoppin_device_settings';
  Future<DeviceSettings> read() async {
    try {
      final raw = await storage.read(key: key);
      return raw == null
          ? const DeviceSettings()
          : DeviceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const DeviceSettings();
    }
  }

  Future<void> write(DeviceSettings value) =>
      storage.write(key: key, value: jsonEncode(value.toJson()));
}

final deviceSettingsStoreProvider = Provider(
  (ref) => const DeviceSettingsStore(),
);
final initialDeviceSettingsProvider = Provider((ref) => const DeviceSettings());

class DeviceSettingsController extends Notifier<DeviceSettings> {
  Future<void> _pending = Future.value();
  @override
  DeviceSettings build() => ref.watch(initialDeviceSettingsProvider);

  /// Serialize whole-record writes so rapid changes cannot overwrite each other.
  Future<bool> update(DeviceSettings Function(DeviceSettings) change) {
    final next = _pending.then((_) async {
      final value = change(state);
      try {
        await ref.read(deviceSettingsStoreProvider).write(value);
      } catch (_) {
        return false;
      }
      state = value;
      return true;
    });
    _pending = next.then((_) {});
    return next;
  }
}

final deviceSettingsProvider =
    NotifierProvider<DeviceSettingsController, DeviceSettings>(
      DeviceSettingsController.new,
    );

String formatDistance(num metres, DistanceUnit unit) {
  final value = metres / (unit == DistanceUnit.miles ? 1609.344 : 1000);
  return '${value.toStringAsFixed(1)} ${unit == DistanceUnit.miles ? 'mi' : 'km'}';
}
