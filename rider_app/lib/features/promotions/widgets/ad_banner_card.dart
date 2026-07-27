import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../notifications/push_tap_router.dart' show isAllowlistedPushTarget;

/// One campaign banner from the BOUND `GET /ads` feed (ACCT-04).
///
/// `GET /ads` has existed, worked and been audience-matched server-side since
/// it shipped — with ZERO UI anywhere in the app. This card is the first thing
/// that renders it, and it is the half of the promotions centre that is
/// genuinely real.
///
/// 🔴 SECURITY — every tap is gated on [isAllowlistedPushTarget].
///
/// `Ad.targetUrl` is a **server-controlled, admin-editable field with zero
/// validation anywhere in the app** (gap 36: "a bare model field with zero
/// validation"). Rendering it as a tap target without a check turns an
/// admin-console typo — or an admin-console compromise — into an open redirect
/// or a scheme injection straight into the rider app. The allowlist Phase 11
/// wrote for push targets rejects any scheme, any host, any traversal and
/// anything outside the five known in-app path prefixes; gap 36 records that it
/// "can be reused directly by the ad-render path". This is that reuse.
///
/// A target that fails the allowlist — or is absent entirely — makes the ad
/// **not a link**, so the card is **not a tap target**: `onTap` is `null`.
/// Never a no-op callback (which still ripples, so the rider is told the card
/// is interactive when it is not), never a swallowed navigation, never a toast
/// apologising for a link we chose to render anyway.
///
/// Impression reporting is a **one-shot per ad**, fired from [initState] and
/// never from `build`. A build-time impression would inflate the admin reach
/// metric on every rebuild — a quiet data lie, and that metric feeds real ad
/// billing. Both engagement calls are best-effort in [AdsRepository] (failures
/// are swallowed), which is correct: analytics must never break the UI, and
/// there is deliberately no error surface for them here.
class AdBannerCard extends ConsumerStatefulWidget {
  /// Creates a banner for [ad].
  const AdBannerCard({required this.ad, super.key});

  /// The campaign, exactly as `GET /ads` returned it.
  final Ad ad;

  @override
  ConsumerState<AdBannerCard> createState() => _AdBannerCardState();
}

class _AdBannerCardState extends ConsumerState<AdBannerCard> {
  @override
  void initState() {
    super.initState();
    // One-shot. Not in build(): see the class doc.
    ref.read(adsRepositoryProvider).reportImpression(widget.ad.id);
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final ad = widget.ad;

    final target = ad.targetUrl;
    final canTap = target != null && isAllowlistedPushTarget(target);

    return HopCard(
      padding: EdgeInsets.zero,
      onTap: canTap
          ? () {
              ref.read(adsRepositoryProvider).reportClick(ad.id);
              context.go(target);
            }
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _AdImage(url: ad.imageUrl),
          Padding(
            padding: EdgeInsets.all(hoppin.spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ad.title,
                  style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
                ),
                if (ad.body case final body? when body.isNotEmpty) ...[
                  SizedBox(height: hoppin.spacing.xs),
                  Text(
                    body,
                    style: hoppin.type.meta.copyWith(color: colors.textMid),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The campaign image — and its honest degradations.
///
/// `image_url` is optional on the model and absent in the common case. A
/// missing image renders a token-styled accent band, never a broken-image
/// glyph; a failing load does the same rather than showing Flutter's error
/// box. The card is still a real card carrying a real title.
class _AdImage extends StatelessWidget {
  const _AdImage({required this.url});

  final String? url;

  static const double _height = 120;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    final band = Container(
      height: _height,
      color: colors.accentSubtle,
    );

    final src = url;
    if (src == null || src.isEmpty) return band;

    return SizedBox(
      height: _height,
      width: double.infinity,
      child: Image.network(
        src,
        fit: BoxFit.cover,
        // A campaign image that 404s is not an error state for the rider —
        // the card degrades to the band and keeps its real copy.
        errorBuilder: (_, _, _) => band,
      ),
    );
  }
}
