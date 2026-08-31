@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/select_vehicle_screen.dart';
import 'package:hoppin_rider/features/profile/application/personal_information_controller.dart';
import 'package:hoppin_rider/features/profile/domain/personal_information_state.dart';
import 'package:hoppin_rider/features/profile/presentation/personal_information_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockPersonalInfoController extends Mock
    implements PersonalInformationController {}

class _MockVehicleRepository extends Mock implements VehicleRepository {}

const _profile = RiderProfile(
  fullName: 'Taimoor Ali Asghar',
  phoneNumber: '+44 123 567 8910',
  email: 'ali.asghar123@gmail.com',
  avatarUrl: null,
  dateOfBirth: '1995-04-12',
  rating: null,
  ratingCount: 0,
);

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

/// Renders Personal Information and Select Vehicle so they can be put side
/// by side with `docs/figma/extracted/`. See `auth_render_test.dart` for why
/// these are renders, not assertions.
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

  testWidgets('personal information light', (t) async {
    final controller = _MockPersonalInfoController();
    final state = PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
    );
    when(() => controller.state).thenReturn(state);
    when(() => controller.addListener(any(),
            fireImmediately: any(named: 'fireImmediately')))
        .thenAnswer((invocation) {
      final listener = invocation.positionalArguments[0]
          as void Function(PersonalInformationState);
      final fire =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fire) listener(controller.state);
      return () {};
    });

    await shoot(
      t,
      ProviderScope(
        overrides: [
          personalInformationControllerProvider.overrideWith((_) => controller),
        ],
        child: const PersonalInformationScreen(),
      ),
      'personal_information_light',
    );
  });

  testWidgets('select vehicle light', (t) async {
    final repo = _MockVehicleRepository();
    when(() => repo.list()).thenAnswer(
        (_) async => const Ok([_standard, _estate, _mpv, _minibus]));

    await shoot(
      t,
      ProviderScope(
        overrides: [vehicleRepositoryProvider.overrideWithValue(repo)],
        child: const SelectVehicleScreen(),
      ),
      'select_vehicle_light',
    );
  });
}
