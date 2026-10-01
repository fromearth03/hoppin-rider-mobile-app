// Renders the home-screen ad banner for visual review, and pins the mapping
// from the admin panel's tap actions to the app's screens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/ads/data/ads_repository.dart';
import 'package:hoppin_rider/features/ads/presentation/ad_banner.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';

void main() {
  // Every rider key in the server's catalog (migration 159, app_tap_actions)
  // must open a real screen here; 'url' opens the browser instead.
  test('every catalog tap action opens a real rider screen', () {
    const catalog = ['book', 'schedule', 'promotions', 'trips', 'payments', 'transactions',
      'saved_places', 'safety', 'support', 'notifications', 'profile', 'settings'];
    for (final key in catalog) {
      expect(adActionRoute(key), isNotNull, reason: '$key has no screen in the rider app');
    }
    expect(adActionRoute('promotions'), AppRoutes.promotional);
    expect(adActionRoute('url'), isNull, reason: 'links open in the browser');
    expect(adActionRoute('earnings'), isNull, reason: 'a driver-only action is not tappable here');
  });

  testWidgets('ad banner', (tester) async {
    tester.view.physicalSize = const Size(430, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAdsProvider.overrideWith((ref) async => const [
              Ad(id: 'a1', title: 'Flash Weekend Sale', body: '30% off every ride this weekend with FLASH30.', imageUrl: '', action: 'promotions'),
              Ad(id: 'a2', title: 'New Rider Welcome', body: 'Your first ride is on us.', imageUrl: '', action: ''),
            ]),
        adsRepositoryProvider.overrideWithValue(_NoopAds()),
        dismissedAdsProvider.overrideWith((ref) => _NoDismissed()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const Scaffold(
          backgroundColor: Color(0xFFF7F7FA),
          body: Padding(padding: EdgeInsets.all(16), child: AdBanner()),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/ad_banner.png'));
    await tester.pumpWidget(const SizedBox());
  });
}

class _NoDismissed extends StateNotifier<Set<String>> implements DismissedAds {
  _NoDismissed() : super(const {});
  @override
  Future<void> dismiss(Iterable<String> ids) async => state = {...state, ...ids};
}

class _NoopAds implements AdsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}
