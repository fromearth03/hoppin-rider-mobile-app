import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'shared/nav/app_router.dart';

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
    return MaterialApp.router(
      title: 'Hoppin Rider',
      debugShowCheckedModeBanner: false,
      // LIGHT ONLY — Ismail's product decision (2026-09-01): the design
      // pack is light-only and the derived dark theme kept surfacing
      // unreviewed. No darkTheme, no themeMode: the OS setting cannot
      // switch this app. If dark frames ever ship, the preferences
      // endpoint already whitelists a `theme` key to persist a choice.
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      // The design is a 430px phone screen. In a wide browser window the
      // app used to stretch edge to edge — sheets became slabs and the map
      // area a grey ocean. Clamp to a centred phone column instead; on a
      // phone-sized viewport (and everywhere off web) nothing changes.
      builder: (context, child) {
        if (!kIsWeb || child == null) return child ?? const SizedBox.shrink();
        return LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth <= 500) return child;
          final dark = Theme.of(context).brightness == Brightness.dark;
          return ColoredBox(
            color: dark ? const Color(0xFF101016) : const Color(0xFFE7E7EC),
            child: Center(
              child: SizedBox(width: 430, child: child),
            ),
          );
        });
      },
    );
  }
}
