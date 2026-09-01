import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/profile_repository.dart';
import '../widgets/profile_avatar.dart';
import 'app_router.dart';
import 'logout_confirm.dart';

/// The navigation drawer — `Side Nav Bar.png`.
///
/// All eight destinations are rendered and reachable. Where a screen's backend
/// does not exist yet — scheduled rides and ride history are both recorded as
/// later milestones — the screen itself says so honestly rather than the
/// drawer hiding the destination or greying it out. `_Item` keeps its disabled
/// state for whatever comes next.
///
/// Destinations `push` rather than `go`. Every one of these screens has a back
/// arrow, and `go` replaces the route instead of stacking it, so the arrow
/// would have nothing to pop and the browser's back button would leave the
/// app.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider).profile;

    return Drawer(
      // The design's panel stops short of the right edge and rounds that
      // corner.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _Header(profile: profile),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _Item(
                    icon: Icons.person_outline,
                    label: 'Personal Information',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.personalInformation);
                    },
                  ),
                  _Item(
                    icon: Icons.calendar_today_outlined,
                    label: 'Schedule Rides',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.scheduleRide);
                    },
                  ),
                  _Item(
                    icon: Icons.campaign_outlined,
                    label: 'Promotional',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.promotional);
                    },
                  ),
                  _Item(
                    icon: Icons.history,
                    label: 'Ride History',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.rideHistory);
                    },
                  ),
                  _Item(
                    icon: Icons.credit_card,
                    label: 'Payments',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.paymentMethods);
                    },
                  ),
                  _Item(
                    icon: Icons.notifications_none,
                    label: 'Notifications',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.notifications);
                    },
                  ),
                  _Item(
                    icon: Icons.support_agent_outlined,
                    label: 'Help & Support',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.helpSupport);
                    },
                  ),
                  _Item(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppRoutes.settings);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _Item(
              icon: Icons.logout,
              label: 'Logout',
              // Confirmed first, as `Logout.png` draws it. One stray tap on
              // the bottom drawer row otherwise ends the session.
              onTap: () async {
                final confirmed = await confirmLogout(context);
                if (!confirmed || !context.mounted) return;
                Navigator.of(context).pop();
                ref.read(authControllerProvider.notifier).signOut();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final RiderProfile? profile;
  const _Header({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile?.fullName.trim();
    final rating = profile?.rating;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          // The real photo, fetched with the bearer token; initials only
          // while it loads or when the rider has none.
          ProfileAvatar(avatarUrl: profile?.avatarUrl, name: name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (name == null || name.isEmpty) ? 'Rider' : name,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 19),
                  overflow: TextOverflow.ellipsis,
                ),
                // No stars until a driver has actually rated this rider. The
                // design shows 4.31 (150); a fabricated 5.0 under a new
                // rider's name is worse than showing nothing.
                if (rating != null) ...[
                  const SizedBox(height: 2),
                  _Stars(rating: rating, count: profile!.ratingCount),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.lightTextSecondary),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final double rating;
  final int count;

  const _Stars({required this.rating, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : (rating >= i - 0.5 ? Icons.star_half : Icons.star_border),
            // The frame's gold stars sit a touch larger than caption text.
            size: 14,
            color: AppColors.warning,
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${rating.toStringAsFixed(2)} ($count)',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A destination. With no [onTap] it renders visibly disabled — the seven
/// milestone-2 destinations.
class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _Item({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final color = enabled
        ? theme.textTheme.bodyLarge?.color
        : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontSize: 15.5, color: color),
                    ),
                  ),
                  if (!enabled)
                    Text(
                      'Soon',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 11,
                        color: color,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}
