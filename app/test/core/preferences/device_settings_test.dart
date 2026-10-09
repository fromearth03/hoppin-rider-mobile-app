import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/preferences/device_settings.dart';
import 'package:hoppin_rider/core/preferences/screen_awake.dart';
import 'package:hoppin_rider/core/preferences/external_navigation.dart';
import 'package:hoppin_rider/core/localization/app_localizations.dart';
import 'package:hoppin_rider/core/localization/catalog.dart';
import 'package:hoppin_rider/core/geo.dart';

class _Store extends DeviceSettingsStore {
  DeviceSettings saved = const DeviceSettings();
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> write(DeviceSettings value) async {
    await gate?.future;
    if (fail) throw StateError('storage failed');
    saved = value;
  }

  @override
  Future<DeviceSettings> read() async => saved;
}

void main() {
  testWidgets('translated templates preserve rider-entered text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ur'),
        supportedLocales: [Locale('en'), Locale('ur'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: AppText('Your note: Meet me at 25 High Street')),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.byType(Text).last).data!;
    expect(text, contains('Meet me at 25 High Street'));
    expect(text, isNot(startsWith('Your note:')));
  });

  test('saved settings restore, invalid values fall back safely', () {
    const s = DeviceSettings(
      keepAwake: true,
      distanceUnit: DistanceUnit.kilometres,
      navigation: NavigationApp.waze,
      language: 'ur',
    );
    final restored = DeviceSettings.fromJson(s.toJson());
    expect(restored.toJson(), s.toJson());
    final invalid = DeviceSettings.fromJson({
      'keepAwake': 'true',
      'language': 'x',
      'distanceUnit': 'x',
      'navigation': 'x',
    });
    expect(invalid.toJson(), const DeviceSettings().toJson());
  });
  test(
    'rapid changes serialize and a failed write preserves the saved choice',
    () async {
      final store = _Store()..gate = Completer<void>();
      final c = ProviderContainer(
        overrides: [deviceSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      final n = c.read(deviceSettingsProvider.notifier);
      final a = n.update((s) => s.copyWith(language: 'ur'));
      final b = n.update(
        (s) => s.copyWith(distanceUnit: DistanceUnit.kilometres),
      );
      store.gate!.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(store.saved.language, 'ur');
      expect(store.saved.distanceUnit, DistanceUnit.kilometres);
      store.fail = true;
      expect(await n.update((s) => s.copyWith(language: 'hi')), isFalse);
      expect(c.read(deviceSettingsProvider).language, 'ur');
      final restarted = ProviderContainer(
        overrides: [
          initialDeviceSettingsProvider.overrideWithValue(await store.read()),
        ],
      );
      addTearDown(restarted.dispose);
      expect(restarted.read(deviceSettingsProvider).language, 'ur');
    },
  );
  test(
    'distance conversion uses the chosen unit without changing source metres',
    () {
      expect(formatDistance(1609.344, DistanceUnit.miles), '1.0 mi');
      expect(formatDistance(1609.344, DistanceUnit.kilometres), '1.6 km');
      expect(formatDistance(0, DistanceUnit.kilometres), '0.0 km');
    },
  );
  testWidgets(
    'wakelock follows preference, foreground, background and disposal',
    (tester) async {
      final calls = <bool>[];
      final c = ProviderContainer(
        overrides: [
          deviceSettingsStoreProvider.overrideWithValue(_Store()),
          screenAwakeDriverProvider.overrideWithValue((v) async {
            calls.add(v);
          }),
        ],
      );
      addTearDown(c.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: ScreenAwake(child: Scaffold())),
        ),
      );
      await tester.pump();
      await c
          .read(deviceSettingsProvider.notifier)
          .update((s) => s.copyWith(keepAwake: true));
      await tester.pump();
      expect(calls.last, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.last, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls.last, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(calls.last, isFalse);
    },
  );
  testWidgets('directions use selected provider and real coordinates', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialDeviceSettingsProvider.overrideWithValue(
            const DeviceSettings(navigation: NavigationApp.waze),
          ),
          directionsLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DirectionsButton(point: LatLng(52.58, -2.13))),
        ),
      ),
    );
    await tester.tap(find.text('Directions'));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'waze.com');
    expect(opened.single.queryParameters['ll'], '52.58,-2.13');
    expect(
      directionsUri(
        NavigationApp.googleMaps,
        const LatLng(52, -2),
        walking: true,
      ).queryParameters['travelmode'],
      'walking',
    );
    expect(
      directionsUri(
        NavigationApp.appleMaps,
        const LatLng(52, -2),
      ).queryParameters['daddr'],
      '52.0,-2.0',
    );
  });
  testWidgets('failed navigation is visible and does not crash', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          directionsLauncherProvider.overrideWithValue((_) async => false),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DirectionsButton(point: LatLng(52, -2))),
        ),
      ),
    );
    await tester.tap(find.text('Directions'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not open your maps app. Choose another app in Settings.',
      ),
      findsOneWidget,
    );
  });
  test('every catalog entry contains both nonempty translations', () {
    expect(translations.length, greaterThan(450));
    for (final entry in translations.entries) {
      expect(entry.value.length, 2, reason: entry.key);
      expect(
        entry.value.every((v) => v.trim().isNotEmpty),
        isTrue,
        reason: entry.key,
      );
    }
  });
  for (final code in ['ur', 'hi']) {
    testWidgets('$code translates copy and uses the correct text direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          supportedLocales: const [Locale('en'), Locale('ur'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(
            body: Column(
              children: [
                AppText('Personal Information'),
                AppText('Save'),
                Text('Ada, 12 Lichfield Street'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(code == 'ur' ? 'ذاتی معلومات' : 'व्यक्तिगत जानकारी'),
        findsOneWidget,
      );
      expect(find.text('Personal Information'), findsNothing);
      expect(find.text('Ada, 12 Lichfield Street'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(Column))),
        code == 'ur' ? TextDirection.rtl : TextDirection.ltr,
      );
    });
  }
}
