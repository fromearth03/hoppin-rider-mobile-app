import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/core/theme/theme_mode_provider.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/settings/presentation/settings_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

Widget _harness(AuthController controller,
        {Brightness brightness = Brightness.light,
        List<Override> extraOverrides = const []}) =>
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => controller),
        ...extraOverrides,
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

    // Distance Units and Map provider (under Navigation) have no shared
    // formatter / Maps SDK to back them -- they must stay genuinely inert.
    // Appearance is deliberately excluded here: it is now backed by
    // themeModeProvider and is covered by its own tests below.
    await tester.tap(find.text('Notification'));
    await tester.pump();
    await tester.tap(find.text('Navigation'));
    await tester.pump();
    await tester.tap(find.text('Distance Units'));
    await tester.pump();
    await tester.tap(find.text('Delete Account'));
    await tester.pump();

    // Still on the settings screen -- nothing navigated away or blew up.
    expect(find.text('Setting'), findsOneWidget);
  });

  testWidgets(
      'Distance Units and other unbacked controls still show a Soon affordance',
      (tester) async {
    await tester.pumpWidget(_harness(controller));

    expect(find.text('Soon'), findsWidgets);

    // Appearance must NOT carry the Soon badge any more -- it is real now.
    final appearanceRow = find.ancestor(
      of: find.text('Apperance'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: appearanceRow, matching: find.text('Soon')),
      findsNothing,
    );
  });

  testWidgets('tapping Appearance opens the picker sheet', (tester) async {
    await tester.pumpWidget(_harness(controller));

    await tester.tap(find.text('Apperance'));
    await tester.pumpAndSettle();

    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets(
      'choosing Dark from the Appearance sheet resolves a dark theme, not '
      'merely a moved radio button', (tester) async {
    await tester.pumpWidget(_harness(controller));

    await tester.tap(find.text('Apperance'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // The picker sheet writes ThemeMode.dark to themeModeProvider; a real
    // app (app.dart) reads that for MaterialApp.themeMode. Reproduce that
    // wiring here and assert the *resolved* brightness, not the provider's
    // raw value -- this is the difference between a radio button moving and
    // a theme actually changing.
    final context = tester.element(find.text('Setting'));
    final mode = ProviderScope.containerOf(context).read(themeModeProvider);
    expect(mode, ThemeMode.dark);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Builder(
          builder: (context) {
            expect(Theme.of(context).brightness, Brightness.dark);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
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
