import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../providers.dart';
import '../booking/booking_builder.dart';
import '../booking/place.dart';
import '../history/history_screen.dart' show RideRow;

/// Rider home — the hub: "Where to?" hero pill, saved-place shortcuts,
/// quiet quick links, recent trips. If a trip is live it surfaces at the
/// top so the rider can jump back in.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final auth = ref.watch(authServiceProvider);
    final history = ref.watch(historyProvider);
    final saved = ref.watch(savedLocationsProvider);

    final rides = history.value ?? const <Ride>[];
    Ride? active;
    for (final r in rides) {
      if (r.status.isActive) {
        active = r;
        break;
      }
    }
    final recent = rides.where((r) => r.status.isTerminal).take(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Hoppin',
          style: type.title.copyWith(color: colors.accent),
        ),
        actions: [
          // PUSHED, not `go`-ne to. These three (Saved places, Safety, Emergency
          // contacts) live OUTSIDE the shell: no bottom nav, no shell bar. `go`
          // REPLACES the route, so `canPop()` on the far side is false — their
          // back arrow never renders and the rider is stranded. Pushing keeps
          // the stack, so their back button returns here.
          IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: 'Saved places',
            onPressed: () => context.push('/places'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(historyProvider);
          ref.invalidate(savedLocationsProvider);
        },
        child: ListView(
          padding: EdgeInsets.all(hoppin.spacing.gutter),
          children: [
            // The greeting speaks in display type — hierarchy by type, not
            // by boxes.
            Text(
              _greeting,
              style: type.display.copyWith(
                fontSize: 34,
                color: colors.textHi,
              ),
            ),
            SizedBox(height: hoppin.spacing.lg),
            if (active != null) ...[
              // Live-trip re-entry: a Hop surface with a pulsing-dot pill,
              // never a stock tinted ListTile.
              HopCard(
                onTap: () => context.go('/trip/${active!.id}'),
                padding: EdgeInsets.symmetric(
                  horizontal: hoppin.spacing.lg,
                  vertical: hoppin.spacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip in progress',
                            style: type.titleSmall
                                .copyWith(color: colors.textHi),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to return to your trip',
                            style: type.bodySmall
                                .copyWith(color: colors.textMid),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: hoppin.spacing.md),
                    const StatusPill(
                      label: 'Live',
                      tone: PillTone.accent,
                      dot: true,
                    ),
                    SizedBox(width: hoppin.spacing.sm),
                    Icon(Icons.chevron_right, color: colors.textMid),
                  ],
                ),
              ),
              SizedBox(height: hoppin.spacing.md),
            ],
            // ── The hero: the one question home asks ─────────────────────
            _WhereToPill(onTap: () => context.go('/book')),
            SizedBox(height: hoppin.spacing.gutter),
            // ── Saved shortcuts: tap → dropoff prefilled → booking ───────
            saved.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) {
                if (list.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('Go again'),
                    SizedBox(height: hoppin.spacing.sm),
                    Wrap(
                      spacing: hoppin.spacing.sm,
                      runSpacing: hoppin.spacing.sm,
                      children: [
                        for (final s in list.take(6))
                          ActionChip(
                            avatar: Icon(
                              Icons.star,
                              size: 16,
                              color: colors.accent,
                            ),
                            label: Text(s.label),
                            onPressed: () {
                              ref
                                  .read(bookingInteractorProvider.notifier)
                                  .setDropoff(s.toPlace());
                              context.go('/book');
                            },
                          ),
                      ],
                    ),
                    SizedBox(height: hoppin.spacing.gutter),
                  ],
                );
              },
            ),
            // ── Quick links: quiet ghost actions, no card grid ───────────
            Row(
              children: [
                Expanded(
                  child: _QuickLink(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    // `/wallet` NEVER EXISTED. The wallet lives on the shell's
                    // `/payments` tab (WalletScreen is what that route builds).
                    // This tap fell through to go_router's raw exception page
                    // for the app's entire life — the router has no route table
                    // entry to catch it and, until Phase 12, no errorBuilder to
                    // soften the landing either.
                    onTap: () => context.go('/payments'),
                  ),
                ),
                Expanded(
                  child: _QuickLink(
                    icon: Icons.support_agent,
                    label: 'Support',
                    onTap: () => context.go('/support'),
                  ),
                ),
                Expanded(
                  child: _QuickLink(
                    icon: Icons.sos,
                    label: 'Safety',
                    onTap: () => context.push('/safety'),
                  ),
                ),
                Expanded(
                  child: _QuickLink(
                    icon: Icons.contact_phone_outlined,
                    label: 'Contacts',
                    onTap: () => context.push('/contacts'),
                  ),
                ),
              ],
            ),
            SizedBox(height: hoppin.spacing.gutter),
            // ── Recent trips ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SectionHeader('Recent trips'),
                TextButton(
                  onPressed: () => context.go('/history'),
                  child: const Text('See all'),
                ),
              ],
            ),
            SizedBox(height: hoppin.spacing.xs),
            history.when(
              loading: () => Padding(
                padding: EdgeInsets.all(hoppin.spacing.gutter),
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  HopBanner.error(message: friendlyErrorMessage(e)),
              data: (_) => recent.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: hoppin.spacing.md,
                      ),
                      child: Text(
                        'Your trips will show up here.',
                        style: type.bodySmall.copyWith(color: colors.textMid),
                      ),
                    )
                  : Column(
                      children: [
                        for (final r in recent) RideRow(ride: r),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Where to?" hero pill — the single question home asks. A stadium
/// surface on the hairline system; the search glyph carries the accent.
class _WhereToPill extends StatelessWidget {
  const _WhereToPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final shape = StadiumBorder(side: BorderSide(color: colors.hairline));

    return Semantics(
      button: true,
      child: Material(
        color: colors.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            height: 60,
            child: Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: hoppin.spacing.gutter),
              child: Row(
                children: [
                  Icon(Icons.search, size: 22, color: colors.accent),
                  SizedBox(width: hoppin.spacing.md),
                  Text(
                    'Where to?',
                    style: hoppin.type.title.copyWith(color: colors.textHi),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet micro section header — labels carry the hierarchy, never boxes.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Text(
      text.toUpperCase(),
      style: hoppin.type.labelSmall.copyWith(
        color: hoppin.colors.textMid,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// Ghost quick link: icon + quiet label, borderless — a 48px+ touch target
/// without the stock card-grid look.
class _QuickLink extends StatelessWidget {
  const _QuickLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(hoppin.radii.card),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: hoppin.spacing.md),
        child: Column(
          children: [
            Icon(icon, size: 22, color: colors.accent),
            SizedBox(height: hoppin.spacing.xs),
            Text(
              label,
              style: hoppin.type.label.copyWith(color: colors.textMid),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// RideRow (the shared Activity-hub row) lives in
// features/history/history_screen.dart — single-sourced for Home + History.
