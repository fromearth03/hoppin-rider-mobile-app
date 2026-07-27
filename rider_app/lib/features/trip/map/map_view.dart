import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

import '../widgets/seam_unavailable_states.dart';
import 'map_builder.dart';
import 'map_state.dart';

/// The draggable trip card's collapsed extent — map dominant, the ETA hero
/// readable. Shared with the trip screen's DraggableScrollableSheet so the
/// recenter chip clears the card's collapsed rim exactly.
const double kTripSheetMinExtent = 0.35;

/// The draggable trip card's expanded extent.
const double kTripSheetMaxExtent = 0.8;

/// Public embedded entry for the rider map riblet (router-free per DOCS/05):
/// the live interactive map canvas the trip screen mounts full-bleed behind
/// the draggable trip card.
class RiderTripMap extends StatelessWidget {
  const RiderTripMap({required this.rideId, super.key});

  /// Which ride's map riblet instance this canvas hosts.
  final String rideId;

  @override
  Widget build(BuildContext context) => _MapView(rideId: rideId);
}

/// The map riblet's view (riblet anatomy, DOCS/05): dumb by contract — it
/// renders HopMap from select-scoped slices of [MapState] (the bottom card's
/// 1 Hz ETA tick must never rebuild map inputs), owns the ONE piece of
/// presentation state the smoothness contract demands (follow paused by a
/// user gesture + the recenter chip that restores it), calls zero
/// repositories, and never navigates.
class _MapView extends ConsumerStatefulWidget {
  const _MapView({required this.rideId});

  final String rideId;

  @override
  ConsumerState<_MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<_MapView> {
  /// True after a pan/zoom gesture: camera intents are recorded but not
  /// applied (HopMap never fights the user) and the recenter chip shows.
  bool _followPaused = false;

  void _onUserGesture() {
    if (!_followPaused) {
      setState(() => _followPaused = true);
    }
  }

  void _resumeFollow() {
    if (_followPaused) {
      setState(() => _followPaused = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final provider = mapInteractorProvider(widget.rideId);

    // A change in the camera intent's TYPE is a trip beat (FitPoints →
    // FollowPoint at trip start, FollowPoint → SettleOn at completion):
    // major beats always retake the camera, so completion settles on the
    // destination pin even if the rider had panned away.
    ref.listen(provider.select((s) => s.cameraIntent?.runtimeType),
        (previous, next) {
      if (_followPaused && previous != next) {
        setState(() => _followPaused = false);
      }
    });

    // Select-scoped watches: every slice carries value equality (the
    // interactor caches pins/track instances), so only real input changes
    // rebuild HopMap — never sibling churn in the trip riblet.
    final pins = ref.watch(provider.select((s) => s.pins));
    final track = ref.watch(provider.select((s) => s.track));
    final carPosition = ref.watch(provider.select((s) => s.carPosition));
    final carHeading = ref.watch(provider.select((s) => s.carHeading));
    final cameraIntent = ref.watch(provider.select((s) => s.cameraIntent));
    final sampleStale = ref.watch(provider.select((s) => s.sampleStale));
    // The MAP-03 ladder rung. `routeOnly` is the honest degrade: route +
    // pins render, the driver-location seam (#41) / ride-geo (#17) answered
    // nothing, so `carPosition` is null and the marker is dark. That hide was
    // SILENT — the rider saw a map with no car and no reason. The rung now
    // carries its designed disclosure (RouteOnlyMapState).
    final phase = ref.watch(provider.select((s) => s.phase));
    final tileProvider = ref.watch(mapTileProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            HopMap(
              pins: pins,
              track: track,
              carPosition: carPosition,
              carHeading: carHeading,
              // Null only on the hidden rung, where this view is unmounted;
              // an empty fit is HopMap's designed no-op.
              cameraIntent: cameraIntent ?? const FitPoints([]),
              follow: !_followPaused,
              interactive: true,
              onUserGesture: _onUserGesture,
              // The interactor's stale flag means "a poll gap over ~3s just
              // happened" — hand HopMap a gap over its 3x-interval snap
              // threshold so the marker teleports deliberately, once.
              sampleGap:
                  sampleStale ? HoppinMotion.mapSampleInterval * 4 : null,
              // 1 Hz today (demo tick + the interactor's poll). #41 body-swap:
              // when GET /rides/:id/driver-location ships, driverPosition
              // starts answering and this retargets to the doc's real 5–10s
              // cadence — a single value swap here, HopMap's tween is unchanged.
              sampleInterval: HoppinMotion.mapSampleInterval,
              userAgentPackageName: 'com.hoppin.rider',
              tileProvider: tileProvider,
            ),
            // The #41/#17 disclosure — mounted on the REAL routeOnly rung
            // (never on hidden, where this view is unmounted; never when the
            // marker is live). It rides the top band so it clears both the
            // trip card and the recenter chip, and is inset from the left so
            // the exit chip's lane stays free on any width.
            if (phase == MapPhase.routeOnly)
              Positioned(
                top: 0,
                right: 0,
                width: constraints.maxWidth * 0.72,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.all(hoppin.spacing.md),
                    child: const _RouteOnlyNotice(),
                  ),
                ),
              ),
            // The recenter chip floats just above the bottom card's
            // collapsed rim; 100ms fade on the motion token.
            Positioned(
              left: 0,
              right: 0,
              bottom: constraints.maxHeight * kTripSheetMinExtent +
                  hoppin.spacing.md,
              child: Center(
                child: AnimatedSwitcher(
                  duration: hoppin.motion.fade,
                  switchInCurve: hoppin.motion.easeOut,
                  switchOutCurve: hoppin.motion.easeOut,
                  child: _followPaused
                      ? _RecenterChip(onTap: _resumeFollow)
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The routeOnly rung's disclosure surface: the registered
/// [RouteOnlyMapState] on a card pane floating over the canvas.
///
/// A non-intrusive overlay by construction — it does not fill the map, it
/// does not eat gestures (hit-testing passes through to HopMap so panning the
/// map under it still works), and it sits in the top band, clear of both the
/// trip card's collapsed rim and the recenter chip that floats above it.
class _RouteOnlyNotice extends StatelessWidget {
  const _RouteOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(hoppin.radii.card),
          border: Border.all(color: colors.hairline),
          boxShadow: HoppinShadows.card,
        ),
        child: const RouteOnlyMapState(),
      ),
    );
  }
}

/// A designed affordance, not a stock FAB: hairline border, card surface,
/// Geist label, brand accent glyph — flipping follow back on re-applies the
/// latest camera intent inside HopMap.
class _RecenterChip extends StatelessWidget {
  const _RecenterChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hoppin = context.hoppin;
    final colors = hoppin.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // The hit target breathes past the visual pill to clear 44px.
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: hoppin.spacing.xs,
          horizontal: hoppin.spacing.xs,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            border: Border.all(color: colors.hairline),
            // Drawn shadow (the one ambient veil the surface language
            // allows) — never a blur filter.
            boxShadow: [
              BoxShadow(
                color: colors.scrim.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: hoppin.spacing.md,
              vertical: hoppin.spacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location_rounded,
                  size: 16,
                  color: colors.accent,
                ),
                SizedBox(width: hoppin.spacing.xs),
                Text(
                  'Recenter',
                  style: hoppin.type.label.copyWith(color: colors.textHi),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
