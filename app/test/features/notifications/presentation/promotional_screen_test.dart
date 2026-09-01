import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/notifications/data/promotions_source.dart';
import 'package:hoppin_rider/features/notifications/domain/promotion_item.dart';
import 'package:hoppin_rider/features/notifications/presentation/promotional_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockSource extends Mock implements PromotionsSource {}

final _sampleItems = [
  PromotionItem(
    id: 'FIRST10',
    title: 'First Ride Discount',
    description: "Get 10% off on your first ride with Hoppin'",
    status: PromotionStatus.active,
    validUntil: DateTime(2026, 9, 2),
  ),
  PromotionItem(
    id: 'FIRST10B',
    title: 'First Ride Discount',
    description: "Get 10% off on your first ride with Hoppin'",
    status: PromotionStatus.availed,
    validUntil: DateTime(2026, 9, 2),
  ),
  PromotionItem(
    id: 'FIRST10C',
    title: 'First Ride Discount',
    description: "Get 10% off on your first ride with Hoppin'",
    status: PromotionStatus.expired,
    validUntil: DateTime(2026, 9, 2),
  ),
];

Widget _harness(PromotionsSource source,
        {Brightness brightness = Brightness.light}) =>
    ProviderScope(
      overrides: [
        promotionsSourceProvider.overrideWithValue(source),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const PromotionalScreen(),
      ),
    );

void main() {
  late _MockSource source;

  setUp(() {
    source = _MockSource();
    when(() => source.list())
        .thenAnswer((_) async => const Ok<List<PromotionItem>>([]));
  });

  testWidgets('has a const constructor taking only a key', (tester) async {
    const screen = PromotionalScreen(key: Key('p'));
    expect(screen.key, const Key('p'));
  });

  testWidgets('loads from the live source on open', (tester) async {
    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    verify(() => source.list()).called(1);
  });

  testWidgets('renders an honest empty state when there are no offers',
      (tester) async {
    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('Promotional'), findsOneWidget);
    expect(find.text('First Ride Discount'), findsNothing);
    expect(find.textContaining('No promotions'), findsOneWidget);
  });

  testWidgets('a failed load renders the server copy verbatim', (tester) async {
    when(() => source.list()).thenAnswer((_) async => const Err<List<PromotionItem>>(
        ApiException('INTERNAL', 'internal server error', 500)));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('internal server error'), findsOneWidget);
    expect(find.textContaining('Check back later'), findsNothing);
  });

  testWidgets('renders each promotion with its server-owned status pill',
      (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<PromotionItem>>(_sampleItems));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('First Ride Discount'), findsNWidgets(3));
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Availed'), findsOneWidget);
    expect(find.text('Expire'), findsOneWidget);
  });

  testWidgets('renders the valid-until date', (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => Ok<List<PromotionItem>>([_sampleItems.first]));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.textContaining('Valid Until'), findsOneWidget);
    expect(find.textContaining('02 September, 2026'), findsOneWidget);
  });

  testWidgets('an open-ended offer draws no fabricated date', (tester) async {
    when(() => source.list())
        .thenAnswer((_) async => const Ok<List<PromotionItem>>([
              PromotionItem(
                id: 'FOREVER',
                title: 'Always on',
                description: 'No expiry',
                status: PromotionStatus.active,
                validUntil: null,
              ),
            ]));

    await tester.pumpWidget(_harness(source));
    await tester.pumpAndSettle();

    expect(find.text('Always on'), findsOneWidget);
    expect(find.textContaining('Valid Until'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(source, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(find.text('Promotional'), findsOneWidget);
  });
}
