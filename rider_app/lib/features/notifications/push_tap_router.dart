import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'fcm_gateway.dart';
import 'notification_centre_screen.dart' show kNotificationCentreRoute;
import 'notification_feed.dart';

/// Turns a tapped [PushMessage] into a route.
///
/// The ONLY place a push becomes navigation — mirroring the riblet rule that
/// `trip_router.dart` is the only place trip nav happens.
///
/// Precedence:
///   1. the backend's `deep_link`, **if and only if it is allowlisted**;
///   2. a route derived from `type` + `ride_id`;
///   3. the notification centre.
///
/// An unknown or non-allowlisted target NEVER navigates blind. The rider lands
/// on the centre, where they can read the notification for themselves.
String routeForPush(PushMessage m) {
  final link = m.deepLink;
  if (link != null && isAllowlistedPushTarget(link)) return link;

  final id = m.rideId;
  if (id == null || id.isEmpty) return kNotificationCentreRoute;

  return switch (m.type) {
    PushType.newMessage => '/trip/$id/chat',
    PushType.tripCompleted => '/trip/$id/receipt',
    PushType.driverAssigned ||
    PushType.driverArriving ||
    PushType.driverArrived ||
    PushType.tripStarted ||
    PushType.tripCancelled =>
      '/trip/$id',
    PushType.promo || PushType.unknown => kNotificationCentreRoute,
  };
}

/// The in-app path prefixes a push is permitted to steer the app to.
///
/// A push payload is attacker-influenceable in exactly the way `ad.target_url`
/// is (gap 36 asks for client-side allowlisting of ad targets — no such
/// allowlist existed in the repo, so this one is written here and partially
/// satisfies that ask; the ad path can reuse it).
const List<String> _allowedPushPrefixes = <String>[
  '/trip/',
  '/notifications',
  '/history',
  '/payments',
  '/support',
  '/profile',
];

/// True only for a target we recognise as an in-app path.
///
/// Rejects: anything carrying ANY URI scheme at all (web, script, dial and mail
/// schemes alike — the check is `Uri.hasScheme`, not a blocklist), anything with
/// a host (`//evil`), any traversal (`..`), and anything that is not one of the
/// known prefixes. When in doubt, reject — the fallback is the notification
/// centre, which is always safe and always honest.
///
/// ⚠️ The banned schemes are deliberately NOT spelled out literally here. The
/// phase gate greps `lib/` for the dial scheme and must find nothing; a comment
/// *explaining* the prohibition would trip that grep permanently — the same trap
/// Wave 0 documented for the `SEAM(#` literal. Naming a rule must not violate it.
bool isAllowlistedPushTarget(String target) {
  final t = target.trim();
  if (t.isEmpty) return false;

  // Must be a bare in-app path.
  if (!t.startsWith('/')) return false;

  // `//host` is a protocol-relative URL, not a path.
  if (t.startsWith('//')) return false;

  // Any scheme, any traversal, any backslash trickery.
  if (t.contains(':')) return false;
  if (t.contains('..')) return false;
  if (t.contains(r'\')) return false;

  return _allowedPushPrefixes.any(
    (prefix) => prefix.endsWith('/')
        ? t.startsWith(prefix)
        : t == prefix || t.startsWith('$prefix/') || t.startsWith('$prefix?'),
  );
}

/// Consumes tapped pushes and cold-start pushes, and navigates.
///
/// Mounted once, high in the tree, wrapping the router's child. Because
/// `NoopFcmGateway.onMessageOpened()` is an empty stream, this host is a genuine
/// no-op in every test and in the demo — it never fires, never navigates, and
/// costs nothing.
///
/// ⚠️ NOT MOUNTED BY THIS LANE. `router.dart` is contended (Lane E owns it), so
/// Lane E wraps the router child with this host. Until it does, the host is
/// exported and inert — which is exactly what it would be anyway, since the live
/// gateway is the no-op.
///
/// ⚠️ KNOWN TRAP for Lane E: `/trip/:id` is NOT on the signed-out redirect
/// allowlist (`/login /signup /verify /reset`), and post-login the redirect
/// hard-codes `return '/book'`. So a notification tap arriving before auth
/// settles lands silently on Book, not the trip. The fix belongs in
/// `router.dart` — see this plan's SUMMARY.
class PushNavigationHost extends ConsumerStatefulWidget {
  /// Wraps [child] with the tapped-push listener.
  const PushNavigationHost({required this.child, super.key});

  /// The app content this host wraps.
  final Widget child;

  @override
  ConsumerState<PushNavigationHost> createState() => _PushNavigationHostState();
}

class _PushNavigationHostState extends ConsumerState<PushNavigationHost> {
  @override
  void initState() {
    super.initState();
    // Cold start: a push may have launched the app. One-shot, and `null` on the
    // no-op — so this does nothing today.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeInitial());
  }

  Future<void> _consumeInitial() async {
    final m = await ref.read(fcmGatewayProvider).initialMessage();
    if (m == null || !mounted) return;
    ref.read(notificationFeedProvider.notifier).add(m);
    if (!mounted) return;
    context.go(routeForPush(m));
  }

  @override
  Widget build(BuildContext context) {
    // A tapped push: record it in the feed (so the centre is honest about what
    // arrived) and navigate to the allowlisted route.
    ref.listen<AsyncValue<PushMessage>>(openedPushProvider, (_, next) {
      final m = next.value;
      if (m == null || !mounted) return;
      ref.read(notificationFeedProvider.notifier).add(m);
      context.go(routeForPush(m));
    });
    return widget.child;
  }
}

/// The stream of pushes the rider TAPPED. Empty on the no-op default.
final openedPushProvider = StreamProvider<PushMessage>(
  (ref) => ref.watch(fcmGatewayProvider).onMessageOpened(),
);
