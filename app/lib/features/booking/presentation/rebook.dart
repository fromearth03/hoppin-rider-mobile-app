import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/geo.dart';
import '../../../shared/nav/app_router.dart';
import 'route_entry_screen.dart' show ChosenRoute, RoutePoint;

/// Start booking a journey the rider has already taken.
///
/// Into the route picker with both ends filled, NOT straight to the fare
/// screen. A rebook is not a repeat: the rider may be starting from somewhere
/// else today, or going to the same place at a different time. One tap gets
/// them to a screen where everything is already correct and anything can still
/// be changed — and where the fare is quoted fresh, since last month's price is
/// not this month's.
void rebookJourney(
  BuildContext context, {
  required String pickupLabel,
  required LatLng pickup,
  required String dropoffLabel,
  required LatLng dropoff,
}) {
  context.push(
    AppRoutes.route,
    extra: ChosenRoute(
      pickup: RoutePoint(pickupLabel, pickup),
      dropoff: RoutePoint(dropoffLabel, dropoff),
    ),
  );
}
