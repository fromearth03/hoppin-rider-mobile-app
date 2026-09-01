/// Non-web platforms bind the native Maps SDK at build time; there is no JS
/// runtime to probe, so the probe always reports loaded.
bool googleMapsJsLoaded() => true;
