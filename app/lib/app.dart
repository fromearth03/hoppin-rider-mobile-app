import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
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
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Rider's in-session choice from Settings > Appearance. Held in memory
      // only -- shared_preferences is not a dependency, so this resets to
      // ThemeMode.system on every app restart rather than persisting.
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
