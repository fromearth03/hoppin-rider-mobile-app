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

late AccountRepository repo;
late AuthController auth;

Widget _harness({Brightness brightness = Brightness.light}) => ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith((ref) => auth),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const DeleteAccountScreen(),
      ),
    );

/// Taps Delete on the screen, then Delete again in the confirm dialog.
///
/// Deliberately `pump`, not `pumpAndSettle`, after confirming: on success the
/// button keeps its spinner (the real app navigates away on sign-out rather
/// than returning the screen to rest), so settling would never terminate.
Future<void> deleteAndConfirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
  // The dialog's Delete is the second one on screen.
  await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
  await tester.pump(); // dismiss the dialog
  await tester.pump(); // let the awaited call resolve
}

void main() {
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

  testWidgets('shows the title, back arrow and the corrected copy',
      (tester) async {
    await tester.pumpWidget(_harness());

    expect(find.text('Delete Account'), findsNWidgets(2)); // header + card
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.textContaining('Permanent Deletion'), findsOneWidget);
    expect(find.textContaining('Temporary Deactivation'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsWidgets);
  });

  testWidgets(
      'Deactivate stays genuinely disabled — no deactivate endpoint exists',
      (tester) async {
    await tester.pumpWidget(_harness());

    final deactivate =
        tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Deactivate'));
    expect(deactivate.onPressed, isNull,
        reason: 'a live Deactivate would have to call delete, which is a '
            'different and irreversible thing');
  });

  testWidgets('Delete is live now', (tester) async {
    await tester.pumpWidget(_harness());

    final delete = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));
    expect(delete.onPressed, isNotNull);
  });

  testWidgets('Delete confirms first, and Cancel does not call the server',
      (tester) async {
    await tester.pumpWidget(_harness());

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.deleteAccount());
    verifyNever(() => auth.signOut());
  });

  testWidgets('confirming deletes and then signs the rider out',
      (tester) async {
    when(() => repo.deleteAccount()).thenAnswer((_) async => const Ok(
        AccountDeletion(message: 'Your account has been deleted and your '
            'personal data erased.', status: 'deleted')));

    await tester.pumpWidget(_harness());
    await deleteAndConfirm(tester);

    verify(() => repo.deleteAccount()).called(1);
    // The account is gone; staying signed in to it would be a lie.
    verify(() => auth.signOut()).called(1);
  });

  testWidgets('a 409 lists the server blockers and does NOT sign out',
      (tester) async {
    when(() => repo.deleteAccount()).thenAnswer((_) async =>
        const Err<AccountDeletion>(ApiException(
          'DELETION_BLOCKED',
          'account cannot be deleted yet',
          409,
          fields: {
            'blockers': ['You have a ride in progress.', 'A dispute is open.'],
          },
        )));

    await tester.pumpWidget(_harness());
    await deleteAndConfirm(tester);
    // The screen comes back to rest on a refusal, so it can settle here.
    await tester.pumpAndSettle();

    // Server copy, verbatim, and still on screen rather than in a snackbar.
    expect(find.textContaining('You have a ride in progress.'), findsOneWidget);
    expect(find.textContaining('A dispute is open.'), findsOneWidget);
    expect(find.text('Your account cannot be deleted yet'), findsOneWidget);

    verifyNever(() => auth.signOut());

    // The button is usable again once the rider clears the blockers.
    final delete = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));
    expect(delete.onPressed, isNotNull);
  });

  testWidgets('an ordinary failure shows the server message, not a fake success',
      (tester) async {
    when(() => repo.deleteAccount()).thenAnswer((_) async =>
        const Err<AccountDeletion>(
            ApiException('INTERNAL', 'server error', 500)));

    await tester.pumpWidget(_harness());
    await deleteAndConfirm(tester);
    await tester.pumpAndSettle();

    expect(find.text('server error'), findsOneWidget);
    verifyNever(() => auth.signOut());
  });

  testWidgets('says plainly how to pause an account today', (tester) async {
    await tester.pumpWidget(_harness());

    expect(find.textContaining('email Support@hoppin.com'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    expect(find.textContaining('Permanent Deletion'), findsOneWidget);
  });
}
