import 'package:hoppin_shared/hoppin_shared.dart';

/// A chosen point on the map — what the booking flow passes around.
///
/// Deliberately tiny: when a map SDK is chosen (open question — Google Maps /
/// Mapbox / OSM), the picker starts returning these from map taps and place
/// search instead of the current list-based picker; nothing downstream changes.
class Place {
  const Place({required this.label, required this.lat, required this.lng});

  final String label;
  final double lat;
  final double lng;
}

extension SavedLocationToPlace on SavedLocation {
  Place toPlace() => Place(label: label, lat: lat, lng: lng);
}

/// Well-known spots in the service area (Wolverhampton — see the compliance
/// document types in docs/04). Used by the picker until real place search /
/// map selection lands.
const wolverhamptonPresets = [
  Place(label: 'City Centre', lat: 52.5870, lng: -2.1288),
  Place(label: 'Wolverhampton Rail Station', lat: 52.5877, lng: -2.1200),
  Place(label: 'University of Wolverhampton', lat: 52.5896, lng: -2.1276),
  Place(label: 'New Cross Hospital', lat: 52.6046, lng: -2.0930),
  Place(label: 'Molineux Stadium', lat: 52.5903, lng: -2.1306),
  Place(label: 'Bentley Bridge Retail Park', lat: 52.6006, lng: -2.0868),
];
