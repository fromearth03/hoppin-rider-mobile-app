import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'result.dart';

/// The launch gate the operator controls from the admin panel: is the platform
/// down for maintenance, and is this build too old to keep using.
class AppStatus {
  final bool maintenanceMode;

  /// Operator copy for the maintenance screen — what is happening and roughly
  /// when it ends. Null when they set none; the screen has its own fallback.
  final String? maintenanceMessage;

  final bool forceUpdateRequired;
  final bool updateAvailable;
  final String latestVersion;

  const AppStatus({
    this.maintenanceMode = false,
    this.maintenanceMessage,
    this.forceUpdateRequired = false,
    this.updateAvailable = false,
    this.latestVersion = '',
  });

  /// What the app assumes when the check itself fails.
  ///
  /// Open, deliberately. This gate is a kill switch, and an unreachable server
  /// must never be able to trigger one: a rider standing at the kerb with a
  /// flaky connection would be locked out of a working app by a request that
  /// never arrived. If the platform really is down, every other call fails too
  /// and the app degrades honestly through its offline handling.
  static const unknown = AppStatus();

  factory AppStatus.fromJson(Map<String, dynamic> json) => AppStatus(
        maintenanceMode: json['maintenance_mode'] == true,
        maintenanceMessage: switch (json['maintenance_message']) {
          String s when s.trim().isNotEmpty => s.trim(),
          _ => null,
        },
        forceUpdateRequired: json['force_update_required'] == true,
        updateAvailable: json['update_available'] == true,
        latestVersion: switch (json['latest_version']) {
          String s => s,
          _ => '',
        },
      );

  /// True when the app must not let the rider do anything else.
  bool get blocked => maintenanceMode || forceUpdateRequired;
}

class AppStatusRepository {
  final ApiClient _api;
  const AppStatusRepository(this._api);

  static const _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  Future<AppStatus> fetch() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/app-status',
      query: {'platform': _platform(), 'version': _appVersion},
    );
    return switch (res) {
      Ok(:final value) => AppStatus.fromJson(value),
      Err() => AppStatus.unknown,
    };
  }

  /// The server only configures ios and android. The web build is the same
  /// release as the Android one, so it is gated with it rather than being
  /// silently ungateable.
  static String _platform() {
    if (kIsWeb) return 'android';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}

final appStatusRepositoryProvider = Provider<AppStatusRepository>(
    (ref) => AppStatusRepository(ref.watch(apiClientProvider)));

/// Checked once at launch and re-read whenever it is invalidated (the
/// maintenance screen's Try again). Not polled: a rider being yanked out of a
/// booking mid-flow by a toggle is worse than them finishing the trip they
/// already started, and the operator's real lever is that no NEW session can
/// get past this gate.
final appStatusProvider = FutureProvider<AppStatus>(
    (ref) => ref.watch(appStatusRepositoryProvider).fetch());
