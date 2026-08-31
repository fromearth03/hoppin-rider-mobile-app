/// A coordinate.
///
/// Lives in `core` because it is shared geometry, not the property of any one
/// feature: place search produces them, the fare estimate and the booking
/// request consume them, and the map renders them.
class LatLng {
  final double lat;
  final double lng;

  const LatLng(this.lat, this.lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLng($lat, $lng)';
}

/// The server caps intermediate stops at five.
///
/// Enforced when quoting as well as when booking. Quoting a six-stop fare and
/// then refusing it at the book button would be a worse experience than
/// refusing the sixth stop as it is added.
const kMaxWaypoints = 5;
