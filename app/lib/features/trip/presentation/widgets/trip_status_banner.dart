import 'package:flutter/material.dart';

import '../../data/live_trip_source.dart';
import 'glass_chip.dart';

/// The dark pill banner at the top of the map on `Driver Arrived.png` and
/// `Start Ride.png` ("Driver is Waiting for You" / "Active Ride - Navigating
/// to Destination").
class TripStatusBanner extends StatelessWidget {
  final LiveTripStatus status;

  const TripStatusBanner({super.key, required this.status});

  // Distinct from DriverInfoCard's "Finding your driver" title below it --
  // the two sit on screen together during matching, and identical copy in
  // two places reads as a glitch rather than one coherent state.
  String get _label => switch (status) {
        LiveTripStatus.matching => 'Finding you a driver nearby',
        LiveTripStatus.accepted => 'Driver is on the way',
        LiveTripStatus.arriving => 'Driver is Waiting for You',
        LiveTripStatus.started => 'Active Ride - Navigating to Destination',
        LiveTripStatus.completed => 'Ride complete',
        LiveTripStatus.cancelled => 'Ride cancelled',
      };

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Text(
        _label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
