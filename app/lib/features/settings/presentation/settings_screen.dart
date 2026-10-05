import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/result.dart';

import '../../../shared/nav/app_router.dart';
import '../../../shared/nav/logout_confirm.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/theme/theme_controller.dart';
import '../application/preferences_controller.dart';
import '../data/data_export_repository.dart';
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
  bool _exporting = false;

  /// Downloads the rider's data and hands it to the system share sheet, so
  /// they can save it to Files or send it to themselves. The file never
  /// touches app storage beyond the share handoff.
  Future<void> _downloadMyData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(dataExportRepositoryProvider).download();
    if (!mounted) return;
    setState(() => _exporting = false);
    switch (result) {
      case Ok(:final value):
        final day = DateTime.now().toIso8601String().substring(0, 10);
        await SharePlus.instance.share(ShareParams(
          files: [
            XFile.fromData(value,
                name: 'hoppin-my-data-$day.json', mimeType: 'application/json'),
          ],
          fileNameOverrides: ['hoppin-my-data-$day.json'],
          subject: 'My Hoppin data',
        ));
      case Err():
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
              content: Text(
                  'We could not prepare your data just now. Try again in a moment.')));
    }
  }

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
              // The frame's Appearance row. Device-local, so it works before
              // the preferences have loaded and on a signed-out phone too.
              SettingsToggleRow(
                icon: Icons.dark_mode_outlined,
                label: 'Dark mode',
                value: ref.watch(themeControllerProvider) == Brightness.dark,
                onChanged: ref.read(themeControllerProvider.notifier).setDark,
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
            // Privacy. A copy of everything Hoppin holds on the rider: the
            // counterpart of Delete Account below (UK GDPR right of access).
            SettingsCard(children: [
              SettingsActionRow(
                icon: Icons.download_outlined,
                label: _exporting ? 'Preparing your data…' : 'Download my data',
                onTap: _exporting ? null : _downloadMyData,
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
                // The frame draws this as a plain navy row with the trash
                // glyph — the destructive red lives on the confirm screen
                // behind it, not here.
                onTap: () => context.push(AppRoutes.deleteAccount),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
