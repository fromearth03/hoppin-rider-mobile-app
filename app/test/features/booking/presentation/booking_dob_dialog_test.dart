import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/api/error_codes.dart';
import 'package:hoppin_rider/core/auth/account_generation.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/features/auth/data/profile_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/widgets/booking_dob_dialog.dart';
import 'package:mocktail/mocktail.dart';

class _Profiles extends Mock implements ProfileRepository {}

const _profile = RiderProfile(
  fullName: 'Test Rider',
  phoneNumber: null,
  email: 'rider@example.com',
  avatarUrl: null,
  dateOfBirth: '2000-01-01',
  rating: null,
  ratingCount: 0,
);

void main() {
  late _Profiles profiles;
  late ProviderContainer container;
  RiderProfile? returned;

  setUp(() {
    profiles = _Profiles();
    returned = null;
    container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWithValue(profiles)],
    );
  });
  tearDown(() => container.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await showDialog<RiderProfile>(
                    context: context,
                    builder: (_) => const BookingDobDialog(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String date) async {
    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), date);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  test('DOB_REQUIRED has the agreed wording', () {
    expect(
      RiderErrorCopy.forCode('DOB_REQUIRED'),
      'Add your date of birth before booking.',
    );
  });

  testWidgets('cancel preserves the booking and never writes a profile', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    verifyZeroInteractions(profiles);
  });

  testWidgets('missing and underage dates never reach the API', (tester) async {
    await open(tester);
    await tester.tap(find.text('Save date of birth'));
    await tester.pump();
    expect(find.text('Enter your date of birth'), findsOneWidget);
    await choose(tester, '01/01/${DateTime.now().year - 10}');
    await tester.tap(find.text('Save date of birth'));
    await tester.pump();
    expect(find.text('You must be at least 13 to use Hoppin'), findsOneWidget);
    verifyZeroInteractions(profiles);
  });

  testWidgets('save failure stays in the prompt and can retry', (tester) async {
    when(() => profiles.patch(dateOfBirth: '2000-01-01')).thenAnswer(
      (_) async =>
          const Err(ApiException('INTERNAL', 'Try again shortly.', 503)),
    );
    await open(tester);
    await choose(tester, '01/01/2000');
    await tester.tap(find.text('Save date of birth'));
    await tester.pumpAndSettle();
    expect(find.text('Try again shortly.'), findsOneWidget);
    expect(returned, isNull);
    when(
      () => profiles.patch(dateOfBirth: '2000-01-01'),
    ).thenAnswer((_) async => const Ok(_profile));
    await tester.tap(find.text('Save date of birth'));
    await tester.pumpAndSettle();
    expect(returned, same(_profile));
    expect(find.byType(BookingDobDialog), findsNothing);
  });

  testWidgets('account switch discards a late saved profile', (tester) async {
    final pending = Completer<Result<RiderProfile>>();
    when(
      () => profiles.patch(dateOfBirth: '2000-01-01'),
    ).thenAnswer((_) => pending.future);
    await open(tester);
    await choose(tester, '01/01/2000');
    await tester.tap(find.text('Save date of birth'));
    await tester.pump();
    container.read(accountGenerationProvider.notifier).state++;
    pending.complete(const Ok(_profile));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    expect(find.byType(BookingDobDialog), findsNothing);
  });
}
