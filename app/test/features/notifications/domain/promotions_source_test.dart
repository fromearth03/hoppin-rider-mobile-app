import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/notifications/application/promotional_controller.dart';
import 'package:hoppin_rider/features/notifications/data/promotions_source.dart';
import 'package:hoppin_rider/features/notifications/domain/promotion_item.dart';
import 'package:mocktail/mocktail.dart';

class _MockSource extends Mock implements PromotionsSource {}

void main() {
  late _MockSource source;
  late PromotionalController controller;

  setUp(() {
    source = _MockSource();
    controller = PromotionalController(source);
  });

  test('load fills the list from the source', () async {
    when(() => source.list()).thenAnswer((_) async => Ok<List<PromotionItem>>([
          PromotionItem(
            id: 'FIRST10',
            title: 'First Ride Discount',
            description: "Get 10% off on your first ride with Hoppin'",
            status: PromotionStatus.active,
            validUntil: DateTime(2026, 9, 2),
          ),
        ]));

    await controller.load();

    expect(controller.state.items, hasLength(1));
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.error, isNull);
  });

  test('no offers is an empty list, not an error', () async {
    when(() => source.list())
        .thenAnswer((_) async => const Ok<List<PromotionItem>>([]));

    await controller.load();

    expect(controller.state.items, isEmpty);
    expect(controller.state.error, isNull);
  });

  test('a failed load keeps the server copy verbatim', () async {
    when(() => source.list()).thenAnswer((_) async => const Err<List<PromotionItem>>(
        ApiException('INTERNAL', 'internal server error', 500)));

    await controller.load();

    expect(controller.state.error, 'internal server error');
    expect(controller.state.items, isEmpty);
    expect(controller.state.isLoading, isFalse);
  });

  test('a reload clears a previous error', () async {
    when(() => source.list()).thenAnswer((_) async =>
        const Err<List<PromotionItem>>(ApiException('INTERNAL', 'boom', 500)));
    await controller.load();
    expect(controller.state.error, 'boom');

    when(() => source.list())
        .thenAnswer((_) async => const Ok<List<PromotionItem>>([]));
    await controller.load();

    expect(controller.state.error, isNull);
  });
}
