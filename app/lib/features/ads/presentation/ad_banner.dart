import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../shared/nav/app_router.dart';
import '../data/ads_repository.dart';

/// Where a tap goes, by the action name the admin panel saved. Unknown names
/// (an action added for a newer build) make the banner non-tappable rather
/// than a dead tap.
String? adActionRoute(String action) => switch (action) {
  'promotions' => AppRoutes.promotional,
  'trips' => AppRoutes.rideHistory,
  'payments' => AppRoutes.paymentMethods,
  'support' => AppRoutes.helpSupport,
  'notifications' => AppRoutes.notifications,
  _ => null,
};

/// Ads seen this app session, so each counts one impression per session no
/// matter how often Home is rebuilt or the carousel loops.
final _seenThisSession = <String>{};

/// The home-screen banner: active ads from the admin panel, one at a time,
/// turning every few seconds when there are several. Shows nothing at all
/// when there are no ads or they could not be loaded.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({super.key});

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  final _page = PageController();
  Timer? _turn;
  int _index = 0;

  @override
  void dispose() {
    _turn?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _seen(Ad ad) {
    if (_seenThisSession.add(ad.id)) {
      unawaited(ref.read(adsRepositoryProvider).impression(ad.id));
    }
  }

  void _startTurning(int count) {
    _turn?.cancel();
    if (count < 2) return;
    _turn = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_page.hasClients) return;
      _page.animateToPage(
        (_index + 1) % count,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _tap(Ad ad) async {
    final route = adActionRoute(ad.action);
    if (route == null) return;
    unawaited(ref.read(adsRepositoryProvider).click(ad.id));
    if (mounted) unawaited(context.push(route));
  }

  @override
  Widget build(BuildContext context) {
    final ads = ref.watch(activeAdsProvider).valueOrNull ?? const <Ad>[];
    if (ads.isEmpty) return const SizedBox.shrink();
    if (_index >= ads.length) _index = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _seen(ads[_index]);
    });
    if (_turn == null) _startTurning(ads.length);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 84,
            child: PageView.builder(
              controller: _page,
              itemCount: ads.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _seen(ads[i]);
              },
              itemBuilder: (context, i) => _AdCard(
                ad: ads[i],
                onTap: adActionRoute(ads[i].action) == null
                    ? null
                    : () => _tap(ads[i]),
              ),
            ),
          ),
          if (ads.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < ads.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 16 : 6,
                      height: 6,
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
    );
  }
}

class _AdCard extends StatelessWidget {
  final Ad ad;
  final VoidCallback? onTap;

  const _AdCard({required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            if (ad.imageUrl.isNotEmpty)
              SizedBox(
                width: 96,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ad.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 14.5,
                        color: AppColors.navy,
                      ),
                    ),
                    if (ad.body.isNotEmpty)
                      Text(
                        ad.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  Icons.chevron_right,
                  color: AppColors.navy.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
