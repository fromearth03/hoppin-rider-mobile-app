import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';

void main() {
  Map<String, dynamic> row([Object? icon]) => {
        'id': 'cat-1',
        'name': 'Standard',
        'seats': 4,
        'bags': 2,
        'price_multiplier': 1.0,
        if (icon != null) 'icon_url': icon,
      };

  test('carries the operator-uploaded icon', () {
    expect(VehicleCategory.tryFromJson(row('https://api/x.png'))!.iconUrl,
        'https://api/x.png');
  });

  test('a category with no icon falls back to bundled artwork', () {
    // The apps must render something for a class invented in the panel today,
    // so an absent or blank icon is a normal answer, not a broken row.
    expect(VehicleCategory.tryFromJson(row())!.iconUrl, isNull);
    expect(VehicleCategory.tryFromJson(row('   '))!.iconUrl, isNull);
  });
}
