import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/profile/application/personal_information_controller.dart';
import 'package:hoppin_rider/features/profile/domain/personal_information_state.dart';
import 'package:hoppin_rider/features/profile/presentation/personal_information_screen.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';
import 'package:mocktail/mocktail.dart';

class _MockController extends Mock implements PersonalInformationController {}

const _profile = RiderProfile(
  fullName: 'Taimoor Ali Asghar',
  phoneNumber: '+44 123 567 8910',
  email: 'ali.asghar123@gmail.com',
  avatarUrl: null,
  dateOfBirth: '1995-04-12',
  rating: null,
  ratingCount: 0,
);

Widget _harness(PersonalInformationController controller,
        {Brightness brightness = Brightness.light}) =>
    ProviderScope(
      overrides: [
        personalInformationControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const PersonalInformationScreen(),
      ),
    );

void main() {
  late _MockController controller;

  void stub(PersonalInformationState snapshot) {
    when(() => controller.state).thenReturn(snapshot);
    // riverpod's StateNotifierProvider subscribes to the notifier as soon as
    // it is created, and relies on that listener firing immediately to seed
    // its own internal state. mocktail leaves unconfigured methods returning
    // null (crashing on addListener's non-nullable return type) and never
    // invokes the callback, so the provider never initializes -- stub it to
    // behave like the real addListener for the fireImmediately case actually
    // used here.
    when(() => controller.addListener(any(),
        fireImmediately:
            any(named: 'fireImmediately'))).thenAnswer((invocation) {
      final listener = invocation.positionalArguments[0]
          as void Function(PersonalInformationState);
      final fireImmediately =
          invocation.namedArguments[#fireImmediately] as bool? ?? true;
      if (fireImmediately) listener(controller.state);
      return () {};
    });
  }

  setUp(() {
    controller = _MockController();
    when(() => controller.save(
          fullName: any(named: 'fullName'),
          phoneNumber: any(named: 'phoneNumber'),
        )).thenAnswer((_) async {});
    stub(const PersonalInformationState());
  });

  testWidgets('shows a loading indicator while the profile loads',
      (tester) async {
    stub(const PersonalInformationState(status: PersonalInformationStatus.loading));

    await tester.pumpWidget(_harness(controller));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('shows an error state when the profile fails to load',
      (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.error,
      loadError: ApiException('INTERNAL', 'Something went wrong on our side. Try again.', 500),
    ));

    await tester.pumpWidget(_harness(controller));

    expect(find.text('Something went wrong on our side. Try again.'),
        findsOneWidget);
  });

  testWidgets('populates full name, email and phone from the profile',
      (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
    ));

    await tester.pumpWidget(_harness(controller));

    expect(find.text('Taimoor Ali Asghar'), findsOneWidget);
    expect(find.text('ali.asghar123@gmail.com'), findsOneWidget);
    expect(find.text('+44 123 567 8910'), findsOneWidget);
  });

  testWidgets('renders email as read-only, never an editable field',
      (tester) async {
    // patch() has no email parameter -- the API cannot change it, so
    // offering an editable field would promise something that always fails.
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
    ));

    await tester.pumpWidget(_harness(controller));

    final emailField = tester.widget<TextField>(find.ancestor(
      of: find.text('ali.asghar123@gmail.com'),
      matching: find.byType(TextField),
    ));
    expect(emailField.enabled, isFalse);
  });

  testWidgets('shows the name alone when rating is null, never a fabricated score',
      (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile, // rating: null
    ));

    await tester.pumpWidget(_harness(controller));

    expect(find.textContaining('5.0'), findsNothing);
    expect(find.textContaining('0.0'), findsNothing);
  });

  testWidgets('blank full name blocks save without calling the controller',
      (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
    ));

    await tester.pumpWidget(_harness(controller));

    final nameField = find.ancestor(
      of: find.text('Taimoor Ali Asghar'),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField, '   ');
    await tester.ensureVisible(find.widgetWithText(HoppinButton, 'Save'));
    await tester.tap(find.widgetWithText(HoppinButton, 'Save'), warnIfMissed: false);
    await tester.pump();

    verifyNever(() => controller.save(
          fullName: any(named: 'fullName'),
          phoneNumber: any(named: 'phoneNumber'),
        ));
    expect(find.text('Enter your name'), findsOneWidget);
  });

  testWidgets('saves the edited name and phone', (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
    ));

    await tester.pumpWidget(_harness(controller));

    final nameField = find.ancestor(
      of: find.text('Taimoor Ali Asghar'),
      matching: find.byType(TextField),
    );
    await tester.enterText(nameField, 'Taimoor Asghar');
    await tester.ensureVisible(find.widgetWithText(HoppinButton, 'Save'));
    await tester.tap(find.widgetWithText(HoppinButton, 'Save'), warnIfMissed: false);
    await tester.pump();

    verify(() => controller.save(
          fullName: 'Taimoor Asghar',
          phoneNumber: '+44 123 567 8910',
        )).called(1);
  });

  testWidgets('disables the button and shows a spinner while saving',
      (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
      isSaving: true,
    ));

    await tester.pumpWidget(_harness(controller));

    final button =
        tester.widget<HoppinButton>(find.byType(HoppinButton));
    expect(button.isLoading, isTrue);
  });

  testWidgets('shows a specific message on 409 PHONE_TAKEN, not a generic failure',
      (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
      saveError:
          ApiException('PHONE_TAKEN', 'That phone number is already in use.', 409),
    ));

    await tester.pumpWidget(_harness(controller));

    expect(find.text('That phone number is already in use.'), findsOneWidget);
    expect(find.textContaining('Something went wrong'), findsNothing);
  });

  testWidgets('shows the server error message on a generic save failure',
      (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
      saveError:
          ApiException('INTERNAL', 'Something went wrong on our side. Try again.', 500),
    ));

    await tester.pumpWidget(_harness(controller));

    expect(find.text('Something went wrong on our side. Try again.'),
        findsOneWidget);
  });

  testWidgets('shows the name alone with no rating text when rating is present',
      (tester) async {
    // Guard against a regression that fabricates a score: a real rating, if
    // ever rendered here, must come from the profile and never be invented.
    const rated = RiderProfile(
      fullName: 'Taimoor Ali Asghar',
      phoneNumber: '+44 123 567 8910',
      email: 'ali.asghar123@gmail.com',
      avatarUrl: null,
      dateOfBirth: '1995-04-12',
      rating: 4.8,
      ratingCount: 12,
    );
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: rated,
    ));

    await tester.pumpWidget(_harness(controller));

    expect(find.text('Taimoor Ali Asghar'), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    stub(const PersonalInformationState(
      status: PersonalInformationStatus.ready,
      profile: _profile,
    ));

    await tester.pumpWidget(_harness(controller, brightness: Brightness.dark));
    await tester.pump();

    expect(find.widgetWithText(HoppinButton, 'Save'), findsOneWidget);
  });
}
