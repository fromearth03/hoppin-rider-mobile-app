import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('google')
external JSObject? get _google;

/// True only when the Google Maps JS SDK actually initialised on the page.
///
/// `web/index.html` requests the script, but a bad key, a billing-blocked
/// account or an offline CDN all leave `google.maps` undefined without any
/// signal Flutter would otherwise see — the map widget would just render a
/// blank grey rectangle. The probe is what lets [RiderMap] fall back to the
/// self-hosted OSM stack instead.
bool googleMapsJsLoaded() {
  final g = _google;
  if (g.isUndefinedOrNull) return false;
  return !g!.getProperty<JSAny?>('maps'.toJS).isUndefinedOrNull;
}
