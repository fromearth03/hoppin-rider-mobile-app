import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'shared/nav/app_router.dart';

class HoppinApp extends ConsumerWidget {
  const HoppinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Hoppin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follows the device until the rider sets a preference; the backend
      // stores one on /me/preferences, wired in a later batch.
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
