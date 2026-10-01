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
  test('every admin tap action opens a real rider screen', () {
    expect(adActionRoute('promotions'), AppRoutes.promotional);
    expect(adActionRoute('trips'), AppRoutes.rideHistory);
    expect(adActionRoute('payments'), AppRoutes.paymentMethods);
    expect(adActionRoute('support'), AppRoutes.helpSupport);
    expect(adActionRoute('notifications'), AppRoutes.notifications);
    expect(adActionRoute(''), isNull);
    expect(adActionRoute('earnings'), isNull, reason: 'a driver-only action is not tappable here');
  });

  testWidgets('ad banner', (tester) async {
    tester.view.physicalSize = const Size(430, 260);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activeAdsProvider.overrideWith((ref) async => const [
              Ad(id: 'a1', title: 'Flash Weekend Sale', body: '30% off every ride this weekend with FLASH30.', imageUrl: '', action: 'promotions'),
              Ad(id: 'a2', title: 'New Rider Welcome', body: 'Your first ride is on us.', imageUrl: '', action: ''),
            ]),
        adsRepositoryProvider.overrideWithValue(_NoopAds()),
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

class _NoopAds implements AdsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}
