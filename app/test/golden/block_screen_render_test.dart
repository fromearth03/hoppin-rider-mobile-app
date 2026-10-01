// The block screen: the whole app is replaced as soon as the server says this
// phone is blacklisted or the account is suspended or closed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/account_block.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/app_status.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/shared/widgets/app_gate.dart';

Widget _harness(String code) => ProviderScope(
      overrides: [
        appStatusProvider.overrideWith((ref) => Stream.value(AppStatus.unknown)),
        accountBlockProvider.overrideWith((ref) => ApiException(code, 'blocked', 403)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AppGate(child: Text('the app')),
      ),
    );

void main() {
  testWidgets('a blacklisted phone sees the block screen, not the app', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness('DEVICE_BLACKLISTED'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('the app'), findsNothing);
    expect(find.text('This phone has been blocked'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/block_device.png'));
  });

  testWidgets('a suspended account sees its own wording', (tester) async {
    await tester.pumpWidget(_harness('ACCOUNT_SUSPENDED'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Your account is suspended'), findsOneWidget);
  });
}
