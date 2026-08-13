import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import 'fcm_gateway.dart';

/// One notification the client actually SAW arrive.
///
/// Deliberately NOT called `Notification` (that name is taken by Flutter) and
/// deliberately not persisted — see [notificationFeedProvider].
@immutable
class AppNotification {
  /// Creates a session notification.
  const AppNotification({
    required this.id,
    required this.title,
    required this.receivedAt,
    this.body,
    this.read = false,
    this.rideId,
    this.deepLink,
    this.type = PushType.unknown,
  });

  /// Builds one from a push. The id is local — the backend does not issue one
  /// (there is no notification record endpoint; gap 68).
  factory AppNotification.fromPush(PushMessage m, {required String id}) =>
      AppNotification(
        id: id,
        title: m.title ?? _titleFor(m.type),
        body: m.body,
        receivedAt: m.sentAt ?? DateTime.now(),
        rideId: m.rideId,
        deepLink: m.deepLink,
        type: m.type,
      );

  /// Session-local identity.
  final String id;

  /// The headline shown on the card.
  final String title;

  /// The supporting line.
  final String? body;

  /// When this client saw it.
  final DateTime receivedAt;

  /// Local read state. There is no server read-state to sync with (gap 68).
  final bool read;

  /// The trip this is about, when it is about one.
  final String? rideId;

  /// The backend's requested route, if any. Allowlisted before it is obeyed.
  final String? deepLink;

  /// The event kind.
  final PushType type;

  /// Returns a copy with [read] flipped.
  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        receivedAt: receivedAt,
        read: read ?? this.read,
        rideId: rideId,
        deepLink: deepLink,
        type: type,
      );

  static String _titleFor(PushType type) => switch (type) {
        PushType.driverAssigned => 'Your driver is on the way',
        PushType.driverArriving => 'Your driver is arriving',
        PushType.driverArrived => 'Your driver has arrived',
        PushType.tripStarted => 'Your trip has started',
        PushType.tripCompleted => 'Your trip is complete',
        PushType.tripCancelled => 'Your trip was cancelled',
        PushType.newMessage => 'New message from your driver',
        PushType.promo => 'Hoppin',
        PushType.unknown => 'Hoppin',
      };
}

/// The notification centre's feed.
///
/// SESSION-LOCAL by necessity. There is no `GET /me/notifications` (gap 68), so
/// the only notifications this client can honestly show are the ones it saw
/// arrive. It is fed by:
///
///   (a) `FcmGateway.onMessage()` — real pushes. Empty on the no-op, i.e. today.
///   (b) trip-phase transitions from the 3s poll — the POLL FLOOR is what
///       actually makes the centre non-empty today, which is the entire point:
///       push is ADDITIVE, the poll is the correctness floor.
///
/// NOT persisted. A reload empties it, and that is CORRECT — a local store
/// pretending to be server history is exactly the fake-as-live the no-holes rule
/// forbids, and it would diverge permanently from the server once the history
/// endpoint ships.
final notificationFeedProvider =
    NotifierProvider<NotificationFeed, List<AppNotification>>(
  NotificationFeed.new,
);

/// The unread count that drives the top-bar bell badge.
///
/// A REAL count. Wave 0 deleted a hardcoded `notificationCount: 2` that shipped
/// a permanent fake unread badge on every screen. 0 over an empty feed is the
/// honest answer, and `HopTopBar` hides the badge at 0.
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationFeedProvider).where((n) => !n.read).length;
});

/// The session store behind [notificationFeedProvider].
class NotificationFeed extends Notifier<List<AppNotification>> {
  /// The live feed — starts empty and listens to the gateway.
  NotificationFeed() : _seed = null;

  /// A pre-seeded feed. TEST/DEMO composition only — it does not subscribe to
  /// the gateway, so nothing arrives behind the test's back.
  NotificationFeed.seeded(List<AppNotification> seed) : _seed = seed;

  final List<AppNotification>? _seed;
  int _counter = 0;

  @override
  List<AppNotification> build() {
    final seed = _seed;
    if (seed != null) return List<AppNotification>.unmodifiable(seed);

    // Foreground pushes land here. Empty on the no-op default (today), which is
    // why the centre's cold start renders the seam rung rather than a list.
    final sub = ref.watch(fcmGatewayProvider).onMessage().listen(add);
    ref.onDispose(sub.cancel);

    return const <AppNotification>[];
  }

  /// Records a push that arrived. Newest first.
  void add(PushMessage m) {
    final n = AppNotification.fromPush(m, id: 'local-${_counter++}');
    state = <AppNotification>[n, ...state];
  }

  /// Records a poll-derived event — the trip-phase transitions the 3s poll sees.
  /// This is what makes the centre non-empty today.
  void addLocal({
    required String title,
    String? body,
    String? rideId,
    PushType type = PushType.unknown,
  }) {
    state = <AppNotification>[
      AppNotification(
        id: 'local-${_counter++}',
        title: title,
        body: body,
        receivedAt: DateTime.now(),
        rideId: rideId,
        type: type,
      ),
      ...state,
    ];
  }

  /// Marks every session notification read. Purely LOCAL read-state — it costs
  /// nothing and lies about nothing, so unlike "delete all" it stays enabled.
  void markAllRead() {
    state = <AppNotification>[
      for (final n in state) n.read ? n : n.copyWith(read: true),
    ];
  }
}

/// The outcome of a device-token registration attempt. Every skip is a NAMED,
/// disclosed outcome — never a silent no-op that reads like success.
enum TokenRegistration {
  /// The token was registered with a contract-legal `device_os`.
  registered,

  /// No contract-legal `device_os` for this platform (desktop native).
  gatedNoWebPlatform,

  /// GATED on gaps 15/16: the gateway has no token to register (the live
  /// default is the no-op, because the backend has no FCM credentials).
  gatedNoToken,
}

/// Registers this device's FCM token — but ONLY when the platform maps to a
/// `device_os` value the contract accepts (`ios` / `android` / `web`).
Future<TokenRegistration> registerDeviceTokenIfSupported({
  required FcmGateway gateway,
  required ProfileRepository profiles,
  required bool isWeb,
  required TargetPlatform platform,
}) async {
  final deviceOs = contractDeviceOs(isWeb: isWeb, platform: platform);
  if (deviceOs == null) return TokenRegistration.gatedNoWebPlatform;

  final permission = await gateway.requestPermission();
  if (permission != FcmPermission.granted) {
    return TokenRegistration.gatedNoToken;
  }

  final token = await gateway.token();
  if (token == null || token.isEmpty) return TokenRegistration.gatedNoToken;

  await profiles.registerDeviceToken(fcmToken: token, deviceOs: deviceOs);
  return TokenRegistration.registered;
}

/// The `device_os` value the contract accepts for this platform, or `null` when
/// there is none. Web is `"web"` even when Chrome reports an Android/iOS host.
String? contractDeviceOs({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return 'web';
  return switch (platform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => null,
  };
}
