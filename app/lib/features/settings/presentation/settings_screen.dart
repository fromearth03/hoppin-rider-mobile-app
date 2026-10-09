import 'package:hoppin_rider/core/localization/app_localizations.dart';
import '../../../core/preferences/device_settings.dart';
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

/// Account notification preferences and persistent device display settings.
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
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                value,
                name: 'hoppin-my-data-$day.json',
                mimeType: 'application/json',
              ),
            ],
            fileNameOverrides: ['hoppin-my-data-$day.json'],
            subject: 'My Hoppin data',
          ),
        );
      case Err():
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: AppText(
                'We could not prepare your data just now. Try again in a moment.',
              ),
            ),
          );
    }
  }

  Future<void> _saveDevice(
    DeviceSettings Function(DeviceSettings) change,
  ) async {
    final saved = await ref
        .read(deviceSettingsProvider.notifier)
        .update(change);
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('Could not save this setting. Please try again.'),
        ),
      );
    }
  }

  Future<void> _choose<T>(
    String title,
    T current,
    Map<T, String> options,
    DeviceSettings Function(DeviceSettings, T) change, {
    String? note,
  }) async {
    final value = await showModalBottomSheet<T>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: AppText(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AppText(note),
              ),
            for (final entry in options.entries)
              ListTile(
                title: AppText(entry.value),
                trailing: current == entry.key ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (value != null && mounted) await _saveDevice((s) => change(s, value));
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
    ref.listen<PreferencesSnapshot>(preferencesControllerProvider, (
      previous,
      next,
    ) {
      final message = next.error;
      if (message == null || message == previous?.error || !mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: AppText(message)));
    });

    final prefs = ref.watch(preferencesControllerProvider);
    final device = ref.watch(deviceSettingsProvider);
    final prefsController = ref.read(preferencesControllerProvider.notifier);

    return Scaffold(
      appBar: const SettingsHeader(title: 'Setting'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SettingsCard(
              children: [
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
                SettingsToggleRow(
                  icon: Icons.lightbulb_outline,
                  label: 'Do not lock the screen',
                  value: device.keepAwake,
                  onChanged: (value) =>
                      _saveDevice((s) => s.copyWith(keepAwake: value)),
                ),
                // The frame's Appearance row. Device-local, so it works before
                // the preferences have loaded and on a signed-out phone too.
                SettingsToggleRow(
                  icon: Icons.dark_mode_outlined,
                  label: 'Dark mode',
                  value: ref.watch(themeControllerProvider) == Brightness.dark,
                  onChanged: ref.read(themeControllerProvider.notifier).setDark,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsCard(
              children: [
                SettingsNavRow(
                  icon: Icons.navigation_outlined,
                  label: 'Navigation',
                  value: const {
                    NavigationApp.system: 'Device default',
                    NavigationApp.googleMaps: 'Google Maps',
                    NavigationApp.appleMaps: 'Apple Maps',
                    NavigationApp.waze: 'Waze',
                  }[device.navigation],
                  onTap: () => _choose(
                    'Navigation',
                    device.navigation,
                    const {
                      NavigationApp.system: 'Device default',
                      NavigationApp.googleMaps: 'Google Maps',
                      NavigationApp.appleMaps: 'Apple Maps',
                      NavigationApp.waze: 'Waze',
                    },
                    (s, value) => s.copyWith(navigation: value),
                    note:
                        'Used by Directions on your trip. Waze provides driving directions only.',
                  ),
                ),
                SettingsNavRow(
                  icon: Icons.straighten_outlined,
                  label: 'Distance Units',
                  value: device.distanceUnit == DistanceUnit.miles
                      ? 'Miles'
                      : 'Kilometres',
                  onTap: () =>
                      _choose('Distance Units', device.distanceUnit, const {
                        DistanceUnit.miles: 'Miles',
                        DistanceUnit.kilometres: 'Kilometres',
                      }, (s, value) => s.copyWith(distanceUnit: value)),
                ),
                SettingsNavRow(
                  icon: Icons.translate_outlined,
                  label: 'Language',
                  value: const {
                    'en': 'English',
                    'ur': 'اردو',
                    'hi': 'हिन्दी',
                  }[device.language],
                  onTap: () => _choose('Language', device.language, const {
                    'en': 'English',
                    'ur': 'اردو',
                    'hi': 'हिन्दी',
                  }, (s, value) => s.copyWith(language: value)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Privacy. A copy of everything Hoppin holds on the rider: the
            // counterpart of Delete Account below (UK GDPR right of access).
            SettingsCard(
              children: [
                SettingsActionRow(
                  icon: Icons.download_outlined,
                  label: _exporting
                      ? 'Preparing your data…'
                      : 'Download my data',
                  onTap: _exporting ? null : _downloadMyData,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsCard(
              children: [
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
