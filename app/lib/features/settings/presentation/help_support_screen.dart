import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import 'widgets/settings_card.dart';
import 'widgets/settings_header.dart';

/// There is no Help & Support screen in the Figma pack. Built in the same
/// visual language as `Setting.png` (flat header, grouped rounded cards on a
/// flat background) rather than inventing a new style for it.
///
/// Content is static FAQ copy and contact details -- the only things this
/// screen can honestly show given there is no support/FAQ backend anywhere
/// in the API and `url_launcher` is not a dependency, so contact details are
/// plain text rather than tappable mailto/tel links that would need it.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = [
    (
      'How do I book a ride?',
      'Enter your pickup and destination on the home screen, choose a '
          'vehicle type, then confirm to be matched with a driver.',
    ),
    (
      'How do I cancel a ride?',
      'Open the active trip screen and tap Cancel Ride. Cancellation '
          'policies are shown before you confirm a booking.',
    ),
    (
      'How is my fare calculated?',
      'FAQ: fares are based on distance, time and the vehicle category you '
          'choose. Any waiting time is added once the trip is under way.',
    ),
    (
      'How do I add or change a payment card?',
      'Go to Payments from the side menu to add, remove or set a default '
          'card. Rides are always charged to your default card.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const SettingsHeader(title: 'Help & Support'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Frequently asked questions',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SettingsCard(
              children: [
                for (final faq in _faqs)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(faq.$1,
                            style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Text(faq.$2, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Contact us', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SettingsCard(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Icon(Icons.mail_outline,
                          size: 22, color: theme.iconTheme.color),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Email support',
                                style: theme.textTheme.bodyLarge),
                            const SizedBox(height: 2),
                            Text('support@hoppin.app',
                                style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 22, color: theme.iconTheme.color),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'In-app live chat and phone support are not '
                          'available yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.brightness == Brightness.light
                                ? AppColors.lightTextSecondary
                                : AppColors.darkTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
