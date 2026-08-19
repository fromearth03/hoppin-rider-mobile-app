import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import 'fcm_gateway.dart';

/// The CONCRETE [FcmGateway], over `firebase_messaging`.
///
/// This is the ONLY file in the repository — besides `main.dart`'s single
/// guarded `Firebase.initializeApp()` — permitted to import `package:firebase_*`.
/// The phase gate asserts that with a grep. Keeping the SDK here (rather than
/// in `fcm_gateway.dart`, which imports `flutter_riverpod` and nothing else)
/// makes the isolation trivially checkable and keeps every test and the demo
/// structurally unable to reach a real Firebase instance.
///
/// It is NEVER constructed unless `Env.fcmConfigured` is true and
/// `Firebase.initializeApp()` has already succeeded. With no dart-defines —
/// today's reality — `main.dart` skips the whole block and the provider keeps
/// its [NoopFcmGateway] default.
///
/// Delivery remains GATED on the backend `FCM_CREDENTIALS_FILE` (gaps 15/16):
/// this class is wired and correct, and it will simply never receive anything
/// until the backend can send. That is the honest state — not a fake stream.
class FirebaseFcmGateway implements FcmGateway {
  /// Creates the live gateway. Only valid after a successful
  /// `Firebase.initializeApp()`.
  const FirebaseFcmGateway();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<FcmPermission> requestPermission() async {
    final settings = await _messaging.requestPermission();
    // Anything that is not an explicit grant degrades to the honest answer —
    // never a fabricated "granted".
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => FcmPermission.granted,
      AuthorizationStatus.denied => FcmPermission.denied,
      AuthorizationStatus.notDetermined => FcmPermission.notDetermined,
    };
  }

  @override
  Future<String?> token() async {
    // The VAPID key is the public "Web Push certificate". It is only non-empty
    // when the FCM dart-defines were compiled in, which is the same condition
    // under which this class is constructed at all.
    final vapid = Env.fcmVapidKey;
    return _messaging.getToken(vapidKey: vapid.isEmpty ? null : vapid);
  }

  @override
  Stream<PushMessage> onMessage() =>
      FirebaseMessaging.onMessage.map(pushMessageFromRemote);

  @override
  Stream<PushMessage> onMessageOpened() =>
      FirebaseMessaging.onMessageOpenedApp.map(pushMessageFromRemote);

  @override
  Future<PushMessage?> initialMessage() async {
    final m = await _messaging.getInitialMessage();
    return m == null ? null : pushMessageFromRemote(m);
  }
}

/// Maps a `RemoteMessage` onto the normalised [PushMessage].
///
/// The `data` map carries the ASSUMED schema (gap 15) — snake_case
/// `{ type, ride_id, deep_link, title, body }`. Routing reads `data`; display
/// prefers FCM's top-level `notification` block and falls back to `data`.
/// An unrecognised `type` degrades to [PushType.unknown] rather than throwing —
/// the schema is an assumption, so the parse must be forgiving.
PushMessage pushMessageFromRemote(RemoteMessage m) {
  final data = m.data;
  String? str(String key) {
    final v = data[key];
    if (v is! String || v.isEmpty) return null;
    return v;
  }

  return PushMessage(
    type: pushTypeFromWire(str('type')),
    notificationId: str('notification_id') ?? str('notificationId'),
    title: m.notification?.title ?? str('title'),
    body: m.notification?.body ?? str('body'),
    rideId: str('ride_id') ?? str('rideId'),
    deepLink: str('deep_link') ?? str('deepLink'),
    sentAt: m.sentTime,
  );
}
