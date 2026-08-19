import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../notifications/notification_centre_screen.dart'
    show kNotificationCentreRoute;
import '../notifications/notification_feed.dart'
    show unreadNotificationCountProvider;

/// Stable widget keys the Profile hub exposes for tests. Kept across the
/// 08-05 chrome swap.
abstract final class ProfileScreenKeys {
  /// The full-screen Profile hub root — its presence proves the avatar push
  /// landed and (paired with the shell's bottom nav being absent) that
  /// Profile covers the shell.
  static const root = ValueKey('profile-screen-root');
}

/// A single Profile-hub row spec: leading navy icon + label + tap intent.
///
/// [onTap] is REQUIRED and non-nullable as of Phase 12. It was nullable, and the
/// card below fell back to `?? () {}` — a full tap ripple over a silent no-op,
/// which is the Wave-0 lie in its purest form: the affordance says "this does
/// something" and it does nothing. Every hub row now reaches a real screen, so
/// the type says so and the fallback is gone. A future row with nowhere to go
/// will not compile, which is the point.
class _ProfileRow {
  const _ProfileRow(this.icon, this.label, {required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The Profile HUB (Figma #34) — the avatar-tap target from the shell's top
/// bar. A full-screen surface (NO bottom nav; it's a top-level push over the
/// shell): the real [HopTopBar] ("My Profile" + back + bell + avatar), a
/// centred identity block (avatar · name · location), and a card of
/// [HopListRow]s (Personal Information · My Trips · Promotions · Help &
/// Support · Settings · Logout).
///
/// Rows are navigation stubs this phase (the feature screens are Phases
/// 10/12); this renders the hub structure to Figma. It is fidelity-gate
/// reference screen #2.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    ref.watch(profileSnapshotProvider);
    ref.listen(profileSnapshotProvider, (_, next) {
      next.whenData((profile) {
        final current = ref.read(avatarUploadControllerProvider);
        if (current is AvatarUploading || current is AvatarUploaded) return;
        ref
            .read(avatarUploadControllerProvider.notifier)
            .seed(profile.avatarUrl.isEmpty ? null : profile.avatarUrl);
      });
    });
    final auth = ref.watch(authServiceProvider);
    final avatar = ref.watch(avatarUploadControllerProvider);
    final avatarUrl = switch (avatar) {
      AvatarIdle(:final url) => url,
      AvatarUploaded(:final url) => url,
      _ => null,
    };
    final avatarImage = avatarUrl == null
        ? null
        : NetworkImage(avatarUrl, headers: ref.watch(imageAuthHeadersProvider));

    // WAVE-0: five of these six rows were dead — `onTap: null`, falling through
    // to `onTap: rows[i].onTap ?? () {}`, which gave a full tap ripple and did
    // NOTHING. Wave 0 replaced three of them with an honest "coming in Phase 12"
    // sheet rather than a silent no-op.
    //
    // PHASE 12: all six rows now reach a REAL screen, and the interim sheet is
    // deleted. Note the fourth row in particular:
    //
    // 🔴 Help & Support went to `/support` — the ticket TAB. That is a DIFFERENT
    // screen with a different job. The frame the hub actually promises (Figma
    // #38) is FAQ + Contact + Legal, with no tickets on it at all, and it had
    // NEVER BEEN BUILT. Nobody noticed, for the app's entire life, precisely
    // because the row LOOKED wired: it navigated, so it read as done. A row that
    // goes to the wrong screen is harder to spot than one that goes nowhere.
    // The four `/profile/*` leaves are PUSHED, not `go`-ne to. `go` REPLACES
    // the route, so `canPop()` on the sub-screen is false and its back button
    // falls through to a fallback — the rider taps back from Settings and lands
    // on Book instead of returning to the hub they opened it from. `push` keeps
    // the stack, so back means back.
    //
    // "My Trips" stays a `go`: /history is a shell TAB, not a leaf. Pushing a
    // tab over the shell would bury the bottom nav under it.
    final rows = <_ProfileRow>[
      _ProfileRow(
        Icons.person,
        'Personal Information',
        onTap: () => context.push('/profile/personal'),
      ),
      _ProfileRow(
        Icons.history,
        'My Trips',
        onTap: () => context.go('/history'),
      ),
      _ProfileRow(
        Icons.card_giftcard,
        'Promotions',
        onTap: () => context.push('/profile/promotions'),
      ),
      _ProfileRow(
        Icons.help,
        'Help & Support',
        // RE-POINTED (Phase 12). Was `/support` — the ticket tab. See above.
        onTap: () => context.push('/profile/help'),
      ),
      _ProfileRow(
        Icons.settings,
        'Settings',
        onTap: () => context.push('/profile/settings'),
      ),
      _ProfileRow(
        Icons.logout,
        'Logout',
        // Reuse the existing sign-out call site. The router's auth redirect
        // then bounces to /login.
        onTap: () => auth.signOut(),
      ),
    ];

    return Scaffold(
      key: ProfileScreenKeys.root,
      backgroundColor: colors.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // THE BELL BELONGS HERE TOO.
          //
          // Profile sits OUTSIDE the shell, so it does not inherit the shell's
          // top bar — and the bell lives on that bar. This screen built its own
          // bar and passed no `onBell`, so no bell rendered: there was simply no
          // control anywhere on the account surface that reached the
          // notification centre. The rider reported it as "I can't get from
          // Profile to Notifications", and they were right — nothing could.
          //
          // The count is the same honest session unread total the shell shows
          // (0 hides the badge). It is NOT the fake hardcoded "2" this bar once
          // carried over a dead button.
          HopTopBar(
            title: 'My Profile',
            notificationCount: ref.watch(unreadNotificationCountProvider),
            avatarImage: avatarImage,
            onBell: () => context.push(kNotificationCentreRoute),
            onBack: () =>
                context.canPop() ? context.pop() : context.go('/book'),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: hoppin.spacing.gutter,
                vertical: hoppin.spacing.lg,
              ),
              children: [
                // WAVE-0: this rendered a hardcoded `name: 'Clark Kent',
                // location: 'Wolverhampton, Eng'` — EVERY real rider saw Clark
                // Kent, on a screen that was one of the two fidelity-gate
                // reference surfaces. The only identity the app can actually
                // know is the JWT's own metadata (there is no GET /me/profile —
                // gap SL-5), so we show that and nothing more. We do NOT invent
                // a city we cannot know.
                _ProfileIdentity(
                  name: auth.fullName ?? auth.email ?? 'Your account',
                  avatar: avatar,
                  imageHeaders: ref.watch(imageAuthHeadersProvider),
                  onPickAvatar: () => ref
                      .read(avatarUploadControllerProvider.notifier)
                      .pickAndUpload(),
                ),
                SizedBox(height: hoppin.spacing.lg),
                _ProfileRowCard(rows: rows),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Centred identity block: circular avatar over the name (Poppins SemiBold
/// navy), optionally over a location caption with a leading pin.
///
/// [location] is nullable and, today, always null: there is no rider-profile
/// read (gap SL-5), so the app does not know the rider's city. The caption row
/// is omitted rather than filled with an invented value. When
/// `GET /me/profile` ships, pass the real city and the row returns — no other
/// change.
class _ProfileIdentity extends StatelessWidget {
  // The analyzer is right that nothing passes `location` — and that IS the
  // point: it is the SL-5 body-swap seat, kept deliberately so the caller can
  // pass the real city the day `GET /me/profile` ships, with no view change.
  // Deleting it would trade a truthful "we do not know your city" for a
  // re-derivation later. The suppression is narrow and reasoned, not a mute.
  const _ProfileIdentity({
    required this.name,
    // ignore: unused_element_parameter
    this.location,
    this.avatar,
    this.imageHeaders,
    this.onPickAvatar,
  });

  final String name;
  final String? location;

  /// Current avatar upload state. Null leaves the block non-interactive (the
  /// initials-only rendering the screen had before uploads existed).
  final AvatarUploadState? avatar;

  /// Bearer headers for the photo — `/images/*` is authenticated.
  final Map<String, String>? imageHeaders;

  /// Opens the photo picker.
  final VoidCallback? onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final location = this.location;
    return Column(
      children: [
        // The avatar is now a REAL control: `POST /me/avatar/upload` exists and
        // serves riders as well as drivers, so a picker here no longer sends a
        // photo nowhere. Falls back to the previous static treatment when the
        // screen is built without an upload state (e.g. widget tests).
        HopAvatarEditor(
          name: name,
          imageUrl: switch (avatar) {
            AvatarIdle(:final url) => url,
            AvatarUploaded(:final url) => url,
            _ => null,
          },
          headers: imageHeaders,
          busy: avatar is AvatarUploading,
          error: switch (avatar) {
            AvatarUploadFailed(:final message) => message,
            _ => null,
          },
          onTap: onPickAvatar,
        ),
        SizedBox(height: hoppin.spacing.md),
        Text(name, style: hoppin.type.section.copyWith(color: colors.textHi)),
        if (location != null) ...[
          SizedBox(height: hoppin.spacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: colors.textMid),
              SizedBox(width: hoppin.spacing.xs),
              Text(
                location,
                style: hoppin.type.meta.copyWith(color: colors.textMid),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The white hub card holding the [HopListRow]s with hairline dividers
/// between them (divider suppressed on the last row).
class _ProfileRowCard extends StatelessWidget {
  const _ProfileRowCard({required this.rows});

  final List<_ProfileRow> rows;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final radius = BorderRadius.circular(hoppin.radii.card);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: radius,
        boxShadow: HoppinShadows.card,
        // This card is hand-rolled rather than a HopCard (it clips its own
        // dividers), so it has to honour the `cardBorder` contract itself —
        // and it was not. In dark that shadow is 8% black over a #0F1220
        // canvas, i.e. nothing, and a #191D2E card on that canvas is a 6%
        // luminance step: the entire hub list had NO edge against the page.
        // `cardBorder` is transparent in light, so this is a dark-only repair.
        border: Border.all(color: colors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            HopListRow(
              icon: rows[i].icon,
              label: rows[i].label,
              divider: i < rows.length - 1,
              // No `?? () {}` fallback. Every row goes somewhere real now, and
              // an empty closure behind a tap ripple is a lie the type system
              // can prevent — so it does.
              onTap: rows[i].onTap,
            ),
        ],
      ),
    );
  }
}
