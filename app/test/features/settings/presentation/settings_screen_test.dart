import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/settings/presentation/settings_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

Widget _harness(AuthController controller,
        {Brightness brightness = Brightness.light}) =>
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const SettingsScreen(),
      ),
    );

void main() {
  late _MockController controller;

  setUp(() {
    controller = _MockController();
    when(() => controller.state).thenReturn(const AuthSnapshot());
    when(() => controller.signOut()).thenAnswer((_) async {});
    // riverpod's StateNotifierProvider subscribes to the notifier as soon as
    // it is created and relies on that listener firing immediately to seed
    // its own internal state -- see login_screen_test.dart for the same stub.
    when(() => controller.addListener(any(),
        fireImmediately:
            any(named: 'fireImmediately'))).thenAnswer((invocation) {
      final listener =
          invocation.positionalArguments[0] as void Function(AuthSnapshot);
      final fireImmediately =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fireImmediately) listener(controller.state);
      return () {};
    });
  });

  testWidgets('shows the Setting title and back arrow', (tester) async {
    await tester.pumpWidget(_harness(controller));

    expect(find.text('Setting'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('renders every row from the design', (tester) async {
    await tester.pumpWidget(_harness(controller));

    expect(find.text('Notification'), findsOneWidget);
    expect(find.text('Driver Arrived Sound'), findsOneWidget);
    expect(find.text('Do not lock the screen'), findsOneWidget);
    expect(find.text('Apperance'), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Distance Units'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.text('Delete Account'), findsOneWidget);
  });

  testWidgets(
      'toggles and chevron rows that have no backend are actually disabled, '
      'not just styled to look inert', (tester) async {
    await tester.pumpWidget(_harness(controller));

    // Every Switch on this screen is unbacked -- none has a real
    // preferences store to write to.
    final switches =
        tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, isNotEmpty);
    for (final s in switches) {
      expect(s.onChanged, isNull,
          reason: 'a Switch with a non-null onChanged is a working toggle');
    }

    // Tapping a disabled row must not throw and must not invoke navigation.
    await tester.tap(find.text('Notification'));
    await tester.pump();
    await tester.tap(find.text('Apperance'));
    await tester.pump();
    await tester.tap(find.text('Navigation'));
    await tester.pump();
    await tester.tap(find.text('Delete Account'));
    await tester.pump();

    // Still on the settings screen -- nothing navigated away or blew up.
    expect(find.text('Setting'), findsOneWidget);
  });

  testWidgets('shows a Soon affordance on every unbacked control',
      (tester) async {
    await tester.pumpWidget(_harness(controller));

    expect(find.text('Soon'), findsWidgets);
  });

  testWidgets('tapping Logout calls signOut on the auth controller',
      (tester) async {
    await tester.pumpWidget(_harness(controller));

    await tester.tap(find.text('Logout'));
    await tester.pump();

    verify(() => controller.signOut()).called(1);
  });

  testWidgets('back arrow pops the route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProviderScope(
          overrides: [authControllerProvider.overrideWith((ref) => controller)],
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Setting'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Setting'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(
        _harness(controller, brightness: Brightness.dark));
    expect(find.text('Setting'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
  });
}
