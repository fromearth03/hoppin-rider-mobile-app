import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsFlag;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/select_vehicle_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockVehicleRepository extends Mock implements VehicleRepository {}

const _standard = VehicleCategory(
  id: 'a',
  name: 'Standard',
  seats: 4,
  bags: 2,
  priceMultiplier: 1.0,
);
const _estate = VehicleCategory(
  id: 'b',
  name: 'Estate',
  seats: 5,
  bags: 4,
  priceMultiplier: 1.3,
);
const _mpv = VehicleCategory(
  id: 'c',
  name: 'MPV',
  seats: 7,
  bags: 5,
  priceMultiplier: 1.5,
);
const _minibus = VehicleCategory(
  id: 'd',
  name: 'Minibus',
  seats: 8,
  bags: 6,
  priceMultiplier: 2.0,
);
// Neither drawn in the design nor named there — proves the fallback artwork
// (not a hardcoded four-category list) is what actually renders the screen.
const _miniCar = VehicleCategory(
  id: 'e',
  name: 'MiniCar',
  seats: 4,
  bags: 2,
  priceMultiplier: 0.9,
);
const _miniTruck = VehicleCategory(
  id: 'f',
  name: 'MiniTruck',
  seats: 2,
  bags: 6,
  priceMultiplier: 1.1,
);
// A name the app has never heard of. An admin can add this at any time with
// no app release, so it must render with the generic fallback, never blank
// or broken.
const _futureCategory = VehicleCategory(
  id: 'g',
  name: 'HoverPod 3000',
  seats: 3,
  bags: 1,
  priceMultiplier: 1.8,
);

Widget _harness(
  VehicleRepository repo, {
  Brightness brightness = Brightness.light,
  ValueChanged<VehicleCategory>? onSelected,
}) =>
    ProviderScope(
      overrides: [
        vehicleRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: SelectVehicleScreen(onSelected: onSelected),
      ),
    );

void main() {
  late _MockVehicleRepository repo;

  setUp(() {
    repo = _MockVehicleRepository();
  });

  testWidgets('shows a loading indicator while the catalogue loads',
      (tester) async {
    final completer = Completer<Result<List<VehicleCategory>>>();
    when(() => repo.list()).thenAnswer((_) => completer.future);

    await tester.pumpWidget(_harness(repo));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Resolve before the test ends so no timer/future is left pending.
    completer.complete(const Ok([]));
    await tester.pumpAndSettle();
  });

  testWidgets('renders every category the API returns, not a hardcoded four',
      (tester) async {
    // Tall surface so all six cards lay out without needing a scroll -
    // the point under test is which categories render, not scrolling.
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    when(() => repo.list()).thenAnswer((_) async => const Ok([
          _standard,
          _estate,
          _mpv,
          _minibus,
          _miniCar,
          _miniTruck,
        ]));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    for (final v in [_standard, _estate, _mpv, _minibus, _miniCar, _miniTruck]) {
      expect(find.text(v.name), findsOneWidget);
    }
  });

  testWidgets('shows live seats and bags, not the values drawn in the design',
      (tester) async {
    // The design draws Estate as 4 Seats 4 Bags; the live catalogue says
    // 5 Seats 4 Bags. The screen must show what the API sent.
    when(() => repo.list()).thenAnswer((_) async => const Ok([_estate]));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('5 Seats'), findsOneWidget);
    expect(find.textContaining('4 Bags'), findsOneWidget);
  });

  testWidgets('an unknown category name still renders via the generic fallback',
      (tester) async {
    when(() => repo.list()).thenAnswer((_) async => const Ok([_futureCategory]));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // Must render the name and capacity like any other card - not blank,
    // not crashed, not skipped.
    expect(find.text('HoverPod 3000'), findsOneWidget);
    expect(find.textContaining('3 Seats'), findsOneWidget);
    expect(find.textContaining('1 Bags'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an error state with a retry affordance on failure',
      (tester) async {
    when(() => repo.list()).thenAnswer(
        (_) async => const Err(ApiException('INTERNAL', 'Server error', 500)));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Server error'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('retry re-calls the repository', (tester) async {
    var calls = 0;
    when(() => repo.list()).thenAnswer((_) async {
      calls++;
      return calls == 1
          ? const Err(ApiException('INTERNAL', 'Server error', 500))
          : const Ok([_standard]);
    });

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Standard'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('shows an empty state when the catalogue has no categories',
      (tester) async {
    when(() => repo.list()).thenAnswer((_) async => const Ok([]));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('No vehicles'), findsOneWidget);
  });

  testWidgets('tapping a card marks it selected', (tester) async {
    when(() => repo.list()).thenAnswer((_) async => const Ok([_standard, _estate]));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // Nothing selected yet — no card announces itself selected. The frame
    // marks selection with a grey fill, carried to assistive tech via
    // Semantics rather than a check glyph.
    bool isSelected(String label) => tester
        .getSemantics(find.bySemanticsLabel(RegExp(label)).first)
        .hasFlag(SemanticsFlag.isSelected);

    expect(isSelected('Standard'), isFalse);

    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();

    expect(isSelected('Standard'), isTrue);
  });

  testWidgets('selecting a category invokes the onSelected callback',
      (tester) async {
    VehicleCategory? selected;
    when(() => repo.list()).thenAnswer((_) async => const Ok([_standard, _estate]));

    await tester.pumpWidget(_harness(repo, onSelected: (v) => selected = v));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Estate'));
    await tester.pumpAndSettle();

    expect(selected, _estate);
  });

  testWidgets('switching selection moves the check mark, not duplicates it',
      (tester) async {
    when(() => repo.list()).thenAnswer((_) async => const Ok([_standard, _estate]));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estate'));
    await tester.pumpAndSettle();

    bool isSelected(String label) => tester
        .getSemantics(find.bySemanticsLabel(RegExp(label)).first)
        .hasFlag(SemanticsFlag.isSelected);

    expect(isSelected('Standard'), isFalse);
    expect(isSelected('Estate'), isTrue);
  });

  testWidgets('renders in dark mode', (tester) async {
    when(() => repo.list()).thenAnswer((_) async => const Ok([_standard, _estate]));

    await tester.pumpWidget(_harness(repo, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Estate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category with zero seats and zero bags is not rendered',
      (tester) async {
    // The API COALESCEs both to 0 when unconfigured; showing "0 Seats 0 Bags"
    // would state something false.
    const zeroCapacity = VehicleCategory(
        id: 'z', name: 'Ghost', seats: 0, bags: 0, priceMultiplier: 1.0);
    when(() => repo.list())
        .thenAnswer((_) async => const Ok([_standard, zeroCapacity]));

    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Ghost'), findsNothing);
  });
}
