import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_status.dart';
import '../../core/theme/colors.dart';
import 'hoppin_logo.dart';

/// Blocks the entire app while the operator has the platform down, or while
/// this build is below the required floor.
///
/// Above the router rather than inside it: a maintenance screen the rider can
/// navigate away from is not a maintenance screen, and every route — including
/// the ones reached by a deep link — has to be behind it.
class AppGate extends ConsumerWidget {
  final Widget child;

  const AppGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loading and error both fall through to the app. The status check must
    // never be the reason a rider cannot use it — see AppStatus.unknown.
    //
    // valueOrNull, NOT value: AsyncValue.value RETHROWS on an error, so a
    // failed status check would have taken the whole app down from the widget
    // that exists to keep the app usable.
    final status = ref.watch(appStatusProvider).valueOrNull ?? AppStatus.unknown;

    if (status.maintenanceMode) {
      return _Blocked(
        icon: Icons.construction_outlined,
        title: 'Hoppin is down for maintenance',
        body: status.maintenanceMessage ??
            "We're making some improvements and will be back shortly. "
                'Thanks for your patience.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(appStatusProvider),
      );
    }

    if (status.forceUpdateRequired) {
      return _Blocked(
        icon: Icons.system_update_alt,
        title: 'Update required',
        // No "open the store" button: url_launcher is not a dependency (see
        // help_support_screen.dart), and a button that does nothing is worse
        // than telling the rider plainly where to go.
        body: 'This version of Hoppin is no longer supported. '
            'Update it from your app store to keep booking rides.',
        actionLabel: 'I have updated',
        onAction: () => ref.invalidate(appStatusProvider),
      );
    }

    return child;
  }
}

class _Blocked extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _Blocked({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HoppinLogo(height: 34),
                const SizedBox(height: 40),
                Icon(icon, size: 56, color: AppColors.primary),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: AppColors.navy),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.lightTextSecondary),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 220,
                  child: FilledButton(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
