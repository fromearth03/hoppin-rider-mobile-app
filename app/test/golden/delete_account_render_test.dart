@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/application/auth_controller.dart';
import 'package:hoppin_rider/features/auth/domain/auth_state.dart';
import 'package:hoppin_rider/features/settings/data/account_repository.dart';
import 'package:hoppin_rider/features/settings/presentation/delete_account_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockAccountRepo extends Mock implements AccountRepository {}

class _MockAuthController extends Mock implements AuthController {}

/// Renders Delete Account (`Delete Account.png`) so it can be put side by
/// side with `docs/figma/extracted/`. The screen is not routed yet, so it is
/// pumped directly. See `auth_render_test.dart` for why these are renders,
/// not assertions.
void main() {
  late _MockAccountRepo repo;
  late _MockAuthController auth;

  setUp(() {
    repo = _MockAccountRepo();
    auth = _MockAuthController();
    when(() => auth.state).thenReturn(const AuthSnapshot());
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => auth.addListener(any(),
        fireImmediately: any(named: 'fireImmediately'))).thenAnswer((inv) {
      final listener = inv.positionalArguments[0] as void Function(AuthSnapshot);
      final fire = inv.namedArguments[#fireImmediately] as bool? ?? true;
      if (fire) listener(auth.state);
      return () {};
    });
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.light,
    double width = 430,
    Future<void> Function(WidgetTester)? interact,
  }) async {
    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith((ref) => auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const DeleteAccountScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('delete account light', (t) async {
    await shoot(t, 'delete_account_light');
  });

  testWidgets('delete account narrow', (t) async {
    await shoot(t, 'delete_account_narrow', width: 320);
  });

  testWidgets('delete account confirm dialog', (t) async {
    await shoot(t, 'delete_account_confirm', interact: (tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    });
  });

  // The 409 branch: the server's reasons rendered as their own block.
  testWidgets('delete account blocked', (t) async {
    when(() => repo.deleteAccount()).thenAnswer((_) async =>
        const Err<AccountDeletion>(ApiException(
          'DELETION_BLOCKED',
          'account cannot be deleted yet',
          409,
          fields: {
            'blockers': ['You have a ride in progress.', 'A dispute is open.'],
          },
        )));

    await shoot(t, 'delete_account_blocked', interact: (tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    });
  });
}
