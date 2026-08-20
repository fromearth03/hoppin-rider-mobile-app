import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import 'cancel_flow.dart';
import 'map/map_builder.dart';
import 'map/map_state.dart';
import 'map/map_view.dart';
import 'rating_sheet.dart';
import 'share_trip_sheet.dart';
import 'trip_builder.dart';
import 'trip_handoff.dart';
import 'trip_router.dart';
import 'trip_state.dart';
import 'widgets/matched_driver_card.dart';
import 'widgets/seam_unavailable_states.dart';

/// The trip riblet's view (riblet anatomy, DOCS/05): Flighty-style smart
/// states — the screen RECOMPOSES per phase instead of relabelling one
/// layout. Dumb by contract: renders [TripState], forwards user intents to
/// the interactor, owns zero timers, never navigates (TripNavigationHost
/// does) and never talks to the data layer.
///
/// The entry widget keeps its name, path and constructor so the app
/// router's GoRoute line is untouched (04-04 owns lib/router.dart).
class TripScreen extends ConsumerWidget {
  const TripScreen({required this.rideId, super.key});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // MAP-03's degradation ladder picks the shell: the hidden rung (both
    // geo seams null — live mode today, gaps #17/#41 unshipped) renders
    // EXACTLY the Phase 4/5 map-less layout; any other rung mounts the live
    // map canvas under the draggable trip card.
    final mapPhase = ref.watch(
      mapInteractorProvider(rideId).select((s) => s.phase),
    );

    // ACTIVE-TRIP LOCK (Uber-style captive trip): while a ride is LIVE, the
    // trip screen is captive — the router redirect guard bounces any escape
    // back here, so a visible "minimise" affordance is dead UX that only
    // implies "leave and abandon." During the active phases the rider gets
    // NO back/minimise chrome at all; the only exits are trip completion or
    // the explicit two-stage Cancel further down the card. The affordance
    // survives only for the non-captive phases where returning home is
    // legitimate (and where the body already carries explicit buttons).
    final locked = _isActivePhase(
      ref.watch(tripInteractorProvider(rideId).select((s) => s.phase)),
    );

    if (mapPhase == MapPhase.hidden) {
      return PopScope(
        canPop: false,
        // When locked the back-gesture is inert (canPop:false already blocks
        // it; the callback stays a no-op so nothing implies an abandon-exit).
        // Off the lock — the terminal / pre-match phases — it returns the
        // rider home, the same legitimate exit the explicit buttons below use.
        onPopInvokedWithResult: locked
            ? (_, _) {}
            : (_, _) => ref
                  .read(tripInteractorProvider(rideId).notifier)
                  .requestHome(),
        child: Scaffold(
          body: TripNavigationHost(
            rideId: rideId,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The top bar keeps its title in every phase, but the back
                  // affordance appears ONLY off the active-trip lock: during a
                  // live ride there is no escape hatch, so a back arrow would
                  // be a button that leaves and abandons. Terminal/pre-match
                  // phases (completed, cancelled, loading, finding, error) can
                  // return home legitimately and also carry explicit buttons
                  // below.
                  HopTopBar(
                    title: 'Your trip',
                    onBack: locked
                        ? null
                        : () => ref
                              .read(tripInteractorProvider(rideId).notifier)
                              .requestHome(),
                  ),
                  Expanded(child: TripFlowContent(rideId: rideId)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // The classic ride-hail layout (MAP-01/02): the interactive map fills
    // the screen as spatial truth; the SAME Flighty trip content — never
    // forked — rides the draggable bottom card.
    //
    // This rung deliberately carries NO top bar: a header would cage the
    // full-bleed canvas that is the entire point of the layout. Off the lock
    // the exit is [_MapExitChip], floating over the map — a return-home
    // affordance for the terminal / pre-match phases. Under the lock the chip
    // is GONE entirely: no floating affordance may imply "leave and abandon"
    // during a live trip.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: locked
          ? (_, _) {}
          : (_, _) =>
                ref.read(tripInteractorProvider(rideId).notifier).requestHome(),
      child: Scaffold(
        body: TripNavigationHost(
          rideId: rideId,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RiderTripMap(rideId: rideId),
              if (!locked) _MapExitChip(rideId: rideId),
              _TripSheet(rideId: rideId),
            ],
          ),
        ),
      ),
    );
  }

  /// The captive phases of the active-trip lock: a driver is committed to the
  /// rider and the trip is live, so the screen offers no escape hatch. The
  /// non-active phases (loading, finding, completed, cancelled, error) are
  /// either pre-match or terminal, where returning home is a legitimate exit.
  static bool _isActivePhase(TripPhase phase) {
    switch (phase) {
      case TripPhase.driverEnRoute:
      case TripPhase.arrivingNow:
      case TripPhase.driverArrived:
      case TripPhase.onRoad:
        return true;
      case TripPhase.loading:
      case TripPhase.finding:
      case TripPhase.completed:
      case TripPhase.cancelled:
      case TripPhase.error:
        return false;
    }
  }
}

/// The floating return-home affordance over the full-bleed map.
///
/// It is mounted ONLY off the active-trip lock — the terminal (completed,
/// cancelled) and pre-match (loading, finding, error) map-mode phases — where
/// returning home is a legitimate exit. During the live active phases the
/// screen is captive and this chip is not rendered at all: the router redirect
/// guard would bounce any escape straight back, so an affordance here would be
/// dead UX that only implies "leave and abandon." It never cancels the trip.
class _MapExitChip extends ConsumerWidget {
  const _MapExitChip({required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(hoppin.spacing.md),
        child: Align(
          alignment: Alignment.topLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.card,
              border: Border.all(color: colors.hairline),
              boxShadow: [
                BoxShadow(
                  color: colors.scrim.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              tooltip: 'Home',
              icon: Icon(Icons.home_outlined, color: colors.textHi),
              onPressed: () => ref
                  .read(tripInteractorProvider(rideId).notifier)
                  .requestHome(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The draggable bottom card: HopSheet's surface language (rounded top,
/// hairline edge, drag handle, one drawn ambient shadow) around the SAME
/// TripFlowContent the map-less layout renders — remounted, never forked.
/// The sheet's scroll controller is handed INTO the flow content so drag
/// and scroll compose the standard ride-hail way.
class _TripSheet extends StatelessWidget {
  const _TripSheet({required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = Radius.circular(hoppin.radii.sheet);
    return DraggableScrollableSheet(
      initialChildSize: kTripSheetMinExtent,
      minChildSize: kTripSheetMinExtent,
      maxChildSize: kTripSheetMaxExtent,
      snap: true,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: dark ? colors.raised : colors.card,
            borderRadius: BorderRadius.vertical(top: radius),
            border: Border.all(color: colors.hairline),
            boxShadow: [
              BoxShadow(
                color: colors.scrim.withValues(alpha: dark ? 0.45 : 0.18),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: radius),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: hoppin.spacing.sm),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.hairline,
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: TripFlowContent(
                      rideId: rideId,
                      controller: scrollController,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The composable trip content — a scrollable column, content-in/events-out.
///
/// Deliberately NOT fused to the Scaffold above: the Phase 6 live-map pass
/// mounts this same widget inside a draggable bottom card OVER the map
/// pane, so it never paints its own canvas background and never assumes it
/// owns the full screen. All smart-state logic lives in the interactor;
/// this is pure composition.
class TripFlowContent extends ConsumerWidget {
  const TripFlowContent({required this.rideId, this.controller, super.key});

  final String rideId;

  /// The draggable bottom card hands its sheet scroll controller in so drag
  /// and content scroll compose; null (the map-less layout) scrolls
  /// standalone exactly as before.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The rating prompt (RIDER-05): the interactor owns the post-bloom
    // delay and the one-shot flags; the view only presents the sheet, once,
    // when the beat comes due. Dismissal never re-prompts.
    ref.listen(tripInteractorProvider(rideId), (previous, next) {
      if (next.ratingPromptDue && !next.ratingPromptShown) {
        ref
            .read(tripInteractorProvider(rideId).notifier)
            .markRatingPromptShown();
        final driver = next.driver;
        unawaited(
          showRatingSheet(
            context,
            rideId: rideId,
            driverFirstName: driver == null
                ? null
                : _firstNameOf(driver.fullName),
            driverInitials: driver?.initials,
          ),
        );
      }
    });

    final state = ref.watch(tripInteractorProvider(rideId));
    final hoppin = context.hoppin;
    final showsStrip =
        state.phase == TripPhase.onRoad || state.phase == TripPhase.completed;

    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.all(hoppin.spacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhaseSwitcher(
            child: KeyedSubtree(
              key: ValueKey('trip-header-${state.phase}'),
              child: _Header(rideId: rideId, state: state),
            ),
          ),
          SizedBox(height: hoppin.spacing.lg),
          // Persistent strip slot: the SAME RouteStrip element survives the
          // onRoad→completed flip (it sits outside the phase switchers), so
          // the destination bloom fires exactly once on the live completion
          // event — while a ride mounted already-complete renders the strip
          // statically with no bloom replay (04-02 contract).
          if (showsStrip)
            Padding(
              padding: EdgeInsets.only(bottom: hoppin.spacing.lg),
              child: RouteStrip(
                originLabel: state.driver?.originLabel ?? 'Pickup',
                destinationLabel:
                    state.driver?.destinationLabel ?? 'Destination',
                progress: state.stripProgress,
                activeWaypoint: state.phase == TripPhase.onRoad
                    ? state.activeWaypoint
                    : null,
                complete: state.phase == TripPhase.completed,
                showCarMarker: state.phase != TripPhase.completed,
              ),
            )
          else
            const SizedBox.shrink(),
          _PhaseSwitcher(
            child: KeyedSubtree(
              key: ValueKey('trip-body-${state.phase}'),
              child: _Body(rideId: rideId, state: state),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phase transitions on the motion tokens: quick fade with a slight rise —
/// states recompose, they do not blink.
class _PhaseSwitcher extends StatelessWidget {
  const _PhaseSwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.hoppin.motion;
    return AnimatedSwitcher(
      duration: motion.quick,
      switchInCurve: motion.easeOut,
      switchOutCurve: motion.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The per-phase hero block: the one place the trip speaks in display type.
class _Header extends StatelessWidget {
  const _Header({required this.rideId, required this.state});

  final String rideId;
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final driver = state.driver;
    final first = driver == null ? null : _firstNameOf(driver.fullName);

    switch (state.phase) {
      case TripPhase.loading:
        return _quietNote(context, 'Getting your trip…');

      case TripPhase.finding:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirming your driver…',
              style: type.title.copyWith(color: colors.textHi),
            ),
            SizedBox(height: hoppin.spacing.xs),
            Text(
              'This only takes a moment.',
              style: type.bodySmall.copyWith(color: colors.textMid),
            ),
          ],
        );

      case TripPhase.driverEnRoute:
        final remaining = state.etaSecondsRemaining;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (remaining != null) ...[
              // The ticking hero: huge tabular GeistMono, wall-clock fed.
              Text(
                _mmss(remaining),
                style: type.moneyHero.copyWith(color: colors.textHi),
              ),
              SizedBox(height: hoppin.spacing.xs),
            ],
            Text(
              first != null
                  ? '$first is on the way'
                  : 'Your driver is on the way',
              style: type.title.copyWith(color: colors.textHi),
            ),
            if (remaining != null) ...[
              SizedBox(height: hoppin.spacing.xs),
              Text(
                'Arriving ${formatTime(clock.now().add(Duration(seconds: remaining)))}',
                style: type.bodySmall.copyWith(color: colors.textMid),
              ),
            ],
          ],
        );

      case TripPhase.arrivingNow:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Arriving now',
              style: type.display.copyWith(color: colors.textHi),
            ),
            SizedBox(height: hoppin.spacing.xs),
            Text(
              'Meet ${first ?? 'your driver'} at '
              '${driver?.originLabel ?? 'the pickup point'}',
              style: type.body.copyWith(color: colors.textMid),
            ),
          ],
        );

      case TripPhase.driverArrived:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first != null ? '$first is here' : 'Your driver is here',
              style: type.display.copyWith(color: colors.textHi),
            ),
            SizedBox(height: hoppin.spacing.xs),
            Text(
              'Look for the plate below at '
              '${driver?.originLabel ?? 'your pickup point'}.',
              style: type.body.copyWith(color: colors.textMid),
            ),
          ],
        );

      case TripPhase.onRoad:
        return Text(
          'On your way to ${driver?.destinationLabel ?? 'your destination'}',
          style: type.headline.copyWith(color: colors.textHi),
        );

      case TripPhase.completed:
        final receipt = state.receipt;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You've arrived at "
              '${driver?.destinationLabel ?? 'your destination'}',
              style: type.headline.copyWith(color: colors.textHi),
            ),
            if (receipt != null) ...[
              SizedBox(height: hoppin.spacing.sm),
              // Money reassurance first (Careem/Grab pattern): paid, done.
              Text(
                '${formatPence(receipt.totalPence)} · paid',
                style: type.numeral.copyWith(color: colors.success),
              ),
            ],
          ],
        );

      case TripPhase.cancelled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trip cancelled',
              style: type.headline.copyWith(color: colors.textHi),
            ),
            SizedBox(height: hoppin.spacing.xs),
            Text(
              "You can book another ride whenever you're ready.",
              style: type.body.copyWith(color: colors.textMid),
            ),
          ],
        );

      case TripPhase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Something went wrong',
              style: type.title.copyWith(color: colors.textHi),
            ),
            SizedBox(height: hoppin.spacing.xs),
            Text(
              state.error ?? 'We could not load this trip.',
              style: type.body.copyWith(color: colors.textMid),
            ),
          ],
        );
    }
  }

  Widget _quietNote(BuildContext context, String message) {
    final hoppin = context.hoppin;
    return Text(
      message,
      style: hoppin.type.title.copyWith(color: hoppin.colors.textMid),
    );
  }
}

/// The per-phase working area: cards, money row, promo, affordances.
class _Body extends ConsumerWidget {
  const _Body({required this.rideId, required this.state});

  final String rideId;
  final TripState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final interactor = ref.read(tripInteractorProvider(rideId).notifier);

    switch (state.phase) {
      case TripPhase.loading:
      case TripPhase.finding:
      case TripPhase.error:
        if (state.phase == TripPhase.error) {
          return TextButton(
            onPressed: interactor.requestHome,
            child: const Text('Back to home'),
          );
        }
        return const SizedBox.shrink();

      case TripPhase.driverEnRoute:
      case TripPhase.arrivingNow:
      case TripPhase.driverArrived:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Exceptions slot: delay / driver-change StatusPill chips stack
            // here (never silent ETA mutation) once exception telemetry
            // exists — the space above the card is reserved by design.
            //
            // The #5 seam: driverInfo answers null live. Rather than leave a
            // silent gap (or fabricate a driver), the card slot degrades to a
            // designed, honest DriverUnavailableCard until the endpoint ships.
            if (state.driver != null)
              MatchedDriverCard(
                info: state.driver!,
                // Chat is BOUND, but only inside the server's active-trip
                // window. `chatOpen` is the client mirror (the 409 stays the
                // authority) — a null callback disables the row rather than
                // leading the rider into a channel that will reject them.
                onContact: state.chatOpen ? interactor.requestChat : null,
                // A FOURTH, distinct affordance on the disclosed #45 voice
                // seam — never the same button as Message (the Wave-0 lie).
                onCall: interactor.requestCall,
                onShare: () => showShareTripSheet(context, rideId: rideId),
                onSafety: interactor.requestSafety,
                imageHeaders: ref.watch(imageAuthHeadersProvider),
              )
            else
              const DriverUnavailableCard(),
            SizedBox(height: hoppin.spacing.lg),
            _PromoSection(rideId: rideId),
            SizedBox(height: hoppin.spacing.lg),
            // Quiet destructive entry to the two-stage intercept — only in
            // the pre-trip phases (matches the cancellable status set).
            TextButton(
              onPressed: () => showCancelIntercept(context, rideId: rideId),
              style: TextButton.styleFrom(
                foregroundColor: hoppin.colors.error,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Cancel trip'),
            ),
          ],
        );

      case TripPhase.onRoad:
        final handoff = ref.watch(tripHandoffProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Same #5 degrade: honest rung when driverInfo is null on-road.
            if (state.driver != null)
              MatchedDriverCard(
                info: state.driver!,
                compact: true,
                imageHeaders: ref.watch(imageAuthHeadersProvider),
              )
            else
              const DriverUnavailableCard(),
            SizedBox(height: hoppin.spacing.md),
            Row(
              children: [
                if (handoff != null)
                  StatusPill(
                    label: '${formatPounds(handoff.fareTotalPounds)} fixed',
                    tone: PillTone.accent,
                    numeric: true,
                  ),
                const Spacer(),
                // WAVE-0: a phone icon tooltipped "Contact" that opened CHAT.
                // The affordance now matches what it does — and Phase 11 puts a
                // REAL call entry beside it on the disclosed voice seam (#45).
                // Two distinct icons, two distinct destinations. That
                // distinction is the whole fix.
                IconButton(
                  tooltip: 'Message driver',
                  icon: const Icon(Icons.chat_bubble_outline),
                  color: hoppin.colors.accent,
                  onPressed: state.chatOpen ? interactor.requestChat : null,
                ),
                IconButton(
                  tooltip: 'Call driver',
                  icon: const Icon(Icons.phone_outlined),
                  color: hoppin.colors.accent,
                  onPressed: interactor.requestCall,
                ),
                IconButton(
                  tooltip: 'Share trip',
                  icon: const Icon(Icons.ios_share_outlined),
                  color: hoppin.colors.accent,
                  onPressed: () => showShareTripSheet(context, rideId: rideId),
                ),
                IconButton(
                  tooltip: 'Safety',
                  icon: const Icon(Icons.shield_outlined),
                  color: hoppin.colors.accent,
                  onPressed: interactor.requestSafety,
                ),
              ],
            ),
            SizedBox(height: hoppin.spacing.md),
            _PromoSection(rideId: rideId),
            SizedBox(height: hoppin.spacing.sm),
            TextButton(
              onPressed: () => showCancelIntercept(context, rideId: rideId),
              style: TextButton.styleFrom(
                foregroundColor: hoppin.colors.error,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Cancel trip'),
            ),
          ],
        );

      case TripPhase.completed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              onPressed: interactor.requestReceipt,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('View receipt'),
            ),
            SizedBox(height: hoppin.spacing.sm),
            TextButton(
              onPressed: interactor.requestHome,
              child: const Text('Back to home'),
            ),
          ],
        );

      case TripPhase.cancelled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: interactor.requestBook,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Book another ride'),
            ),
            SizedBox(height: hoppin.spacing.sm),
            TextButton(
              onPressed: interactor.requestHome,
              child: const Text('Back to home'),
            ),
          ],
        );
    }
  }
}

/// Promo row (RIDER-07): collapsed by default; expands to an inline entry;
/// success renders the named discount line with the old total struck
/// through and the MoneyTicker animating down to the new one — the money
/// moment must be SEEN, not implied. Failures explain why (the PROMO_*
/// messages are display-ready).
class _PromoSection extends ConsumerStatefulWidget {
  const _PromoSection({required this.rideId});

  final String rideId;

  @override
  ConsumerState<_PromoSection> createState() => _PromoSectionState();
}

class _PromoSectionState extends ConsumerState<_PromoSection> {
  final _codeCtrl = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _apply(String code) {
    unawaited(
      ref.read(tripInteractorProvider(widget.rideId).notifier).applyPromo(code),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripInteractorProvider(widget.rideId));
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final promo = state.appliedPromo;
    // A code staged at booking that failed at the match beat — say it out
    // loud (the booking flow can no longer show it once the trip owns the
    // screen); an in-trip apply success supersedes the note.
    final matchPromoError = ref.watch(tripHandoffProvider)?.promoError;

    if (promo != null) {
      return HopCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _promoLabel(promo),
              style: type.label.copyWith(color: colors.success),
            ),
            SizedBox(height: hoppin.spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatPounds(promo.originalFare),
                  style: type.numeral.copyWith(
                    color: colors.textMid,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                SizedBox(width: hoppin.spacing.sm),
                MoneyTicker(
                  pence: (promo.newFare * 100).round(),
                  fromPence: (promo.originalFare * 100).round(),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matchPromoError != null) ...[
          HopBanner.error(
            message:
                "Your promo code didn't apply — $matchPromoError. "
                'You can add a code below.',
          ),
          SizedBox(height: hoppin.spacing.sm),
        ],
        HopCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_expanded)
                InkWell(
                  onTap: () => setState(() => _expanded = true),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_offer_outlined,
                          size: 18,
                          color: colors.accent,
                        ),
                        SizedBox(width: hoppin.spacing.sm),
                        Text(
                          'Add promo code',
                          style: type.body.copyWith(color: colors.textHi),
                        ),
                        const Spacer(),
                        Icon(Icons.expand_more, color: colors.textMid),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        enabled: !state.promoBusy,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'e.g. HOPPIN20',
                        ),
                        onSubmitted: _apply,
                      ),
                    ),
                    SizedBox(width: hoppin.spacing.sm),
                    FilledButton(
                      onPressed: state.promoBusy
                          ? null
                          : () => _apply(_codeCtrl.text),
                      child: Text(state.promoBusy ? 'Applying…' : 'Apply'),
                    ),
                  ],
                ),
              if (state.promoError != null) ...[
                SizedBox(height: hoppin.spacing.sm),
                Text(
                  state.promoError!,
                  style: type.bodySmall.copyWith(color: colors.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// "HOPPIN20 · 20% off" for percentage promos; a minus-money line for
  /// any other discount shape.
  String _promoLabel(PromoResult promo) {
    if (promo.discountType == 'percentage' && promo.originalFare > 0) {
      final pct = ((promo.discountAmount / promo.originalFare) * 100).round();
      return '${promo.promoCode} · $pct% off';
    }
    return '${promo.promoCode} · −${formatPounds(promo.discountAmount)}';
  }
}

String _mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _firstNameOf(String fullName) {
  final parts = fullName.trim().split(' ');
  return parts.isEmpty ? fullName : parts.first;
}
