import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../data/ads_repository.dart';
import 'ad_actions.dart';
import 'ad_banner.dart' show recordAdSeen;

/// Every active ad, newest first, with the rider's promo codes one tap away.
/// Ads closed on Home still show here: closing only tidies Home.
class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ads = ref.watch(activeAdsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ads & promotions')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(activeAdsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Material(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(
                  Icons.confirmation_number_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Your promo codes',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Codes you can use at checkout',
                  style: TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white),
                onTap: () => context.push(AppRoutes.promotional),
              ),
            ),
            const SizedBox(height: 18),
            ...switch (ads) {
              AsyncData(:final value) when value.isEmpty => [
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    'No ads right now. Check back soon.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
              AsyncData(:final value) => [
                for (final ad in value) ...[
                  _OfferCard(ad: ad),
                  const SizedBox(height: 12),
                ],
              ],
              _ => [
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            },
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  final Ad ad;
  const _OfferCard({required this.ad});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => recordAdSeen(ref, ad));
    final tappable = adIsTappable(ad);
    return Material(
      color: AppColors.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tappable ? () => openAd(context, ref, ad) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ad.imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Image.network(
                  ad.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: AppColors.fill.withValues(alpha: 0.08)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ad.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                        if (ad.body.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(ad.body, style: theme.textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  if (tappable)
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.ink.withValues(alpha: 0.6),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
