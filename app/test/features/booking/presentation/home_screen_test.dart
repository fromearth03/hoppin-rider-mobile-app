import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/booking/data/vehicle_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/features/booking/presentation/home_screen.dart';
import 'package:hoppin_rider/shared/nav/app_drawer.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuth extends Mock implements AuthController {}

const _categories = [
  VehicleCategory(
    id: 'v1',
    name: 'Standard',
    seats: 4,
    bags: 2,
    priceMultiplier: 1.0,
  ),
];

Widget _harness(
  AuthController auth, {
  Brightness brightness = Brightness.light,
}) =>
    ProviderScope(
      overrides: [
        vehicleCategoriesProvider.overrideWith((ref) async => _categories),
        // The drawer reads the rider's profile from here. Without the
        // override the real provider reaches for Supabase, which is not
        // initialised in a widget test.
        authControllerProvider.overrideWith((ref) => auth),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const HomeScreen(),
      ),
    );

void main() {
  late _MockAuth auth;

  setUp(() {
    auth = _MockAuth();
    when(() => auth.state).thenReturn(const AuthSnapshot());
    // See login_screen_test: mocktail leaves addListener returning null, so
    // the provider never seeds its own state.
    when(() => auth.addListener(any(),
            fireImmediately: any(named: 'fireImmediately')))
        .thenAnswer((invocation) {
      final listener =
          invocation.positionalArguments[0] as void Function(AuthSnapshot);
      final fire =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fire) listener(auth.state);
      return () {};
    });
  });
  testWidgets('tapping the search bar opens route entry', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeScreen()),
        GoRoute(
            path: AppRoutes.route,
            builder: (_, __) => const Scaffold(body: Text('route entry'))),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vehicleCategoriesProvider.overrideWith((ref) async => _categories),
        authControllerProvider.overrideWith((ref) => auth),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Where to & for how much?'));
    await tester.pumpAndSettle();

    expect(find.text('route entry'), findsOneWidget);
  });

  testWidgets('the menu button opens the navigation drawer', (tester) async {
    // The button called Scaffold.of(context).openDrawer() while the Scaffold
    // had no drawer attached, and from a context above the Scaffold at that —
    // two separate reasons it could only ever throw. Nothing caught it,
    // because nothing had tapped it.
    await tester.pumpWidget(_harness(auth));
    await tester.pumpAndSettle();

    expect(find.byType(AppDrawer), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppDrawer), findsOneWidget);
  });

  testWidgets('draws the Ride Type card and the search field', (tester) async {
    await tester.pumpWidget(_harness(auth));
    await tester.pumpAndSettle();

    expect(find.text('Ride Type'), findsOneWidget);
    expect(find.text('Where to & for how much?'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(auth, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(find.text('Ride Type'), findsOneWidget);
  });
}
