import 'package:hoppin_rider/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../geo.dart';
import 'device_settings.dart';

Uri directionsUri(NavigationApp app, LatLng point, {bool walking = false}) {
  final coordinate = '${point.lat},${point.lng}';
  return switch (app) {
    NavigationApp.googleMaps => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': coordinate,
      'travelmode': walking ? 'walking' : 'driving',
    }),
    NavigationApp.appleMaps => Uri.https('maps.apple.com', '/', {
      'daddr': coordinate,
      'dirflg': walking ? 'w' : 'd',
    }),
    NavigationApp.waze => Uri.https('waze.com', '/ul', {
      'll': coordinate,
      'navigate': 'yes',
    }),
    NavigationApp.system => Uri.parse('geo:$coordinate?q=$coordinate'),
  };
}

final directionsLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class DirectionsButton extends ConsumerWidget {
  final LatLng point;
  final bool pickup;
  final bool compact;
  const DirectionsButton({
    super.key,
    required this.point,
    this.pickup = false,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = pickup ? 'Directions to pickup' : 'Directions';
    Future<void> openDirections() async {
      final app = ref.read(deviceSettingsProvider).navigation;
      final launch = ref.read(directionsLauncherProvider);
      bool opened = false;
      try {
        opened = await launch(directionsUri(app, point, walking: pickup));
      } catch (_) {}
      if (!opened && app == NavigationApp.system) {
        try {
          opened = await launch(
            directionsUri(NavigationApp.googleMaps, point, walking: pickup),
          );
        } catch (_) {}
      }
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText(
              'Could not open your maps app. Choose another app in Settings.',
            ),
          ),
        );
      }
    }

    if (compact) {
      return IconButton(
        tooltip: tr(context, label),
        icon: const Icon(
          Icons.directions_outlined,
          color: Colors.white,
          size: 20,
        ),
        onPressed: openDirections,
      );
    }
    return TextButton.icon(
      icon: const Icon(Icons.directions_outlined),
      label: AppText(label),
      onPressed: openDirections,
    );
  }
}
