import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/fcm_gateway.dart';
import '../notifications/notification_centre_screen.dart';
import '../notifications/notification_feed.dart';
import '../device/device_checkin.dart';

/// Stable widget keys the shell exposes for navigation + tests. The real
/// chrome (HopTopBar / HopBottomNav) landed at convergence (08-05); these
/// keys bridge the swap so shell_nav_test keeps its behavioural anchors.
abstract final class RiderShellKeys {
  /// The bottom navigation bar (absent on top-level pushes like /profile).
  static const bottomNav = ValueKey('rider-shell-bottom-nav');

  /// The top-bar avatar → taps to the Profile hub. Mirrors HopTopBar's own
  /// internal avatar key so the tap target stays discoverable post-swap.
  static const avatar = Key('hop_top_bar_avatar');
}

/// The Figma title shown per branch in the shared [HopTopBar].
const _branchTitles = <String>['Book Ride', 'History', 'Payments', 'Support'];

/// The rider app's persistent chrome: the real [HopTopBar] (title + bell +
/// avatar-to-Profile) over the branch content, and the real [HopBottomNav]
/// (navy-capsule active tab · Book / History / Payments / Support).
///
/// Tab switches go through `navigationShell.goBranch(index)` so each branch
/// keeps its own nav stack; the avatar pushes /profile OVER the shell (that
/// route sits outside the shell, so Profile has no bottom nav).
class RiderShell extends ConsumerWidget {
  const RiderShell({required this.navigationShell, super.key});

  /// The go_router shell whose `currentIndex`/`goBranch` drive the tabs.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.hoppin.colors;
    final index = navigationShell.currentIndex;
    final avatarState = ref.watch(avatarUploadControllerProvider);
    final profile = ref.watch(profileSnapshotProvider);
    final profileAvatarUrl = profile.value?.avatarUrl.trim();
    final avatarUrl = switch (avatarState) {
      AvatarIdle(:final url) => url,
      AvatarUploaded(:final url) => url,
      _ => null,
    } ?? ((profileAvatarUrl?.isEmpty ?? true) ? null : profileAvatarUrl);
    final avatarImage = avatarUrl == null
        ? null
        : NetworkImage(avatarUrl, headers: ref.watch(imageAuthHeadersProvider));

    // 🔴 THE SHELL LAYERS. IT DOES NOT STACK.
    //
    // The chrome used to be a `Column` — bar, content, bar — and that single
    // choice is what made real glass impossible. A `BackdropFilter` filters what
    // has ALREADY BEEN PAINTED into the layer beneath it. In a Column the bar
    // and the content are siblings: there is nothing under the bar to sample, so
    // the blur is a no-op and the "glass" quietly degrades into a translucent
    // tinted box. It photographs perfectly. It is not glass.
    //
    // So the content now sits UNDER the chrome — `extendBody` +
    // `extendBodyBehindAppBar` give the body the full viewport, and the bars are
    // painted over it. The page genuinely scrolls beneath them and genuinely
    // blurs through them.
    //
    // That is a bargain with a bill attached, and the bill is paid in
    // `_ChromeInsets` below: content that can pass under the chrome can also be
    // PARKED under it. A beautiful bar that permanently hides the first row of a
    // list is not a style, it is a bug.
    return Scaffold(
      backgroundColor: colors.canvas,
      extendBody: true,
      extendBodyBehindAppBar: true,
      // 🔴 ONE BACKDROP, SAMPLED ONCE, SHARED BY BOTH BARS.
      //
      // The pill and the nav float over the SAME scrolling page, and each
      // BackdropFilter would otherwise rasterise its own private copy of it:
      // two saveLayers and two sigma-18 passes per frame, sampling identical
      // content. A full-width blur at this sigma costs ~6-9ms of raster on the
      // mid-range Android the driver app runs 8-hour shifts on, against a
      // 16.67ms budget — so the second one is not a rounding error, it is the
      // frame.
      //
      // This is the one place that knows both bars are the same material over
      // the same page, so this is where they are told to share a backdrop.
      // HopGlass picks the group up implicitly (BackdropFilter.grouped) — the
      // bars themselves stay unaware, and a HopGlass used anywhere else, with no
      // group above it, behaves exactly as it did before.
      body: BackdropGroup(
        child: Stack(
          children: [
            const _FcmTokenBinder(),
            // Below the glass. Its scroll views are handed the padding they owe
            // the chrome via the MediaQuery insets injected here.
            Positioned.fill(child: _ChromeInsets(child: navigationShell)),

            // Above it. The pill applies its own safe-area top inset (it floats
            // BELOW the notch, not under it), so it is aligned to the raw top.
            Align(
              alignment: Alignment.topCenter,
              // The HONEST bell (NOTIF-02).
              //
              // This once carried a hardcoded `notificationCount: 2` over an empty
              // `onBell: () {}` — a permanent fake "2 unread" badge on EVERY screen
              // in the app, wired to a button that did nothing. Wave 0 deleted it.
              //
              // It is back now, and it is real: the count is the SESSION feed's
              // actual unread total (0 when nothing has arrived, which hides the
              // badge), and the bell opens the notification centre. There is still
              // no notification HISTORY endpoint (gap 68) — the centre discloses
              // that itself; it does not get papered over with a fake number here.
              child: HopTopBar(
                title: _branchTitles[index],
                notificationCount: ref.watch(unreadNotificationCountProvider),
                avatarImage: avatarImage,
                // PUSH, not `go`. `go` REPLACES the current route, so `canPop()` is
                // false on the far side and the back button there falls through to
                // a hardcoded fallback — the rider taps back and is teleported to
                // the Book tab instead of returning to the tab they left. Pushing
                // keeps the stack, so `pop()` returns them where they came from.
                onBell: () => context.push(kNotificationCentreRoute),
                onAvatarTap: () => context.push('/profile'),
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: HopBottomNav(
                key: RiderShellKeys.bottomNav,
                currentIndex: index,
                // goBranch(initialLocation: …) re-pops a branch to its root when
                // its tab is re-tapped — standard indexedStack behaviour.
                onTap: (i) => navigationShell.goBranch(
                  i,
                  initialLocation: i == navigationShell.currentIndex,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for notification permission and POSTs the FCM token once the rider is
/// inside the signed-in shell. No-op gateway (tests / unconfigured build)
/// returns immediately without touching the API client.
class _FcmTokenBinder extends ConsumerStatefulWidget {
  const _FcmTokenBinder();

  @override
  ConsumerState<_FcmTokenBinder> createState() => _FcmTokenBinderState();
}

class _FcmTokenBinderState extends ConsumerState<_FcmTokenBinder> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authServiceProvider);
    _authSub = auth.onAuthStateChange.listen((_) {
      if (auth.isSignedIn) {
        unawaited(checkInRiderDevice(ref.read(profileRepositoryProvider)));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auth.isSignedIn) {
        unawaited(checkInRiderDevice(ref.read(profileRepositoryProvider)));
      }
      final gateway = ref.read(fcmGatewayProvider);
      if (gateway is NoopFcmGateway) return;
      unawaited(
        registerDeviceTokenIfSupported(
          gateway: gateway,
          profiles: ref.read(profileRepositoryProvider),
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        ),
      );
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Tells every tab how much room the glass is taking, WITHOUT taking it away.
///
/// This is the other half of the layering bargain. Now that content passes under
/// the chrome, a `ListView` that starts at y=0 starts UNDERNEATH the floating
/// pill: its first row is not merely dimmed, it is unreachable — you cannot
/// scroll UP past the top of a scroll view. The same at the bottom, under the
/// nav.
///
/// The fix has to be additive, not subtractive. Wrapping the branch in a
/// `Padding` would shrink the viewport and reintroduce exactly the `Column` we
/// just left: nothing would pass under the bars and the blur would go back to
/// having nothing to sample. So the room is granted as MediaQuery PADDING —
/// which every scroll view in Flutter already knows how to consume (via the
/// `SafeArea`/`MediaQuery` inset that `ListView` applies automatically through
/// its `padding` default, or explicitly where a screen sets its own). The
/// viewport stays full-bleed; the CONTENT inside it is inset.
///
/// The numbers are chrome tokens ([HoppinChrome.scrollPaddingTop] /
/// [HoppinChrome.scrollPaddingBottom]), so if the pill's height or its float
/// margin ever changes, the padding that clears it changes with it.
class _ChromeInsets extends StatelessWidget {
  const _ChromeInsets({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final chrome = context.hoppin.chrome;

    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          // The pill floats below the status bar, so the room it needs is its
          // own footprint ON TOP of the safe-area inset the screen already had.
          top: media.padding.top + chrome.scrollPaddingTop,
          bottom: media.padding.bottom + chrome.scrollPaddingBottom,
        ),
      ),
      child: child,
    );
  }
}
