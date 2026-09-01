import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/nav/app_router.dart';
import '../../../shared/nav/logout_confirm.dart';
import '../../auth/application/auth_controller.dart';
import '../application/preferences_controller.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';
import 'widgets/settings_rows.dart';

/// Matches `Setting.png`: three grouped cards on a flat background.
///
/// Notification and Driver Arrived Sound are live: `GET`/`PATCH
/// /me/preferences` stores per-user preferences as `users.preferences` JSONB,
/// and the two toggles map onto the server's whitelisted keys
/// `push_trip_updates` and `sound_offer_chime`. They persist across restarts
/// because the server, not the device, holds them.
///
/// "Do not lock the screen" stays disabled: it is a device wakelock, not a
/// server preference. The whitelist in `preferences_handler.go` has no key for
/// it, and `wakelock_plus` is not a dependency — so there is nothing to write
/// to and nothing to keep the screen awake with.
///
/// Both live toggles stay disabled until the first read succeeds. A switch
/// rendered live over a failed read would let the rider "turn off" something
/// whose real state the app never learned, then PATCH that guess over server
/// truth.
///
/// Every other control here that has no real backing renders visibly disabled
/// with a "Soon" badge, following the same disabled-until-later pattern used
/// elsewhere for out-of-scope destinations.
///
/// There is no Appearance row: the app is light-only by product decision
/// (2026-09-01) — the design pack is light-only. The server whitelists a
/// `theme` preference key should dark frames ever ship.
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
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: reading a StateNotifier during initState would
    // rebuild a widget that is still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(preferencesControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    // A rolled-back switch snapping silently back to its old position looks
    // like a bug; the server's own words say why it did.
    ref.listen<PreferencesSnapshot>(preferencesControllerProvider,
        (previous, next) {
      final message = next.error;
      if (message == null || message == previous?.error || !mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });

    final prefs = ref.watch(preferencesControllerProvider);
    final prefsController = ref.read(preferencesControllerProvider.notifier);

    return Scaffold(
      appBar: const SettingsHeader(title: 'Setting'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SettingsCard(children: [
              SettingsToggleRow(
                icon: Icons.notifications_none,
                label: 'Notification',
                value: prefs.pushTripUpdates,
                // Null until the first read lands: the switch renders itself
                // genuinely inert rather than inviting a tap we could not
                // honestly save.
                onChanged: prefs.isReady
                    ? prefsController.setPushTripUpdates
                    : null,
              ),
              SettingsToggleRow(
                icon: Icons.volume_up_outlined,
                label: 'Driver Arrived Sound',
                value: prefs.soundOfferChime,
                onChanged: prefs.isReady
                    ? prefsController.setSoundOfferChime
                    : null,
              ),
              // No server key and no wakelock plugin — genuinely nothing to
              // write to, and nothing that would keep the screen awake.
              const SettingsToggleRow(
                icon: Icons.lightbulb_outline,
                label: 'Do not lock the screen',
                value: false,
                comingSoon: true,
              ),
              // The frame draws an Appearance row, but the app is light-only
              // by product decision (2026-09-01) — a picker with nothing to
              // switch would be the exact lying control this app refuses to
              // ship, so the row is gone rather than inert.
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
                // Same confirm as the drawer — `Logout.png` applies to every
                // logout surface, and this row otherwise ends the session on
                // one stray tap.
                onTap: () async {
                  final confirmed = await confirmLogout(context);
                  if (!confirmed || !context.mounted) return;
                  ref.read(authControllerProvider.notifier).signOut();
                },
              ),
              SettingsActionRow(
                icon: Icons.delete_outline,
                label: 'Delete Account',
                destructive: true,
                onTap: () => context.push(AppRoutes.deleteAccount),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
