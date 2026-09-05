import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/api/api_exception.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/places_repository.dart';
import 'package:hoppin_rider/features/booking/data/saved_locations_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/saved_places_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hoppin_rider/shared/widgets/skeleton.dart';

class _MockSavedRepo extends Mock implements SavedLocationsRepository {}

class _MockPlacesRepo extends Mock implements PlacesRepository {}

SavedLocation _place({
  String id = 'sl_1',
  String label = 'Home',
  double lat = 51.5,
  double lng = -0.1,
}) =>
    SavedLocation(id: id, label: label, lat: lat, lng: lng);

Widget _harness(
  SavedLocationsRepository repo, {
  PlacesRepository? placesRepo,
  Brightness brightness = Brightness.light,
}) =>
    ProviderScope(
      overrides: [
        savedLocationsRepositoryProvider.overrideWithValue(repo),
        if (placesRepo != null)
          placesRepositoryProvider.overrideWithValue(placesRepo),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const SavedPlacesScreen(),
      ),
    );

void main() {
  late _MockSavedRepo repo;
  late _MockPlacesRepo placesRepo;

  setUp(() {
    repo = _MockSavedRepo();
    placesRepo = _MockPlacesRepo();
    when(() => repo.remove(any())).thenAnswer((_) async => const Ok(null));
    when(() => repo.add(
          label: any(named: 'label'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
        )).thenAnswer((_) async => Ok(_place()));
    when(() => repo.rename(any(), any()))
        .thenAnswer((_) async => Ok(_place(label: 'Renamed')));
    when(() => placesRepo.search(any())).thenAnswer((_) async => const Ok([]));
  });

  group('loading, error, empty', () {
    testWidgets('shows a skeleton while the list is in flight',
        (tester) async {
      final completer = Completer<Result<List<SavedLocation>>>();
      when(() => repo.list()).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      // A skeleton, not a spinner: it reserves the row layout so nothing
      // jumps when the real places arrive.
      expect(find.byType(SkeletonList), findsOneWidget);

      completer.complete(const Ok([]));
      await tester.pumpAndSettle();
    });

    testWidgets('shows an honest empty state with no saved places',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.textContaining('No saved places'), findsOneWidget);
      // No demo fakeness: nothing that looks like a real saved place renders.
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('shows the server error message on failure and offers retry',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Err(
          ApiException('INTERNAL', 'Could not load your saved places.', 500)));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.text('Could not load your saved places.'), findsOneWidget);

      when(() => repo.list()).thenAnswer((_) async => Ok([_place()]));
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('populated list', () {
    testWidgets('renders each saved place label', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([
            _place(id: 'sl_1', label: 'Home'),
            _place(id: 'sl_2', label: 'Work'),
          ]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });
  });

  group('remove', () {
    testWidgets('asks for confirmation before removing', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_place()]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      verifyNever(() => repo.remove(any()));
    });

    testWidgets('removes only after confirming', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_place(id: 'sl_1')]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      verify(() => repo.remove('sl_1')).called(1);
    });

    testWidgets('dismissing the dialog leaves the place alone',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_place(id: 'sl_1')]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.remove(any()));
    });

    testWidgets('shows the server error message when removal fails',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([_place(id: 'sl_1')]));
      when(() => repo.remove('sl_1')).thenAnswer((_) async => const Err(
          ApiException('INTERNAL', 'Could not remove that place.', 500)));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Could not remove that place.'), findsOneWidget);
    });
  });

  group('rename', () {
    testWidgets('opens a dialog with the current label pre-filled',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([
            _place(id: 'sl_1', label: 'Home'),
          ]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'Home');
    });

    testWidgets('saving calls rename with the edited label', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([
            _place(id: 'sl_1', label: 'Home'),
          ]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'My House');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => repo.rename('sl_1', 'My House')).called(1);
    });

    testWidgets('cancelling leaves the place unrenamed', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => Ok([
            _place(id: 'sl_1', label: 'Home'),
          ]));

      await tester.pumpWidget(_harness(repo));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.rename(any(), any()));
    });
  });

  group('add', () {
    testWidgets('tapping Add a place opens the add dialog', (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));

      await tester.pumpWidget(_harness(repo, placesRepo: placesRepo));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add a place'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('searching shows results sourced from the places repository',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));
      when(() => placesRepo.search('Manchester')).thenAnswer((_) async => Ok([
            const PlaceSuggestion(
              label: 'Manchester Piccadilly',
              lat: 53.4,
              lng: -2.2,
              postcode: 'M1 2AA',
              source: 'map',
            ),
          ]));

      await tester.pumpWidget(_harness(repo, placesRepo: placesRepo));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add a place'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Manchester');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Manchester Piccadilly'), findsOneWidget);
    });

    testWidgets(
        'choosing a result and naming it calls add with the coordinates',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));
      when(() => placesRepo.search('Manchester')).thenAnswer((_) async => Ok([
            const PlaceSuggestion(
              label: 'Manchester Piccadilly',
              lat: 53.4,
              lng: -2.2,
              postcode: null,
              source: 'map',
            ),
          ]));

      await tester.pumpWidget(_harness(repo, placesRepo: placesRepo));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add a place'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Manchester');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      await tester.tap(find.text('Manchester Piccadilly'));
      await tester.pumpAndSettle();

      // Choosing a result fills the label field with a sensible default,
      // which the rider can still edit before saving.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => repo.add(
            label: 'Manchester Piccadilly',
            lat: 53.4,
            lng: -2.2,
          )).called(1);
    });

    testWidgets('shows the server error message when add fails',
        (tester) async {
      when(() => repo.list()).thenAnswer((_) async => const Ok([]));
      when(() => placesRepo.search('Manchester')).thenAnswer((_) async => Ok([
            const PlaceSuggestion(
              label: 'Manchester Piccadilly',
              lat: 53.4,
              lng: -2.2,
              postcode: null,
              source: 'map',
            ),
          ]));
      when(() => repo.add(
            label: any(named: 'label'),
            lat: any(named: 'lat'),
            lng: any(named: 'lng'),
          )).thenAnswer((_) async => const Err(
          ApiException('VALIDATION_FAILED', 'Give this place a name.', 0)));

      await tester.pumpWidget(_harness(repo, placesRepo: placesRepo));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add a place'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Manchester');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      await tester.tap(find.text('Manchester Piccadilly'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Give this place a name.'), findsOneWidget);
    });
  });

  testWidgets('renders in dark mode', (tester) async {
    when(() => repo.list()).thenAnswer((_) async => Ok([
          _place(id: 'sl_1', label: 'Home'),
        ]));

    await tester.pumpWidget(_harness(repo, brightness: Brightness.dark));
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Saved Places'), findsOneWidget);
  });
}
