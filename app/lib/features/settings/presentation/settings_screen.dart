import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'widgets/appearance_picker_sheet.dart';
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
/// Appearance is the one row with a real effect: it opens a picker sheet
/// (`appearance_picker_sheet.dart`) that writes to `themeModeProvider`,
/// which `HoppinApp` reads for `MaterialApp.themeMode`. The choice changes
/// the resolved theme immediately, for the current session only -- there is
/// still no settings/preferences repository and `shared_preferences` is not
/// a dependency, so nothing here claims to survive an app restart.
///
/// Distance Units stays disabled: distance is rendered ad hoc inline in
/// `trip_details_screen.dart` and `ride_complete_screen.dart` (both outside
/// this feature), with no shared formatter to thread a units preference
/// through. Wiring a toggle here would either require editing screens this
/// pass does not own, or ship a control that changes nothing -- so it stays
/// off, honestly.
///
/// Map provider stays disabled too: there is no Maps SDK key and
/// `MapPlaceholder` stands in for the map, so choosing between two map
/// providers that do not render anything would be meaningless.
///
/// Logout is the one other row with a real backend behind it: `AuthController`
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
            SettingsCard(children: [
              const SettingsToggleRow(
                icon: Icons.notifications_none,
                label: 'Notification',
                value: false,
                comingSoon: true,
              ),
              const SettingsToggleRow(
                icon: Icons.volume_up_outlined,
                label: 'Driver Arrived Sound',
                value: false,
                comingSoon: true,
              ),
              const SettingsToggleRow(
                icon: Icons.lightbulb_outline,
                label: 'Do not lock the screen',
                value: false,
                comingSoon: true,
              ),
              SettingsNavRow(
                icon: Icons.wb_sunny_outlined,
                label: 'Apperance',
                onTap: () => showAppearancePickerSheet(context),
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
