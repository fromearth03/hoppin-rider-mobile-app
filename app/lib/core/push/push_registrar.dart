import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// FCM boot + token registration — everything push, in one guarded seam.
///
/// Push is ADDITIVE: no piece of this may ever stop the app. Firebase init
/// happens once from main() behind [initFirebaseGuarded]; the token is
/// registered on every arrival at signed-in via [PushRegistrar.register]
/// (`POST /me/device-tokens`), which also retires the account's other
/// devices server-side — that is what routes pushes to the device the user
/// actually logged in on instead of an old session somewhere else.
///
/// Config comes from dart-defines and falls back to the platform Firebase
/// project the old web apps used. The Android APK additionally needs its
/// package registered in the Firebase console; until then getToken simply
/// fails and is swallowed — the in-app notification feed keeps working.
class PushConfig {
  PushConfig._();

  static const apiKey = String.fromEnvironment('FCM_API_KEY',
      defaultValue: 'AIzaSyDeaObkhh_prXXjNadiZQl_Q_A-dfbcHkE');
  static const appId = String.fromEnvironment('FCM_APP_ID',
      defaultValue: '1:381604059820:web:0f35c93f3f0455b6359d09');
  static const senderId =
      String.fromEnvironment('FCM_SENDER_ID', defaultValue: '381604059820');
  static const projectId =
      String.fromEnvironment('FCM_PROJECT_ID', defaultValue: 'ecom-4f7bc');
  static const vapidKey = String.fromEnvironment('FCM_VAPID_KEY');
}

bool _firebaseReady = false;

/// Call ONCE from main(), before runApp. Never throws.
Future<void> initFirebaseGuarded() async {
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: PushConfig.apiKey,
        appId: PushConfig.appId,
        messagingSenderId: PushConfig.senderId,
        projectId: PushConfig.projectId,
      ),
    ).timeout(const Duration(seconds: 8));
    _firebaseReady = true;
  } catch (_) {
    // Bad config, Safari, refused service worker — degrade to the polled
    // notification feed. Push may NEVER stop the app.
  }
}

class PushRegistrar {
  final ApiClient _api;
  bool _registered = false;
  bool _listening = false;

  PushRegistrar(this._api);

  /// Fire-and-forget on every arrival at signed-in. Latched per session; a
  /// failure clears the latch so the next sign-in retries.
  Future<void> register() async {
    if (!_firebaseReady || _registered) return;
    _registered = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken(
        vapidKey: PushConfig.vapidKey.isEmpty ? null : PushConfig.vapidKey,
      );
      if (token == null || token.isEmpty) {
        _registered = false;
        return;
      }
      await _post(token);
      if (!_listening) {
        _listening = true;
        // A rotated token that is never re-posted goes stale server-side and
        // pushes silently stop; keep it current for the life of the session.
        messaging.onTokenRefresh.listen((t) => _post(t), onError: (_) {});
      }
    } catch (_) {
      _registered = false; // unregistered platform app / no play services
    }
  }

  Future<void> _post(String token) => _api.post<Map<String, dynamic>>(
        '/me/device-tokens',
        body: {'fcm_token': token, 'device_os': _os()},
      );

  static String _os() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }
}

final pushRegistrarProvider =
    Provider<PushRegistrar>((ref) => PushRegistrar(ref.watch(apiClientProvider)));
