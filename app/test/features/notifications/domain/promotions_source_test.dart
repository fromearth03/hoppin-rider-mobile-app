import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/notifications/data/promotions_source.dart';

void main() {
  test('NoPromotionsSource always returns an empty list', () async {
    const source = NoPromotionsSource();
    expect(await source.list(), isEmpty);
  });
}
