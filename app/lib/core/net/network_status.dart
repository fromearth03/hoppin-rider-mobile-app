import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app can actually reach the backend.
///
/// Deliberately NOT driven by the platform's connectivity flag. That flag
/// answers "is a network interface up", which is a different question and is
/// wrong in all the cases that matter: a captive-portal hotspot, full bars with
/// no data allowance, or our own API being down all report "connected". The
/// only honest signal is whether our requests are actually completing, so this
/// is fed by the API client: a transport failure (no HTTP response at all)
/// marks us offline; any real response — even a 500 — proves the server was
/// reached and marks us online.
enum Reachability { online, offline }

class NetworkStatus extends ChangeNotifier {
  Reachability _state = Reachability.online;
  Timer? _probe;

  /// Re-checked while offline so the app recovers on its own — the rider should
  /// not have to sit there pressing Retry.
  ///
  /// Assigned once by the API client provider rather than injected at
  /// construction: the probe needs the client, and the client needs this, so
  /// one of the two has to be wired second.
  Future<bool> Function()? pingBackend;

  NetworkStatus({this.pingBackend});


  Reachability get state => _state;
  bool get isOffline => _state == Reachability.offline;

  /// Called by the API client for every completed call.
  ///
  /// [reachedServer] is false ONLY for transport failures — a timeout or a
  /// refused connection, where no HTTP status came back. A 4xx or 5xx means the
  /// server answered, so the network is fine and this must not flip us offline.
  void report({required bool reachedServer}) {
    _set(reachedServer ? Reachability.online : Reachability.offline);
  }

  void _set(Reachability next) {
    if (_state == next) return;
    _state = next;
    if (next == Reachability.offline) {
      _startProbing();
    } else {
      _probe?.cancel();
      _probe = null;
    }
    notifyListeners();
  }

  void _startProbing() {
    if (pingBackend == null || _probe != null) return;
    _probe = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        if (await pingBackend!()) _set(Reachability.online);
      } catch (_) {
        // Still down. Keep probing.
      }
    });
  }

  /// Manual retry from the offline screen.
  Future<bool> recheck() async {
    if (pingBackend == null) return false;
    try {
      final ok = await pingBackend!();
      if (ok) _set(Reachability.online);
      return ok;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  void forceOffline() => _set(Reachability.offline);

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }
}

/// Single instance for the app. The ping target is injected in [main] so this
/// file stays free of any HTTP dependency and is trivially testable.
final networkStatusProvider = ChangeNotifierProvider<NetworkStatus>(
  (ref) => NetworkStatus(),
);
