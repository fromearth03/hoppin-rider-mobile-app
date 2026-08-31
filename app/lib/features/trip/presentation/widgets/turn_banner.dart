import 'package:flutter/material.dart';

import '../../data/live_trip_source.dart';

/// The "Take left after 1.5 mi" banner on `Start Ride.png`, driven by
/// `geo.steps`.
///
/// Per docs/SCREEN-DECISIONS.md ("Trip in progress"): `steps` is `null` --
/// never `[]` -- outside the driving states, and also null when OSRM is slow
/// or unavailable. Null means "no instructions available" and hides the
/// banner entirely; an empty list means "no turns remain" and is a different,
/// equally banner-less state. Neither is an error, and the two must never be
/// rendered as if they were the same thing internally, even though both
/// currently render nothing -- keeping them distinct here is what lets a
/// future "no turns remain" treatment diverge from "no data" without
/// touching the caller.
class TurnBanner extends StatelessWidget {
  final List<TripStep>? steps;

  const TurnBanner({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final list = steps;
    if (list == null || list.isEmpty) return const SizedBox.shrink();

    final step = list.first;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(step.maneuver), color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              step.instruction,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String maneuver) {
    if (maneuver.contains('left')) return Icons.turn_left;
    if (maneuver.contains('right')) return Icons.turn_right;
    if (maneuver.contains('roundabout')) return Icons.roundabout_left;
    if (maneuver.contains('arrive')) return Icons.flag;
    return Icons.straight;
  }
}
