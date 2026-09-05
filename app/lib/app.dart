import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'core/net/network_status.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'shared/nav/app_router.dart';
import 'features/auth/domain/auth_state.dart';
import 'shared/widgets/offline.dart';
import 'shared/widgets/startup_splash.dart';

class HoppinApp extends ConsumerStatefulWidget {
  const HoppinApp({super.key});

  @override
  ConsumerState<HoppinApp> createState() => _HoppinAppState();
}

class _HoppinAppState extends ConsumerState<HoppinApp> {
  @override
  void initState() {
    super.initState();
    // Resolve the startup state exactly once, after the first frame so the
    // provider container is ready.
    //
    // Nothing else moves the app off AuthStatus.unknown, and `redirectFor`
    // deliberately declines to redirect while unknown — so without this a
    // returning rider with a valid session lands on the login screen and
    // stays there, and the profile is never re-read to catch a missing date
    // of birth.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Hoppin Rider',
      debugShowCheckedModeBanner: false,
      // Web/desktop testers use a MOUSE, and Flutter's default behavior
      // ignores mouse drags on scrollables — which made every draggable
      // bottom sheet impossible to collapse in a browser. Accept every
      // pointer kind for drags, everywhere.
      scrollBehavior: const _AllPointersScrollBehavior(),
      // LIGHT ONLY — Ismail's product decision (2026-09-01): the design
      // pack is light-only and the derived dark theme kept surfacing
      // unreviewed. No darkTheme, no themeMode: the OS setting cannot
      // switch this app. If dark frames ever ship, the preferences
      // endpoint already whitelists a `theme` key to persist a choice.
      theme: AppTheme.light,
      routerConfig: router,
      // The design is a 430px phone screen. In a wide browser window the
      // app used to stretch edge to edge — sheets became slabs and the map
      // area a grey ocean. Clamp to a centred phone column instead; on a
      // phone-sized viewport (and everywhere off web) nothing changes.
      builder: (context, child) {
        // Offline takes over the whole screen — except on a live trip, where
        // blanking the page would take away the map, the driver's details and
        // the SOS button from someone sitting in a moving car. That screen
        // shows a reconnecting banner instead and stays usable.
        // Until bootstrap says who this is, show the splash rather than the
        // login form the router happens to have started on.
        final starting =
            ref.watch(authControllerProvider).status == AuthStatus.unknown;
        final Widget shell = starting
            ? const StartupSplash()
            : _OfflineShell(
                router: router,
                child: child ?? const SizedBox.shrink(),
              );
        if (!kIsWeb) return shell;
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 500) return shell;
            final dark = Theme.of(context).brightness == Brightness.dark;
            return ColoredBox(
              color: dark ? const Color(0xFF101016) : const Color(0xFFE7E7EC),
              child: Center(child: SizedBox(width: 430, child: shell)),
            );
          },
        );
      },
    );
  }
}

/// Accept every pointer kind for scroll/sheet drags. Flutter's default
/// excludes the mouse, which made the draggable bottom sheets impossible to
/// collapse when testing the app in a browser.
class _AllPointersScrollBehavior extends MaterialScrollBehavior {
  const _AllPointersScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

/// Replaces the current screen with [OfflineScreen] while the backend is
/// unreachable — except on the routes listed in [_offlineExempt].
///
/// A rider mid-journey must keep their map, their driver's details and the SOS
/// button. Taking those away at the exact moment the signal drops would be the
/// worst possible time to do it, so the live trip degrades to a banner instead.
class _OfflineShell extends ConsumerWidget {
  final GoRouter router;
  final Widget child;

  const _OfflineShell({required this.router, required this.child});

  static const _offlineExempt = {AppRoutes.liveTrip};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(networkStatusProvider).isOffline) return child;

    // Rebuild on navigation so the exemption follows the rider as they move.
    return AnimatedBuilder(
      animation: router.routerDelegate,
      builder: (context, _) {
        final path = router.routerDelegate.currentConfiguration.uri.path;
        if (_offlineExempt.contains(path)) return child;
        return const OfflineScreen();
      },
    );
  }
}
