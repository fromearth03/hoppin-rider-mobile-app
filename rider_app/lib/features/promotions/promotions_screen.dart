import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'widgets/ad_banner_card.dart';
import 'widgets/promo_codes_unavailable.dart';

/// The in-app route the Profile hub's "Promotions" row targets. Lane F adds the
/// matching `GoRoute` (`router.dart` is contended); this constant is the
/// contract both sides agree on. It is an authenticated surface — it must NOT
/// go on the signed-out redirect allowlist.
const String kPromotionsRoute = '/profile/promotions';

/// The active `GET /ads` feed. BOUND, audience-matched server-side from the JWT
/// role — the app never sends an audience.
///
/// `autoDispose` so leaving the screen drops the feed rather than holding stale
/// campaigns; re-entering re-reads.
final activeAdsProvider = FutureProvider.autoDispose<List<Ad>>((ref) {
  return ref.watch(adsRepositoryProvider).activeAds();
});

/// The public promotion CATALOGUE — `GET /promotions`. BOUND.
///
/// 🔴 This is NOT the rider's wallet. The server filters by campaign window and
/// rider audience, never by who is asking, so these are offers that EXIST and
/// are open — not codes this rider holds. `GET /me/promos` still does not exist
/// and [PromoCodesUnavailable] still says so. The two are different questions
/// and the screen must keep answering them separately.
final promoOffersProvider = FutureProvider.autoDispose<List<PromoOffer>>((ref) {
  return ref.watch(ridesRepositoryProvider).promotions();
});

/// The promotions centre (ACCT-04).
///
/// 🔴 **This screen is HALF-REAL, and the split is STRUCTURAL, not cosmetic.**
///
///   * **Campaigns** — the genuinely BOUND `GET /ads` feed. Real data, real
///     loading, real error, real empty. It had ZERO UI in the app until now.
///   * **Your codes** — gap 72 / SL-13. There is no `GET /me/promos`. The
///     section is a permanent seam and [PromoCodesUnavailable] says so.
///
/// Both halves are true. Neither is disguised as the other, and the empty rung
/// of the first is deliberately NOT reused for the second: "no campaigns right
/// now" is a FACT (the endpoint answered `[]`); the same sentence about codes
/// would be a LIE (we cannot ask at all).
///
/// What this screen deliberately does NOT contain, and why:
///
///   * **No promo-code cards.** The three codes the Figma frame draws are
///     INVENTED — no endpoint could have produced them, and one of them is a
///     REFERRAL code, which is doubly forbidden: referrals are the owner's sole
///     PARKED feature, so drawing it would resurrect a killed scope item. The
///     literal strings are pinned absent by `promotions_screen_test.dart`,
///     which is the only place in the lane they may appear. (⚠️ Naming a rule
///     must not violate it — the phase gate greps `lib/` for those literals and
///     a comment quoting them would trip it permanently. Same trap Wave 0
///     documented for the `SEAM(#` literal.)
///   * **No Copy button, and no copy-to-device write of any kind** (the test
///     drives every control and asserts the platform copy channel stays
///     silent). There is nothing true to copy. A Copy button that copies a code
///     we made up is the Wave-0 share-sheet bug reincarnated — that one copied
///     a sentence containing no link and toasted "Link copied".
///   * **No expiry dates.** The frame's "valid until" lines are invented too;
///     there is no code to have an expiry.
///   * **No "validate this code" input.** `POST /rides/:id/promo` NEEDS A RIDE;
///     no pre-ride validation endpoint exists (seam 46). A validate button here
///     would be a brand-new lie, minted by the phase whose entire purpose is to
///     stop lying.
///
/// ⚠️ The Figma frame for this screen contains NO banners at all. The half it
/// designs (the code list) is the half with no endpoint; the half it omits
/// (campaigns) is the only bound half. The campaigns layout is therefore
/// designed from the token system — explicitly Claude's discretion per
/// CONTEXT.md, because the owner anticipated exactly this gap.
class PromotionsScreen extends ConsumerWidget {
  /// Creates the promotions centre.
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final ads = ref.watch(activeAdsProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HopTopBar(
              title: 'Promotions',
              // NEVER null — a null back intent HIDES the chevron entirely, and
              // this screen is reached from the Profile hub with `context.go`,
              // which REPLACES rather than pushes: there is nothing to pop, so
              // a stock AppBar would draw no arrow either and the rider was
              // stranded here. Fall back to the hub they came from.
              //
              // (The literal spelling of the null-back mistake is deliberately
              // NOT written here: shell_chrome_test greps this source for it,
              // and a comment quoting the bug would trip the guard forever.)
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/profile'),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  hoppin.spacing.gutter,
                  hoppin.spacing.md,
                  hoppin.spacing.gutter,
                  hoppin.spacing.xl,
                ),
                children: [
                  // ── The BOUND half ──────────────────────────────────────
                  const _SectionHeading('Campaigns'),
                  SizedBox(height: hoppin.spacing.sm),
                  ..._campaignsFor(ads),

                  SizedBox(height: hoppin.spacing.lg),

                  // ── The CATALOGUE half — also BOUND ─────────────────────
                  //
                  // `GET /promotions` existed for this screen's whole life and
                  // nothing called it. These offers are REAL server rows, so
                  // their codes and expiry dates are FACTS — which is exactly
                  // what separates them from the Figma frame's invented cards
                  // that `promotions_screen_test` pins absent forever.
                  //
                  // Heading is "Available offers", never "Your codes": these
                  // are open to riders generally, not granted to this one.
                  const _SectionHeading('Available offers'),
                  SizedBox(height: hoppin.spacing.sm),
                  ..._offersFor(ref.watch(promoOffersProvider)),

                ],
              ),
            ),

            // ── The SEAMED half (gap 72) — PINNED, not scrolled ──────────
            //
            // THE gap-72 mount site (Group C reachability).
            //
            // Constructed UNCONDITIONALLY: the seam is not "sometimes null", it
            // is ALWAYS null. There is no `GET /me/promos`, so there is no
            // branch on which codes could appear.
            //
            // 🔴 It sits OUTSIDE the ListView deliberately. As the last child of
            // a scrolling list it was culled the moment the bound sections above
            // it filled the viewport — the disclosure silently disappeared on
            // exactly the busy screens where a rider is most likely to go
            // looking for their codes. A permanent rung must not be able to
            // scroll out of existence, so it is pinned to the bottom of the
            // screen instead of trusting a cache extent to keep it alive.
            Padding(
              padding: EdgeInsets.fromLTRB(
                hoppin.spacing.gutter,
                hoppin.spacing.lg,
                hoppin.spacing.gutter,
                hoppin.spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SectionHeading('Your codes'),
                  SizedBox(height: hoppin.spacing.sm),
                  const PromoCodesUnavailable(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The three honest rungs of the BOUND half: loading, failed, and the data
  /// (which is itself either real campaigns or the truthful empty fact).
  ///
  /// 🔴 **The error check comes FIRST, and deliberately.** Riverpod 3 delivers
  /// a failed `FutureProvider` as `AsyncLoading(error: …)` — `isLoading` is
  /// STILL true while the error rides along, and `AsyncValue.when` therefore
  /// routes that state to its `loading` branch by default. A `when`-based
  /// ladder here spins FOREVER on a dead endpoint: the rider watches a
  /// spinner that will never resolve, and never learns the call failed. So the
  /// ladder is written explicitly and `hasError` is asked first.
  static List<Widget> _campaignsFor(AsyncValue<List<Ad>> ads) {
    if (ads.hasError) return const [_CampaignsError()];
    if (ads.hasValue) {
      final list = ads.requireValue;
      if (list.isEmpty) return const [_CampaignsEmpty()];
      return [
        for (final ad in list) ...[
          AdBannerCard(ad: ad, key: ValueKey(ad.id)),
          const SizedBox(height: HoppinSpacing.md),
        ],
      ];
    }
    return const [_CampaignsLoading()];
  }

  /// The catalogue's rungs. Same ladder shape as [_campaignsFor], and for the
  /// same reason: `hasError` is asked FIRST because a failed Riverpod 3 future
  /// is still `isLoading`, so a `when`-based ladder would spin forever.
  ///
  /// The empty rung here is an honest FACT — the endpoint answered with no
  /// offers, which is different from the "we cannot ask" of [PromoCodesUnavailable]
  /// below it. Two different sentences for two different truths.
  static List<Widget> _offersFor(AsyncValue<List<PromoOffer>> offers) {
    if (offers.hasError) return const [_OffersUnavailable()];
    if (offers.hasValue) {
      final list = offers.requireValue;
      if (list.isEmpty) return const [_OffersEmpty()];
      return [
        for (final offer in list) ...[
          _OfferCard(offer: offer, key: ValueKey(offer.promoCode)),
          const SizedBox(height: HoppinSpacing.md),
        ],
      ];
    }
    return const [_CampaignsLoading()];
  }
}

/// One real offer from the catalogue.
///
/// Shows the code, because it is a REAL code the rider can type at booking.
/// There is deliberately **no Copy button**: the screen-wide rule is that no
/// control writes to the clipboard, and the honest affordance is the sentence
/// telling them where the code goes — `POST /rides/:id/promo` needs a ride, so
/// a code copied here cannot be applied until they book anyway.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, super.key});

  final PromoOffer offer;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    // Only ever rendered from server data — never a fabricated date.
    final expires = offer.expiresAt;

    return HopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.displayTitle,
                  style: hoppin.type.bodyMedium.copyWith(color: colors.textHi),
                ),
              ),
              SizedBox(width: hoppin.spacing.sm),
              // The code, in a chip that reads as something to type.
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: hoppin.spacing.sm,
                  vertical: hoppin.spacing.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.accentSubtle,
                  borderRadius: BorderRadius.circular(hoppin.radii.input),
                ),
                child: Text(
                  offer.promoCode,
                  style: hoppin.type.labelSmall.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (offer.description.isNotEmpty) ...[
            SizedBox(height: hoppin.spacing.xs),
            Text(
              offer.description,
              style: hoppin.type.meta.copyWith(color: colors.textMid),
            ),
          ],
          // Conditions the rider needs BEFORE they count on the offer. Omitted
          // entirely when the server sent none rather than guessed at.
          if (offer.minRideAmount != null ||
              offer.newUsersOnly ||
              expires != null) ...[
            SizedBox(height: hoppin.spacing.xs),
            Text(
              [
                if (offer.newUsersOnly) 'New riders only',
                if (offer.minRideAmount != null)
                  'Trips over £${offer.minRideAmount!.toStringAsFixed(2)}',
                if (expires != null)
                  'Ends ${expires.day}/${expires.month}/${expires.year}',
              ].join(' · '),
              style: hoppin.type.labelSmall.copyWith(color: colors.textMid),
            ),
          ],
          SizedBox(height: hoppin.spacing.sm),
          Text(
            'Enter this code when you book.',
            style: hoppin.type.labelSmall.copyWith(color: colors.textMid),
          ),
        ],
      ),
    );
  }
}

/// The catalogue answered with nothing. A FACT, unlike the codes seam below.
class _OffersEmpty extends StatelessWidget {
  const _OffersEmpty();

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Text(
      'No offers running right now.',
      style: hoppin.type.body.copyWith(color: hoppin.colors.textMid),
    );
  }
}

/// The catalogue read failed. Says so — it does NOT fall through to the empty
/// rung, which would assert "no offers" when the truth is "we could not ask".
class _OffersUnavailable extends StatelessWidget {
  const _OffersUnavailable();

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Text(
      "Couldn't load offers just now.",
      style: hoppin.type.body.copyWith(color: hoppin.colors.textMid),
    );
  }
}

/// One of the two section titles that make the half-real split legible.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Text(
      label,
      style: hoppin.type.section.copyWith(color: hoppin.colors.textHi),
    );
  }
}

/// The BOUND feed is in flight.
class _CampaignsLoading extends StatelessWidget {
  const _CampaignsLoading();

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xl),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// The BOUND feed answered `[]`.
///
/// ⚠️ This rung asserts EMPTINESS — and here that is a FACT, because the
/// endpoint exists, we asked it, and it told us there is nothing. It is exactly
/// the sentence that must NOT be reused for the codes section below, where the
/// same words would be a lie: there we cannot ask at all (gap 72).
class _CampaignsEmpty extends StatelessWidget {
  const _CampaignsEmpty();

  @override
  Widget build(BuildContext context) {
    return const HopCard(
      child: HopEmptyState(
        compact: true,
        headline: 'No campaigns right now',
        supporting: 'When we run an offer, it shows up here.',
      ),
    );
  }
}

/// The BOUND feed threw.
///
/// The rider is told the call FAILED, not that there is nothing — a failure
/// rendered as emptiness is the same lie in a different costume.
class _CampaignsError extends StatelessWidget {
  const _CampaignsError();

  @override
  Widget build(BuildContext context) {
    return const HopCard(
      child: HopEmptyState(
        compact: true,
        headline: "We couldn't load campaigns",
        supporting:
            'Something went wrong on our side. Pull back in a moment and '
            "we'll try again.",
      ),
    );
  }
}
