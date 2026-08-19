import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L1c seam over the platform FCM SDK (RIDER-APP-ONLY).
///
/// The single abstraction the notification rail talks to. `firebase_core` /
/// `firebase_messaging` are isolated to `firebase_fcm_gateway.dart` plus the
/// app-root wiring in `main.dart` — never in `hoppin_shared`/`hoppin_demo`,
/// mirroring the Phase-6 `maplibre_gl` and Phase-9 `flutter_stripe` isolation
/// contracts so the shared/demo layers stay SDK-free and the phase-gate
/// isolation grep passes.
///
/// Delivery is GATED on the backend `FCM_CREDENTIALS_FILE` plus a documented
/// push payload schema (DOCS/04:44; gaps 15/16), and token registration is
/// separately gated on `device_os` accepting a web value (gap 69). The live
/// target today is [NoopFcmGateway], which reports the gate honestly rather
/// than faking a token or a stream.
///
/// The 3s poll (`trip_interactor.dart`) remains the CORRECTNESS FLOOR. Nothing
/// here gates trip state — push is strictly ADDITIVE, forever.
abstract interface class FcmGateway {
  /// Ask the OS for notification permission. Web + iOS require an explicit
  /// grant; Android 13+ too. Returns the honest outcome — NEVER assume granted.
  Future<FcmPermission> requestPermission();

  /// The device's FCM registration token, or `null` when unavailable (no
  /// permission, no Firebase project, unsupported browser). Callers feed a
  /// non-null token to `ProfileRepository.registerDeviceToken` — but ONLY on a
  /// platform whose `device_os` the contract accepts (see
  /// `registerDeviceTokenIfSupported` in `notification_feed.dart`).
  Future<String?> token();

  /// Foreground pushes. Empty stream on the no-op — the centre still renders
  /// (its cold-start rung) and the poll floor still drives the trip.
  Stream<PushMessage> onMessage();

  /// A push the rider TAPPED (background → foreground, or cold start). The
  /// tap-router turns each into a route. Empty on the no-op.
  Stream<PushMessage> onMessageOpened();

  /// The push that cold-started the app, if any. `null` on the no-op.
  Future<PushMessage?> initialMessage();
}

/// Normalised permission outcome — widgets and tests never import a firebase
/// enum. Same normalisation discipline as `LocationPermissionResult`.
enum FcmPermission {
  /// The rider allowed notifications.
  granted,

  /// The rider refused.
  denied,

  /// No answer yet — nothing has been asked.
  notDetermined,

  /// No push surface at all: the no-op gateway, an unsupported browser, or a
  /// build with no Firebase project compiled in. The honest answer while
  /// delivery is gated.
  unsupported,
}

/// A push, normalised away from `RemoteMessage` so nothing above this boundary
/// imports firebase.
///
/// The wire shape is ASSUMED (gap 15 — the backend has published no push-event
/// schema). It mirrors the notification-record shape the sibling gap doc
/// already proposes, so that when the history endpoint lands the centre and
/// the push rail parse the same thing:
///
/// ```json
/// { "type": "driver_assigned", "ride_id": "…", "deep_link": "/trip/…",
///   "title": "…", "body": "…" }
/// ```
class PushMessage {
  /// Creates a normalised push.
  const PushMessage({
    required this.type,
    this.notificationId,
    this.title,
    this.body,
    this.rideId,
    this.deepLink,
    this.sentAt,
  });

  /// The event kind. Unknown wire values map to [PushType.unknown] and route to
  /// the notification centre — never a crash, never a dropped message.
  final PushType type;

  /// Durable server id, used to reconcile a foreground push with history.
  final String? notificationId;

  /// Display headline (FCM's top-level `notification.title`, falling back to
  /// `data.title`).
  final String? title;

  /// Display body.
  final String? body;

  /// The trip this push is about, when it is about one.
  final String? rideId;

  /// The in-app path the backend wants opened, e.g. `/trip/<id>`. ASSUMED (gap
  /// 15). OBEYED only when it passes the allowlist in `push_tap_router.dart` —
  /// a push payload is attacker-influenceable and is never followed blind.
  final String? deepLink;

  /// When the backend says it sent this.
  final DateTime? sentAt;
}

/// The push-event catalogue this client understands.
///
/// ASSUMED (gap 15) — the backend has not published one; this set is relayed in
/// DOCS/06 as the client's parse contract. Unknown values degrade to [unknown]
/// rather than throwing.
enum PushType {
  /// A driver accepted the ride.
  driverAssigned,

  /// The driver is en route.
  driverArriving,

  /// The driver is at the pickup.
  driverArrived,

  /// The trip began.
  tripStarted,

  /// The trip finished.
  tripCompleted,

  /// The trip was cancelled.
  tripCancelled,

  /// A new in-trip chat message.
  newMessage,

  /// A marketing/promotional message.
  promo,

  /// Anything the backend sends that this client does not know. Routes to the
  /// centre so the rider still SEES it.
  unknown,
}

/// The snake_case wire values for [PushType], per the ASSUMED schema (gap 15).
const Map<String, PushType> _pushTypeWire = <String, PushType>{
  'driver_assigned': PushType.driverAssigned,
  'driver_arriving': PushType.driverArriving,
  'driver_arrived': PushType.driverArrived,
  'trip_started': PushType.tripStarted,
  'trip_completed': PushType.tripCompleted,
  'trip_cancelled': PushType.tripCancelled,
  'new_message': PushType.newMessage,
  'promo': PushType.promo,
};

/// Parses the wire `type` string. A value we do not recognise — including
/// `null` — degrades to [PushType.unknown]. The schema is assumed, so a backend
/// that later ships a type we have never heard of must not crash the app.
PushType pushTypeFromWire(String? wire) =>
    _pushTypeWire[wire] ?? PushType.unknown;

/// The current live gateway.
///
/// FCM delivery is GATED (no backend creds, gaps 15/16), so this reports the
/// gate honestly: no permission, no token, no stream. It never fabricates a
/// token and never emits a synthetic push. Mirrors `NoopStripeGateway` exactly.
///
/// This is also the gateway every widget and unit test gets for free — which is
/// precisely what keeps `flutter test` off `Firebase.initializeApp()`. If a
/// test ever needs a firebase mock, this boundary has leaked.
class NoopFcmGateway implements FcmGateway {
  /// Creates the no-op gateway.
  const NoopFcmGateway();

  @override
  Future<FcmPermission> requestPermission() async => FcmPermission.unsupported;

  @override
  Future<String?> token() async => null;

  @override
  Stream<PushMessage> onMessage() => const Stream.empty();

  @override
  Stream<PushMessage> onMessageOpened() => const Stream.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;
}

/// Exposes the active [FcmGateway]. Defaults to [NoopFcmGateway] — the GATED
/// live target. `main.dart` overrides it with `FirebaseFcmGateway` ONLY when
/// `Env.fcmConfigured` is true; `main_demo.dart` overrides it with
/// `FakeFcmGateway`. Nothing else ever constructs a gateway.
final fcmGatewayProvider = Provider<FcmGateway>(
  (ref) => const NoopFcmGateway(),
);
