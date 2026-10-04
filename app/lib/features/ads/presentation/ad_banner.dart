import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../data/ads_repository.dart';
import 'ad_actions.dart';
import '../../../shared/widgets/glass.dart';

export 'ad_actions.dart' show adActionRoute;

/// Ads seen this app session, so each counts one impression per session no
/// matter how often a screen is rebuilt.
final _seenThisSession = <String>{};

void recordAdSeen(WidgetRef ref, Ad ad) {
  if (_seenThisSession.add(ad.id)) {
    unawaited(ref.read(adsRepositoryProvider).impression(ad.id));
  }
}

/// How many of the newest ads Home shows. The rest are on the Ads &
/// promotions screen.
const homeAdLimit = 3;

/// The small ad card floating at the top of Home: the newest few ads the
/// rider has not closed, one at a time, with a close button and a way to see
/// them all. Nothing at all when there are none.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({super.key});

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  final _page = PageController();
  Timer? _turn;
  int _index = 0;
  int _count = 0;

  @override
  void dispose() {
    _turn?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _turnEvery(int count) {
    if (count == _count) return;
    _count = count;
    _turn?.cancel();
    if (count < 2) return;
    _turn = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_page.hasClients) {
        _page.animateToPage(
          (_index + 1) % _count,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(activeAdsProvider).valueOrNull ?? const <Ad>[];
    final dismissed = ref.watch(dismissedAdsProvider);
    final ads = all
        .where((a) => !dismissed.contains(a.id))
        .take(homeAdLimit)
        .toList();
    if (ads.isEmpty) return const SizedBox.shrink();
    if (_index >= ads.length) _index = 0;
    _turnEvery(ads.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _index < ads.length) recordAdSeen(ref, ads[_index]);
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Frosted over the map, like the buttons beside it.
        Glass(
          borderRadius: BorderRadius.circular(14),
          blur: 16,
          opacity: 0.80,
          child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 72,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _page,
                  itemCount: ads.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _AdTile(ad: ads[i]),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    tooltip: 'Hide ads',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(
                      Icons.close,
                      color: AppColors.navy.withValues(alpha: 0.6),
                    ),
                    // Hides these ads until a new one is published.
                    onPressed: () => ref
                        .read(dismissedAdsProvider.notifier)
                        .dismiss(ads.map((a) => a.id)),
                  ),
                ),
                if (ads.length > 1)
                  Positioned(
                    bottom: 6,
                    right: 12,
                    child: Row(
                      children: [
                        for (var i = 0; i < ads.length; i++)
                          Container(
                            margin: const EdgeInsets.only(left: 3),
                            width: i == _index ? 12 : 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: i == _index
                                  ? AppColors.navy
                                  : AppColors.navy.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        )),
        const SizedBox(height: 6),
        Glass(
          borderRadius: BorderRadius.circular(20),
          blur: 14,
          opacity: 0.78,
          child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push(AppRoutes.offers),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_offer_outlined,
                    size: 15,
                    color: AppColors.navy,
                  ),
                  SizedBox(width: 5),
                  Text(
                    'Ads & promotions',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )),
      ],
    );
  }
}

class _AdTile extends ConsumerWidget {
  final Ad ad;
  const _AdTile({required this.ad});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tappable = adIsTappable(ad);
    return InkWell(
      onTap: tappable ? () => openAd(context, ref, ad) : null,
      child: Row(
        children: [
          if (ad.imageUrl.isNotEmpty)
            SizedBox(
              width: 72,
              height: double.infinity,
              child: Image.network(
                ad.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: AppColors.navy.withValues(alpha: 0.08)),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 34, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ad.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      color: AppColors.navy,
                    ),
                  ),
                  if (ad.body.isNotEmpty)
                    Text(
                      ad.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
