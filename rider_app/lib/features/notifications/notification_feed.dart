import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';

import 'fcm_gateway.dart';

/// One notification shown by the client, whether loaded from history or
/// received live through FCM.
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
        id: m.notificationId ?? id,
        title: m.title ?? _titleFor(m.type),
        body: m.body,
        receivedAt: m.sentAt ?? DateTime.now(),
        rideId: m.rideId,
        deepLink: m.deepLink,
        type: m.type,
      );

  factory AppNotification.fromHistory(UserNotification n) => AppNotification(
    id: n.id,
    title: n.title,
    body: n.body.isEmpty ? null : n.body,
    receivedAt: n.createdAt,
    read: n.isRead,
    rideId: n.rideId,
    deepLink: n.deepLink,
    type: pushTypeFromWire(n.type),
  );

  /// Server id for history records, or a local id for a live event.
  final String id;

  /// The headline shown on the card.
  final String title;

  /// The supporting line.
  final String? body;

  /// When this client saw it.
  final DateTime receivedAt;

  /// Read state returned by the server for history, or local state for a live
  /// event until the next history refresh.
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

/// The notification centre's merged server-history and live feed.
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
  bool _historyMerged = false;

  @override
  List<AppNotification> build() {
    final seed = _seed;
    if (seed != null) return List<AppNotification>.unmodifiable(seed);

    final sub = ref.watch(fcmGatewayProvider).onMessage().listen(add);
    ref.onDispose(sub.cancel);

    return const <AppNotification>[];
  }

  /// Records a push that arrived. Newest first.
  void add(PushMessage m) {
    final n = AppNotification.fromPush(m, id: 'local-${_counter++}');
    state = <AppNotification>[n, ...state];
  }

  /// Merges durable history without duplicating live records.
  void mergeHistory(List<UserNotification> history) {
    if (_historyMerged && history.isEmpty) return;
    _historyMerged = true;
    final byId = <String, AppNotification>{
      for (final item in state) item.id: item,
    };
    for (final item in history) {
      byId[item.id] = AppNotification.fromHistory(item);
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    state = List<AppNotification>.unmodifiable(merged);
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

  /// Marks every notification read locally and persists the same action.
  void markAllRead() {
    state = <AppNotification>[
      for (final n in state) n.read ? n : n.copyWith(read: true),
    ];
    try {
      unawaited(
        ref
            .read(notificationsRepositoryProvider)
            .markAllRead()
            .catchError((_) {}),
      );
    } on Object {
      // A local/demo composition may not have an authenticated API client.
      // The local state change still remains useful in that mode.
    }
  }
}

/// Loads the user's durable notification history when the centre is opened.
final notificationHistoryProvider =
    FutureProvider.autoDispose<List<UserNotification>>((ref) {
      return ref.watch(notificationsRepositoryProvider).list();
    });

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

  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await profiles.registerDeviceToken(fcmToken: token, deviceOs: deviceOs);
      return TokenRegistration.registered;
    } on ApiException catch (error) {
      if (error.statusCode >= 400 && error.statusCode < 500) {
        return TokenRegistration.gatedNoToken;
      }
    } on Exception {
      // Retry transient network/server failures below.
    }
    await Future<void>.delayed(Duration(seconds: attempt + 1));
  }
  return TokenRegistration.gatedNoToken;
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
