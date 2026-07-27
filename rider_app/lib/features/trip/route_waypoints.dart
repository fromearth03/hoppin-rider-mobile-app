/// Word waypoints for the map-less RouteStrip — the journey narrated in
/// Wolverhampton-real landmarks instead of a moving dot.
///
/// This is RIDER-APP COPY, not demo code (the picker's presets are app code
/// too): a known origin/destination pair gets its scripted narration; live
/// mode with unknown routes simply shows no waypoint word.
///
/// Geography note: the phase context's illustrative phrase "Passing Chapel
/// Ash" does not fit this route — Chapel Ash is WEST of the city centre,
/// while the scripted trip (Rail Station → New Cross Hospital) runs
/// NORTH-EAST along the A4124 Wednesfield Road. These four are the
/// Wolverhampton-real waypoints for that road.
List<String> waypointsFor(String? originLabel, String? destinationLabel) {
  if (originLabel == 'Wolverhampton Rail Station' &&
      destinationLabel == 'New Cross Hospital') {
    return const [
      'Leaving the city centre',
      'Along Wednesfield Road',
      'Passing Heath Town',
      'Approaching New Cross Hospital',
    ];
  }
  return const [];
}
