import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/profile/application/personal_information_controller.dart';
import 'package:hoppin_rider/features/profile/presentation/personal_information_screen.dart';
import 'package:mocktail/mocktail.dart';

class _Profiles extends Mock implements ProfileRepository {}

RiderProfile profile([String? dob]) => RiderProfile(
  fullName: 'Rider',
  phoneNumber: null,
  email: 'r@example.com',
  avatarUrl: null,
  dateOfBirth: dob,
  rating: null,
  ratingCount: 0,
);
void main() {
  late _Profiles repo;
  late PersonalInformationController controller;
  late List<RiderProfile> updates;
  setUp(() {
    repo = _Profiles();
    updates = [];
    when(() => repo.get()).thenAnswer((_) async => Ok(profile()));
  });
  Future<void> open(WidgetTester tester) async {
    controller = PersonalInformationController(repo, onUpdated: updates.add);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalInformationControllerProvider.overrideWith(
            (ref) => controller,
          ),
        ],
        child: const MaterialApp(home: PersonalInformationScreen()),
      ),
    );
    await tester.pumpAndSettle();
    updates.clear();
  }

  Future<void> choose(WidgetTester tester, String date) async {
    await tester.ensureVisible(find.text('Set date of birth'));
    await tester.tap(find.text('Set date of birth'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, date);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'DOB is visible and saved from Personal Information, then locked',
    (tester) async {
      when(
        () => repo.patch(
          fullName: 'Rider',
          phoneNumber: null,
          address: '',
          dateOfBirth: '2000-01-01',
        ),
      ).thenAnswer((_) async => Ok(profile('2000-01-01')));
      await open(tester);
      expect(find.text('Date of birth'), findsOneWidget);
      await choose(tester, '01/01/2000');
      await save(tester);
      verify(
        () => repo.patch(
          fullName: 'Rider',
          phoneNumber: null,
          address: '',
          dateOfBirth: '2000-01-01',
        ),
      ).called(1);
      expect(updates.single.needsDateOfBirth, isFalse);
      expect(find.text('01/01/2000'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '01/01/2000'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('underage DOB cannot be saved', (tester) async {
    await open(tester);
    await choose(tester, '01/01/${DateTime.now().year - 10}');
    await save(tester);
    expect(find.text('You must be at least 13 to use Hoppin'), findsOneWidget);
    verifyNever(
      () => repo.patch(
        fullName: any(named: 'fullName'),
        phoneNumber: any(named: 'phoneNumber'),
        address: any(named: 'address'),
        dateOfBirth: any(named: 'dateOfBirth'),
      ),
    );
  });
  testWidgets('save failure retains date and permits retry without booking', (
    tester,
  ) async {
    when(
      () => repo.patch(
        fullName: 'Rider',
        phoneNumber: null,
        address: '',
        dateOfBirth: '2000-01-01',
      ),
    ).thenAnswer(
      (_) async => const Err(ApiException('INTERNAL', 'Try again.', 503)),
    );
    await open(tester);
    await choose(tester, '01/01/2000');
    await save(tester);
    expect(find.text('Try again.'), findsOneWidget);
    expect(updates, isEmpty);
    when(
      () => repo.patch(
        fullName: 'Rider',
        phoneNumber: null,
        address: '',
        dateOfBirth: '2000-01-01',
      ),
    ).thenAnswer((_) async => Ok(profile('2000-01-01')));
    await save(tester);
    expect(updates.single.needsDateOfBirth, isFalse);
  });
  test(
    'late profile save after disposal cannot update another account',
    () async {
      final pending = Completer<Result<RiderProfile>>();
      when(
        () => repo.patch(fullName: 'Rider', dateOfBirth: '2000-01-01'),
      ).thenAnswer((_) => pending.future);
      final c = PersonalInformationController(repo, onUpdated: updates.add);
      await Future<void>.delayed(Duration.zero);
      updates.clear();
      final saving = c.save(fullName: 'Rider', dateOfBirth: '2000-01-01');
      c.dispose();
      pending.complete(Ok(profile('2000-01-01')));
      await saving;
      expect(updates, isEmpty);
    },
  );
}
