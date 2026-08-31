@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/data/payment_methods_repository.dart';
import 'package:hoppin_rider/features/payments/data/receipts_repository.dart';
import 'package:hoppin_rider/features/payments/presentation/payment_methods_screen.dart';
import 'package:hoppin_rider/features/payments/presentation/ride_complete_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentRepo extends Mock implements PaymentMethodsRepository {}

/// Renders Payment Methods and Ride Complete so they can be put side by side
/// with `docs/figma/extracted/`. See `auth_render_test.dart` for why these
/// are renders, not assertions.
void main() {
  Future<void> shoot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: screen,
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('payment methods light', (t) async {
    final repo = _MockPaymentRepo();
    when(() => repo.list()).thenAnswer((_) async => const Ok([
          SavedCard(
            paymentMethodId: 'pm_1',
            brand: 'visa',
            last4: '4242',
            expMonth: 12,
            expYear: 2030,
            isDefault: true,
          ),
          SavedCard(
            paymentMethodId: 'pm_2',
            brand: 'mastercard',
            last4: '9090',
            expMonth: 6,
            expYear: 2028,
            isDefault: false,
          ),
        ]));

    await shoot(
      t,
      ProviderScope(
        overrides: [paymentMethodsRepositoryProvider.overrideWithValue(repo)],
        child: const PaymentMethodsScreen(),
      ),
      'payment_methods_light',
    );
  });

  testWidgets('ride complete light', (t) async {
    const rideId = 'r1';
    final receipt = Receipt(
      rideId: rideId,
      rideCategory: 'standard',
      farePence: const Pence(1405),
      waitingPence: const Pence(0),
      totalPence: const Pence(500),
      currency: 'GBP',
      status: 'captured',
      distanceMiles: 4.7,
      pickupTime: DateTime.utc(2026, 8, 31, 9, 0),
      dropoffTime: DateTime.utc(2026, 8, 31, 9, 13),
      providerPaymentId: 'pi_123',
    );

    await shoot(
      t,
      ProviderScope(
        overrides: [
          rideReceiptProvider(rideId)
              .overrideWith((ref) => Future.value(receipt)),
        ],
        child: const RideCompleteScreen(rideId: rideId),
      ),
      'ride_complete_light',
    );
  });
}
