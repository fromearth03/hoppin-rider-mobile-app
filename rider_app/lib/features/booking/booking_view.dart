import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../../providers.dart';
import '../auth/otp_verify_screen.dart';
import '../trip/cancellation_reasons.dart';
import '../trip/widgets/seam_unavailable_states.dart';
import 'booking_builder.dart';
import 'booking_state.dart';
import 'location_picker_screen.dart';
import 'widgets/fee_disclosure.dart';
import 'widgets/matching_rung.dart';
import 'widgets/multistop_unavailable_notice.dart';
import 'widgets/payment_method_row.dart';
import 'widgets/promo_row.dart';
import 'widgets/ride_type_selector.dart';
import 'widgets/service_unavailable_screen.dart';

/// The booking riblet's view (riblet anatomy, DOCS/05). Dumb by contract:
/// renders [BookingState], forwards user intents to the interactor, owns
/// zero timers, never navigates (BookingNavigationHost does) and never
/// talks to the data layer.
///
/// Rebuilt to the Figma "Book Ride" frame (#8) from the hoppin_ui component
/// set (08-05): a HopMap band, the Ride Now / Schedule Ride segmented
/// control, a LocationField (From navy / To red), a RideTypeCard grid, the
/// FareEstimateCard with its surge line, the selected payment-method row, the
/// cancellation-policy alert and the primary "Confirm Booking" button — all
/// through `context.hoppin` tokens. The top bar is the shell's HopTopBar; the
/// bottom nav is the shell's HopBottomNav.
///
/// Reskin of the VIEW ONLY — the interactor/state, the fare maths, the
/// promo staging, the matching beat and every phase transition are unchanged.
/// The ride-type + Ride-Now/Schedule selection are presentation-only local
/// state (no interactor field exists for them this milestone).
class BookingView extends ConsumerStatefulWidget {
  const BookingView({super.key});

  @override
  ConsumerState<BookingView> createState() => _BookingViewState();
}

class _BookingViewState extends ConsumerState<BookingView> {
  /// Presentation-only: Ride Now (0) vs Schedule Ride (1). Book is on-demand
  /// here; Schedule routes to the /scheduled surface (10-05).
  int _when = 0;

  Future<void> _pick(BuildContext context, {required bool isPickup}) async {
    final place = await LocationPickerScreen.pick(
      context,
      title: isPickup ? 'Choose pickup' : 'Choose destination',
    );
    if (place == null) return;
    final interactor = ref.read(bookingInteractorProvider.notifier);
    isPickup ? interactor.setPickup(place) : interactor.setDropoff(place);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingInteractorProvider);
    final hoppin = context.hoppin;
    final colors = hoppin.colors;

    // The searching beat takes the whole surface (the RadarPulse moment).
    if (state.phase == BookingPhase.searching) {
      return Material(
        color: colors.canvas,
        child: SafeArea(top: false, child: _MatchingBeat(state: state)),
      );
    }

    // BOOK-08 — dispatch exhausted its first pass; the backend is
    // automatically re-dispatching. The designed "finding another driver"
    // retry rung (Lane B's MatchingRung) LEADS over the old manual "Try again"
    // dead end (decision 5). A manual exit stays reachable.
    if (state.phase == BookingPhase.retrying) {
      return Material(
        color: colors.canvas,
        child: const SafeArea(top: false, child: _RetryingBeat()),
      );
    }

    // Outside-area rung (BOOK-07): the geofence pre-flight (or the server 422)
    // fast-failed the pickup. The designed unavailable screen takes the whole
    // surface; its exit returns to a usable booking surface (decision A —
    // profile/payments stay reachable, this is never a dead end).
    if (state.phase == BookingPhase.outsideArea) {
      return Material(
        color: colors.canvas,
        child: SafeArea(
          child: ServiceUnavailableScreen(
            onExit: () => ref
                .read(bookingInteractorProvider.notifier)
                .dismissBookingBlock(),
          ),
        ),
      );
    }

    // Verify wall (AUTH-02): the server answered 403 ACCOUNT_NOT_ELIGIBLE. The
    // hard block at the booking action mirrors the soft VerifyBanner — the OTP
    // screen takes the surface until the account is verified. Its own
    // navigation (router redirect on the auth event) carries the rider on.
    if (state.phase == BookingPhase.needsVerification) {
      // The OTP wall verifies against the signed-in account; the screen reads
      // the auth service itself for resend/verify, so booking passes only the
      // display contact. Kept out of auth internals to preserve test isolation.
      return const Material(
        child: SafeArea(child: OtpVerifyScreen(phone: 'your account')),
      );
    }

    // ACTIVE-TRIP LOCK (belt-and-suspenders to the router redirect). If the
    // rider already has a live trip, the booking FORM must not be reachable —
    // an Uber-style app never lets you start a second concurrent ride. The
    // router redirect (/book → /trip/:activeId) is the primary guard; this is
    // the in-flow backstop for the race where the form has already painted.
    //
    // Scoped to the form-entry phases only. The interactor's own mid-flight
    // phases (searching / retrying / matched / the two block rungs) have
    // already taken the surface above and must run to completion — gating them
    // here would fight the interactor that is itself creating the live trip.
    if (_isFormPhase(state.phase)) {
      final active = _activeRide(ref);
      if (active != null) {
        return Material(
          color: colors.canvas,
          child: SafeArea(child: _TripInProgressSurface(activeRideId: active.id)),
        );
      }
    }

    // Material ancestor: the shell hosts this under its Scaffold in production,
    // but the riblet is also pumped standalone in tests — so it provides its
    // own so bare InkWells (promo row) always find one.
    return Material(
      color: colors.canvas,
      child: ListView(
        // TOP: zero, deliberately. The first child is the map band, and it is
        // MEANT to run under the floating pill — see _MapBand, which absorbs the
        // chrome's top inset into its own height. Padding the list here instead
        // would push the map down and leave the glass hovering over flat canvas
        // with nothing to blur, which is the whole failure this design exists to
        // avoid.
        //
        // BOTTOM: the full chrome reserve. The last child is the "Book now" CTA
        // and it would otherwise sit beneath the nav — an action the rider can
        // see and cannot press. Everything between the two ends still passes
        // under the glass as it scrolls, which is the point of layering.
        padding: EdgeInsets.only(
          bottom: context.chromeScrollPadding().bottom,
        ),
        children: [
          // ── Map band (rounded inset, route + pins + distance/ETA pill) ──
          _MapBand(state: state),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hoppin.spacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: hoppin.spacing.lg),
                _WhenSegment(
                  index: _when,
                  onChanged: (i) {
                    // "Schedule Ride" (1) routes to the scheduled surface
                    // (BOOK-03) rather than mutating the on-demand Book view;
                    // the segment snaps back to "Ride Now" so returning here
                    // lands on the live booking flow.
                    if (i == 1) {
                      unawaited(context.push('/scheduled'));
                      return;
                    }
                    setState(() => _when = i);
                  },
                ),
                SizedBox(height: hoppin.spacing.lg),
                LocationField(
                  fromLabel: 'From',
                  fromValue: state.pickup?.label ?? 'Choose pickup',
                  toLabel: 'To',
                  toValue: state.dropoff?.label ?? 'Choose destination',
                  onEditFrom: state.isBusy
                      ? null
                      : () => _pick(context, isPickup: true),
                  onEditTo: state.isBusy
                      ? null
                      : () => _pick(context, isPickup: false),
                ),
                // SL-11 / #59 — multi-stop is DEFERRED (the estimate/request
                // contract carries no waypoint fields). This is exactly where
                // a rider reaches for "add stop": immediately under the
                // From/To pair. Mounting the designed notice here discloses
                // the deferral instead of letting the affordance be silently
                // absent — an absence a rider reads as "this app can't do it",
                // never as "not yet".
                SizedBox(height: hoppin.spacing.sm),
                const MultiStopUnavailableNotice(),
                SizedBox(height: hoppin.spacing.lg),
                const _SectionHeading('Ride Type'),
                SizedBox(height: hoppin.spacing.md),
                // Lane-A ride-type selector (SL-1 static disclosed list). The
                // convergence edit swaps the old presentation-only 4-card grid
                // for the real selector and threads the chosen vehicle category
                // into the estimate/request via the interactor.
                RideTypeSelector(
                  selectedCategory: state.selectedCategory,
                  onSelect: (id) => ref
                      .read(bookingInteractorProvider.notifier)
                      .setCategory(id),
                  // The SL-1 body-swap: real classes with real category ids
                  // when GET /vehicle-types answers, the disclosed static list
                  // (XL + Accessibility unbookable) when it does not.
                  options: rideTypeOptionsFrom(
                    switch (ref.watch(vehicleTypesProvider)) {
                      AsyncValue(hasValue: true, :final value?) => value,
                      _ => const <VehicleType>[],
                    },
                  ),
                ),
                SizedBox(height: hoppin.spacing.lg),
                ..._fareSection(context, state),
                SizedBox(height: hoppin.spacing.lg),
                // PAY / money path — the payment-method row reads the REAL
                // `paymentMethodsProvider` (the same read the Wallet uses). It
                // renders the rider's actual default card, or an honest rung
                // when there is none / payments are disabled / we could not
                // read them. It never fabricates a brand or digits: this is the
                // last thing a rider sees before committing money.
                const PaymentMethodRow(),
                SizedBox(height: hoppin.spacing.lg),
                // CANCEL-01 / SL-9 — the pre-booking cancellation-fee disclosure
                // (Lane D). Mounted BEFORE the request button (Scope Lock §4.1:
                // "Penalty rules MUST be clearly displayed to passengers before
                // booking"). Renders the real stub figures, disclosed indicative.
                FeeDisclosure(
                  schedule: ref.watch(cancellationFeeScheduleProvider),
                ),
                SizedBox(height: hoppin.spacing.lg),
                _confirmButton(context, state),
                SizedBox(height: hoppin.spacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The "Fare Estimate" heading + the state-appropriate fare surface: the
  /// FareEstimateCard once estimated, a slim progress line while estimating,
  /// a prompt while a stop is missing, or the designed failure card.
  List<Widget> _fareSection(BuildContext context, BookingState state) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    switch (state.phase) {
      case BookingPhase.idle:
        return [
          const _SectionHeading('Fare Estimate'),
          SizedBox(height: hoppin.spacing.md),
          HopCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: hoppin.spacing.md),
              child: Text(
                'Choose a pickup and destination to see your fare.',
                textAlign: TextAlign.center,
                style: type.body.copyWith(color: colors.textMid),
              ),
            ),
          ),
        ];

      case BookingPhase.estimating:
        return [
          const _SectionHeading('Fare Estimate'),
          SizedBox(height: hoppin.spacing.md),
          HopCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: hoppin.spacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accent,
                    ),
                  ),
                  SizedBox(width: hoppin.spacing.sm),
                  Text(
                    'Getting your fare…',
                    style: type.body.copyWith(color: colors.textMid),
                  ),
                ],
              ),
            ),
          ),
        ];

      case BookingPhase.estimated:
      case BookingPhase.requesting:
        final est = state.estimate;
        if (est == null) return const [SizedBox.shrink()];
        return [
          const _SectionHeading('Fare Estimate'),
          SizedBox(height: hoppin.spacing.md),
          FareEstimateCard(
            lines: _fareLines(est.estimate),
            totalAmount: formatPounds(est.estimate.total),
          ),
          SizedBox(height: hoppin.spacing.md),
          // Promo affordance kept reachable (interactor.setPendingPromo) — the
          // staging behaviour is untouched, only its host surface changed.
          PromoRow(
            pendingPromoCode: state.pendingPromoCode,
            promoError: state.promoError,
            onPromoChanged: (code) => unawaited(ref
                .read(bookingInteractorProvider.notifier)
                .setPendingPromo(code)),
          ),
          // #46 — the pre-ride promo seam answered NULL: the code is staged,
          // NOT validated. The staged chip on its own reads like a tick, so
          // the designed disclosure rides directly under it and says what
          // actually happened ("code saved — checked at the match beat").
          // Real degrade branch: `promoUnvalidated` is raised only where
          // `isPromoValid()` returned null. A definitive `true` (demo) never
          // shows it.
          if (state.promoUnvalidated) const PromoUnavailableState(),
        ];

      case BookingPhase.searching:
      case BookingPhase.retrying:
      case BookingPhase.matched:
      // These take the whole surface earlier in build() — the fare section
      // never renders for them, but the switch must stay exhaustive.
      case BookingPhase.outsideArea:
      case BookingPhase.needsVerification:
        return const [SizedBox.shrink()];

      case BookingPhase.failed:
        return [
          const _SectionHeading('Fare Estimate'),
          SizedBox(height: hoppin.spacing.md),
          HopCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: colors.error),
                SizedBox(height: hoppin.spacing.sm),
                Text(
                  "We couldn't get you moving",
                  style: type.title.copyWith(color: colors.textHi),
                ),
                SizedBox(height: hoppin.spacing.xs),
                Text(
                  state.error ?? 'Something went wrong.',
                  style: type.body.copyWith(color: colors.textMid),
                ),
                SizedBox(height: hoppin.spacing.lg),
                HopButton.secondary(
                  label: 'Try again',
                  onPressed: () => ref
                      .read(bookingInteractorProvider.notifier)
                      .retryEstimate(),
                ),
              ],
            ),
          ),
        ];
    }
  }

  /// The primary CTA — "Confirm Booking" (Figma). Enabled only once an
  /// estimate is in hand; shows the busy spinner while requesting. Drives the
  /// unchanged `requestRide()`.
  Widget _confirmButton(BuildContext context, BookingState state) {
    final canConfirm = state.phase == BookingPhase.estimated &&
        state.estimate != null;
    final requesting = state.phase == BookingPhase.requesting;
    return HopButton.primary(
      label: 'Confirm Booking',
      busy: requesting,
      onPressed: canConfirm
          ? () => unawaited(
                ref.read(bookingInteractorProvider.notifier).requestRide(),
              )
          : null,
    );
  }

  /// Maps the real [Quote] to the Figma fare lines: Base fare, Distance, and
  /// the surge row — which ALWAYS renders (§3.4 / BOOK-06: surge is never
  /// silently absent; at ×1.0 baseline it shows a plain-English "no surge"
  /// label instead of being hidden).
  List<FareLine> _fareLines(Quote q) {
    final surged = q.multiplier > 1.0;
    return [
      FareLine(label: 'Base Fare', amount: formatPounds(q.base)),
      FareLine(label: 'Distance', amount: formatPounds(q.distance)),
      // Compliance display rule: the surge line is permanent. Busy → the red
      // multiplier chip + surge amount; quiet → an honest baseline label.
      if (surged)
        FareLine(
          label: 'Surge',
          amount: formatPounds(q.surge),
          surgeMultiplier: '${q.multiplier.toStringAsFixed(1)}x',
        )
      else
        FareLine(label: 'Surge — none right now', amount: formatPounds(0)),
    ];
  }

  /// The phases where the editable booking form is on screen — the only ones
  /// the active-trip lock guards. The interactor's mid-flight phases
  /// (searching / retrying / matched / outsideArea / needsVerification) take
  /// the surface earlier in build() and must not be pre-empted.
  bool _isFormPhase(BookingPhase phase) {
    switch (phase) {
      case BookingPhase.idle:
      case BookingPhase.estimating:
      case BookingPhase.estimated:
      case BookingPhase.requesting:
      case BookingPhase.failed:
        return true;
      case BookingPhase.searching:
      case BookingPhase.retrying:
      case BookingPhase.matched:
      case BookingPhase.outsideArea:
      case BookingPhase.needsVerification:
        return false;
    }
  }

  /// The rider's live trip, if any — read from [historyProvider] (the same
  /// `GET /rides` read home uses). Returns the first ride whose status is
  /// still active (not completed/cancelled/unknown). Null while loading or in
  /// error, so a transient history hiccup never falsely locks the form.
  Ride? _activeRide(WidgetRef ref) {
    final rides = ref.watch(historyProvider).value ?? const <Ride>[];
    for (final r in rides) {
      if (r.status.isActive) return r;
    }
    return null;
  }
}

/// ACTIVE-TRIP LOCK surface. When the rider already has a live trip, the whole
/// booking form is replaced by this — there is no pickup/dropoff field and no
/// Book button to reach, so a second concurrent ride cannot be started from the
/// booking flow (belt-and-suspenders to the router's /book → /trip redirect).
///
/// On-brand and calm rather than alarming (the rider isn't blocked, they're
/// mid-ride): a live pulse, a clear "trip in progress" statement, and a single
/// premium primary action back to the trip. Modelled on how Uber greets you
/// when you re-open the app mid-ride — one obvious way forward, nothing else.
class _TripInProgressSurface extends StatelessWidget {
  const _TripInProgressSurface({required this.activeRideId});

  final String activeRideId;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(hoppin.spacing.gutter),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: RadarPulse(size: 148)),
              SizedBox(height: hoppin.spacing.xl),
              const Center(
                child: StatusPill(
                  label: 'Trip in progress',
                  tone: PillTone.accent,
                  dot: true,
                ),
              ),
              SizedBox(height: hoppin.spacing.lg),
              Text(
                'You have a trip in progress',
                textAlign: TextAlign.center,
                style: type.title.copyWith(color: colors.textHi),
              ),
              SizedBox(height: hoppin.spacing.sm),
              Text(
                "You're already on your way. Finish or cancel this ride before "
                'booking another.',
                textAlign: TextAlign.center,
                style: type.body.copyWith(color: colors.textMid),
              ),
              SizedBox(height: hoppin.spacing.xl),
              HopButton.primary(
                label: 'Return to your trip',
                icon: Icons.navigation_rounded,
                // Uber-style single exit: back to the live trip. `go` REPLACES
                // the route so the booking form is not left underneath on the
                // stack (mirrors booking_router.dart's matched handover).
                onPressed: () => context.go('/trip/$activeRideId'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Figma section heading (Poppins SemiBold ~20 navy).
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    return Text(
      text,
      style: hoppin.type.section.copyWith(color: hoppin.colors.textHi),
    );
  }
}

/// The rounded map inset (Figma: the route band atop Book Ride). An inert
/// HopMap — pickup/dropoff pins, the route polyline, and a distance/ETA pill
/// overlay. Falls back to a neutral band before both stops are chosen.
class _MapBand extends StatelessWidget {
  const _MapBand({required this.state});

  final BookingState state;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final pickup = state.pickup;
    final dropoff = state.dropoff;
    final est = state.estimate;

    final pins = <HopMapPin>[
      if (pickup != null)
        HopMapPin(HopGeoPoint(pickup.lat, pickup.lng), HopMapPinRole.pickup),
      if (dropoff != null)
        HopMapPin(
          HopGeoPoint(dropoff.lat, dropoff.lng),
          HopMapPinRole.destination,
        ),
    ];
    final track = (pickup != null && dropoff != null)
        ? HopMapTrack([
            HopGeoPoint(pickup.lat, pickup.lng),
            HopGeoPoint(dropoff.lat, dropoff.lng),
          ])
        : null;
    final intent = pins.isEmpty
        ? const FitPoints([HopGeoPoint(52.5870, -2.1288)])
        : FitPoints([for (final p in pins) p.point]);

    // 🔴 THE MAP RUNS UNDER THE PILL. This is the shot the whole design is for:
    // a frosted bar with a real street map alive behind it, and that only
    // happens if the map is actually THERE to be blurred. A map band that
    // politely starts below the chrome leaves the pill floating over flat
    // canvas, which is where "glass" collapses back into "tinted card".
    //
    // So the band grows by exactly the room the chrome is occupying and starts
    // at y=0. The 220pt of map the layout was designed around is still 220pt of
    // CLEAR map below the bar; the extra is the part the bar frosts. Nothing is
    // lost — the pins fit to the clear region via the camera intent, and the
    // distance pill is anchored to the BOTTOM of the band.
    final underChrome = context.chromeScrollPadding().top;

    return SizedBox(
      height: 220 + underChrome,
      child: Stack(
        children: [
          Positioned.fill(
            child: HopMap(
              pins: pins,
              track: track,
              carPosition: null,
              carHeading: null,
              cameraIntent: intent,
              follow: true,
              interactive: false,
              onUserGesture: () {},
            ),
          ),
          if (est != null)
            Positioned(
              left: hoppin.spacing.gutter,
              bottom: hoppin.spacing.md,
              child: _DistancePill(
                distanceMeters: est.distanceMeters,
                durationSeconds: est.durationSeconds,
              ),
            ),
        ],
      ),
    );
  }
}

/// The distance/ETA pill floating over the map ("4.2km • 15 min").
class _DistancePill extends StatelessWidget {
  const _DistancePill({
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final int distanceMeters;
  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    final km = (distanceMeters / 1000).toStringAsFixed(1);
    final mins = (durationSeconds / 60).round();
    return StatusPill(label: '$km km • $mins min', numeric: true);
  }
}

/// Ride Now / Schedule Ride segmented control (Figma): active segment navy
/// fill white label, inactive white fill navy label, inside a rounded card.
class _WhenSegment extends StatelessWidget {
  const _WhenSegment({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _labels = ['Ride Now', 'Schedule Ride'];

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final radius = BorderRadius.circular(hoppin.radii.control);
    return Container(
      padding: EdgeInsets.all(hoppin.spacing.xs),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: radius,
        boxShadow: HoppinShadows.card,
        // Hand-rolled surface, so it owes the `cardBorder` contract the same
        // as HopCard does. Without it this control had no edge in dark — a
        // #191D2E track on a #0F1220 canvas under an 8%-black shadow that does
        // not render there — and the INACTIVE segment is a transparent fill,
        // so the unselected half of the switch had nothing to read as a
        // surface at all.
        border: Border.all(color: colors.cardBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: _Segment(
                label: _labels[i],
                active: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final radius = BorderRadius.circular(hoppin.radii.control);
    return Material(
      color: active ? colors.accent : Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: hoppin.spacing.md),
          child: Center(
            child: Text(
              label,
              style: hoppin.type.bodyMedium.copyWith(
                color: active ? colors.onAccent : colors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The staged matching beat (Domino's return-trip effect: three short waits,
/// not one long one). The copy advances on [BookingState.matchingStage] —
/// wall-clock derived in the interactor, never tick-accumulated — and the
/// small cancel is ALWAYS visible.
class _MatchingBeat extends ConsumerWidget {
  const _MatchingBeat({required this.state});

  final BookingState state;

  static const _stageCopy = [
    'Contacting drivers nearby…',
    'A driver is reviewing your request…',
    'Confirming your driver…',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;
    final stage = state.matchingStage.clamp(0, _stageCopy.length - 1);

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(hoppin.spacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RadarPulse(size: 180),
            SizedBox(height: hoppin.spacing.xl),
            // Fixed-height slot so the radar never shifts as lines swap.
            SizedBox(
              height: 56,
              child: Center(
                child: AnimatedSwitcher(
                  duration: hoppin.motion.fade,
                  switchInCurve: hoppin.motion.easeOut,
                  switchOutCurve: hoppin.motion.easeOut,
                  child: Text(
                    _stageCopy[stage],
                    key: ValueKey(stage),
                    textAlign: TextAlign.center,
                    style: type.title.copyWith(color: colors.textHi),
                  ),
                ),
              ),
            ),
            SizedBox(height: hoppin.spacing.xs),
            Text(
              'Usually under a minute',
              style: type.bodySmall.copyWith(color: colors.textMid),
            ),
            SizedBox(height: hoppin.spacing.xl),
            TextButton(
              onPressed: () {
                // Stop the client-side search first (the interactor bumps
                // its generation), then offer the skippable reason survey.
                ref.read(bookingInteractorProvider.notifier).cancelSearch();
                unawaited(_showCancelSurvey(context));
              },
              style: TextButton.styleFrom(
                foregroundColor: colors.textMid,
                minimumSize: const Size(44, 44),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The BOOK-08 retry rung surface — dispatch exhausted its first pass, the
/// backend is re-dispatching. Wraps Lane B's [MatchingRung] and wires its
/// [MatchingRung.onExit] to the SAME designed exit the first-pass beat uses:
/// stop the client-side search, then offer the skippable reason survey (never
/// a dead end). The rung LEADS; the exit is always reachable.
class _RetryingBeat extends ConsumerWidget {
  const _RetryingBeat();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MatchingRung(
      onExit: () {
        ref.read(bookingInteractorProvider.notifier).cancelSearch();
        unawaited(_showCancelSurvey(context));
      },
    );
  }
}

/// The skippable pre-match cancel survey. Acknowledgment-only: `:8080`
/// has no pre-match cancel endpoint (documented gap, CODE-GRAPH.md §6) —
/// the search stop is client-side and no reason can be recorded yet, so
/// the sheet thanks the rider and moves on. Scroll-controlled so all four
/// reasons AND the Skip stay tappable on short viewports. Shared by the
/// first-pass [_MatchingBeat] cancel and the [_RetryingBeat] exit.
Future<void> _showCancelSurvey(BuildContext context) {
  final colors = context.hoppin.colors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: colors.scrim,
    builder: (_) => const HopSheet(child: _CancelSurveySheet()),
  );
}

/// Four seeded reasons + a first-class Skip; any tap simply closes the
/// sheet — the estimated state (places + fare intact) is already behind it.
class _CancelSurveySheet extends ConsumerWidget {
  const _CancelSurveySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // STOPGAP FIX (unblocks web compile): unwrap the AsyncValue before using
    // it as a list. Mirrors cancel_flow.dart. Must also land in Abdullah's repo.
    final reasonsAsync = ref.watch(cancellationReasonsProvider);
    final reasons = reasonsAsync.hasValue
        ? reasonsAsync.requireValue
        : const <CancellationReason>[];
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    final type = hoppin.type;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Search stopped',
          style: type.title.copyWith(color: colors.textHi),
        ),
        SizedBox(height: hoppin.spacing.xs),
        Text(
          'Mind telling us why? Optional — it helps us improve.',
          style: type.bodySmall.copyWith(color: colors.textMid),
        ),
        SizedBox(height: hoppin.spacing.md),
        for (var i = 0; i < reasons.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: hoppin.spacing.xs),
                  child: Text(
                    reasons[i].label,
                    style: type.body.copyWith(color: colors.textHi),
                  ),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: hoppin.spacing.md),
        HopButton.secondary(
          label: 'Skip',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
