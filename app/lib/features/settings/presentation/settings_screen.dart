import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';
import 'widgets/settings_rows.dart';

/// Matches `Setting.png`: three grouped cards on a flat background.
///
/// Every control here that has no real backing renders visibly disabled with
/// a "Soon" badge, following the same disabled-until-later pattern used
/// elsewhere for out-of-scope destinations. There is no settings/preferences
/// repository anywhere in the app and `shared_preferences` is not a
/// dependency, so a toggle here cannot remember its own state -- building one
/// that resets the moment the rider leaves the screen would be a lie about a
/// setting.
///
/// Appearance is not a working theme switch either: `HoppinApp` in `app.dart`
/// hardcodes `themeMode: ThemeMode.system` with its own note that the backend
/// preference wiring is a later batch, and that file is owned by another
/// agent. So Appearance is disabled here rather than wired to a control this
/// screen has no authority to drive.
///
/// Logout is the one row with a real backend behind it: `AuthController`
/// already exposes `signOut()`.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const SettingsHeader(title: 'Setting'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SettingsCard(children: [
              SettingsToggleRow(
                icon: Icons.notifications_none,
                label: 'Notification',
                value: false,
                comingSoon: true,
              ),
              SettingsToggleRow(
                icon: Icons.volume_up_outlined,
                label: 'Driver Arrived Sound',
                value: false,
                comingSoon: true,
              ),
              SettingsToggleRow(
                icon: Icons.lightbulb_outline,
                label: 'Do not lock the screen',
                value: false,
                comingSoon: true,
              ),
              SettingsNavRow(
                icon: Icons.wb_sunny_outlined,
                label: 'Apperance',
                comingSoon: true,
              ),
            ]),
            const SizedBox(height: 20),
            const SettingsCard(children: [
              SettingsNavRow(
                icon: Icons.navigation_outlined,
                label: 'Navigation',
                comingSoon: true,
              ),
              SettingsNavRow(
                icon: Icons.straighten_outlined,
                label: 'Distance Units',
                comingSoon: true,
              ),
              SettingsNavRow(
                icon: Icons.translate_outlined,
                label: 'Language',
                comingSoon: true,
              ),
            ]),
            const SizedBox(height: 20),
            SettingsCard(children: [
              SettingsActionRow(
                icon: Icons.logout,
                label: 'Logout',
                onTap: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              ),
              const SettingsActionRow(
                icon: Icons.delete_outline,
                label: 'Delete Account',
                destructive: true,
                comingSoon: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
