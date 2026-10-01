import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/nav/app_router.dart';
import '../data/ads_repository.dart';

/// Where each tap-action key opens in the rider app. The keys come from the
/// server's catalog (app_tap_actions), which the admin panel picks from; this
/// map is the rider app's half of it. A key missing here (added for a newer
/// build) makes the ad non-tappable rather than a dead tap.
const adActionRoutes = <String, String>{
  'book': AppRoutes.route,
  'schedule': AppRoutes.scheduleRide,
  'promotions': AppRoutes.promotional,
  'trips': AppRoutes.rideHistory,
  'payments': AppRoutes.paymentMethods,
  'transactions': AppRoutes.transactions,
  'saved_places': AppRoutes.savedPlaces,
  'safety': AppRoutes.safety,
  'support': AppRoutes.helpSupport,
  'notifications': AppRoutes.notifications,
  'profile': AppRoutes.personalInformation,
  'settings': AppRoutes.settings,
};

/// The screen an action opens, or null (website links and unknown keys).
String? adActionRoute(String action) => adActionRoutes[action];

/// Whether tapping [ad] does anything in this build.
bool adIsTappable(Ad ad) =>
    adActionRoutes.containsKey(ad.action) ||
    (ad.action == 'url' && ad.tapUrl.startsWith('https://'));

/// Records the tap and opens what the ad points at.
Future<void> openAd(BuildContext context, WidgetRef ref, Ad ad) async {
  if (!adIsTappable(ad)) return;
  unawaited(ref.read(adsRepositoryProvider).click(ad.id));
  if (ad.action == 'url') {
    final uri = Uri.tryParse(ad.tapUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  final route = adActionRoute(ad.action);
  if (route != null && context.mounted) unawaited(context.push(route));
}
