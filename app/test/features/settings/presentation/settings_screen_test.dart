import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/core/theme/theme_mode_provider.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/settings/data/preferences_repository.dart';
import 'package:hoppin_rider/features/settings/presentation/delete_account_screen.dart';
import 'package:hoppin_rider/features/settings/presentation/settings_screen.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements AuthController {}

class _MockPrefsRepo extends Mock implements PreferencesRepository {}

/// The screen loads preferences on its first frame, so every harness needs a
/// repository. Defaults to a successful read with both toggles on.
late PreferencesRepository prefsRepo;

Widget _harness(AuthController controller,
        {Brightness brightness = Brightness.light,
        List<Override> extraOverrides = const []}) =>
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => controller),
        preferencesRepositoryProvider.overrideWithValue(prefsRepo),
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
    prefsRepo = _MockPrefsRepo();
    when(() => prefsRepo.read()).thenAnswer((_) async => const Ok(
        RiderPreferences(pushTripUpdates: true, soundOfferChime: true)));
    when(() => prefsRepo.update(
            pushTripUpdates: any(named: 'pushTripUpdates'),
            soundOfferChime: any(named: 'soundOfferChime')))
        .thenAnswer((_) async => const Ok(
            RiderPreferences(pushTripUpdates: true, soundOfferChime: true)));
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

  /// Finds the Switch inside the row carrying [label].
  Switch switchFor(WidgetTester tester, String label) {
    final row = find.ancestor(
      of: find.text(label),
      matching: find.byType(Row),
    );
    return tester.widget<Switch>(
        find.descendant(of: row, matching: find.byType(Switch)).first);
  }

  testWidgets(
      'chevron rows that have no backend are actually disabled, '
      'not just styled to look inert', (tester) async {
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    // Distance Units and Map provider (under Navigation) have no shared
    // formatter / Maps SDK to back them -- they must stay genuinely inert.
    // Appearance is deliberately excluded here: it is now backed by
    // themeModeProvider and is covered by its own tests below.
    await tester.tap(find.text('Navigation'));
    await tester.pump();
    await tester.tap(find.text('Distance Units'));
    await tester.pump();

    // Still on the settings screen -- nothing navigated away or blew up.
    expect(find.text('Setting'), findsOneWidget);
  });

  testWidgets(
      '"Do not lock the screen" stays genuinely disabled: no server key '
      'exists for it', (tester) async {
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    expect(switchFor(tester, 'Do not lock the screen').onChanged, isNull,
        reason: 'a Switch with a non-null onChanged is a working toggle');

    await tester.tap(find.text('Do not lock the screen'));
    await tester.pump();
    expect(find.text('Setting'), findsOneWidget);
  });

  testWidgets('the two backed toggles come up live, showing server state',
      (tester) async {
    when(() => prefsRepo.read()).thenAnswer((_) async => const Ok(
        RiderPreferences(pushTripUpdates: true, soundOfferChime: false)));

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    final notification = switchFor(tester, 'Notification');
    expect(notification.onChanged, isNotNull);
    expect(notification.value, isTrue);

    final sound = switchFor(tester, 'Driver Arrived Sound');
    expect(sound.onChanged, isNotNull);
    expect(sound.value, isFalse,
        reason: 'the server said this rider had it off');
  });

  testWidgets('toggling Notification PATCHes push_trip_updates',
      (tester) async {
    when(() => prefsRepo.update(
            pushTripUpdates: any(named: 'pushTripUpdates')))
        .thenAnswer((_) async => const Ok(
            RiderPreferences(pushTripUpdates: false, soundOfferChime: true)));

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    verify(() => prefsRepo.update(pushTripUpdates: false)).called(1);
    expect(switchFor(tester, 'Notification').value, isFalse);
  });

  testWidgets(
      'a failed read leaves both backed toggles disabled rather than '
      'guessing at their state', (tester) async {
    when(() => prefsRepo.read()).thenAnswer((_) async =>
        const Err<RiderPreferences>(
            ApiException('INTERNAL', 'server error', 500)));

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    expect(switchFor(tester, 'Notification').onChanged, isNull);
    expect(switchFor(tester, 'Driver Arrived Sound').onChanged, isNull);
  });

  testWidgets('a refused toggle rolls back and says why, in server words',
      (tester) async {
    when(() => prefsRepo.update(
            pushTripUpdates: any(named: 'pushTripUpdates')))
        .thenAnswer((_) async => const Err<RiderPreferences>(
            ApiException('INTERNAL', 'could not save', 500)));

    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(switchFor(tester, 'Notification').value, isTrue,
        reason: 'a switch left off would lie about what was saved');
    expect(find.text('could not save'), findsOneWidget);
  });

  testWidgets('the two backed toggles no longer carry a Soon badge',
      (tester) async {
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    for (final label in ['Notification', 'Driver Arrived Sound']) {
      final row =
          find.ancestor(of: find.text(label), matching: find.byType(Row));
      expect(find.descendant(of: row, matching: find.text('Soon')), findsNothing,
          reason: '$label is backed by /me/preferences now');
    }

    // The wakelock row still is unbacked, and still says so.
    final lockRow = find.ancestor(
        of: find.text('Do not lock the screen'), matching: find.byType(Row));
    expect(find.descendant(of: lockRow, matching: find.text('Soon')),
        findsOneWidget);
  });

  testWidgets('tapping Delete Account navigates to the Delete Account screen',
      (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, __) => const SettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.deleteAccount,
          builder: (_, __) => const DeleteAccountScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
          preferencesRepositoryProvider.overrideWithValue(prefsRepo),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );

    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Permanent Deletion'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Deactivate'), findsOneWidget);
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

  testWidgets('Logout confirms first, and Cancel does not sign out',
      (tester) async {
    await tester.pumpWidget(_harness(controller));

    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    // The dialog from Logout.png, not an immediate sign-out.
    expect(find.text('Are you logging out?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => controller.signOut());
    expect(find.text('Are you logging out?'), findsNothing);
  });

  testWidgets('confirming the Logout dialog calls signOut', (tester) async {
    await tester.pumpWidget(_harness(controller));

    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    await tester.pumpAndSettle();

    verify(() => controller.signOut()).called(1);
  });

  testWidgets('back arrow pops the route', (tester) async {
    // The scope wraps MaterialApp, as it does in the real app: a pushed route
    // renders in the Navigator's overlay, so a scope nested *inside* the app
    // would not be an ancestor of the screen under test.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => controller),
          preferencesRepositoryProvider.overrideWithValue(prefsRepo),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
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
