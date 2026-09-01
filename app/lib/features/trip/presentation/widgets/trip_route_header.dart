import 'package:flutter/material.dart';

import '../../data/live_trip_source.dart';
import 'glass_chip.dart';

/// The frame's dark glass route panel over the map: pickup, mid stops and
/// dropoff as white rows on a translucent blurred dark ground.
///
/// Renders nothing without waypoints — an empty glass panel over the map
/// would be furniture with no information in it. Labels come from
/// `GET /rides/:id`'s geo block, reverse-geocoded server-side.
class TripRouteHeader extends StatelessWidget {
  final List<TripWaypoint> waypoints;

  const TripRouteHeader({super.key, required this.waypoints});

  @override
  Widget build(BuildContext context) {
    if (waypoints.length < 2) return const SizedBox.shrink();

    IconData iconFor(int index) {
      if (index == 0) return Icons.location_on_outlined;
      if (index == waypoints.length - 1) return Icons.flag_outlined;
      return Icons.circle_outlined;
    }

    return GlassChip(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < waypoints.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(iconFor(i), size: 15, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      waypoints[i].label.isEmpty
                          ? (i == 0 ? 'Pickup' : 'Destination')
                          : waypoints[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            if (i != waypoints.length - 1)
              Divider(
                  height: 1, color: Colors.white.withValues(alpha: 0.15)),
          ],
        ],
      ),
    );
  }
}
