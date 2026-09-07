import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/booking/data/places_repository.dart';
import 'package:hoppin_rider/features/booking/data/saved_locations_repository.dart';
import 'package:hoppin_rider/features/booking/presentation/route_entry_screen.dart';
import 'package:hoppin_rider/shared/nav/app_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlaces extends Mock implements PlacesRepository {}

class _MockSaved extends Mock implements SavedLocationsRepository {}

const _savedHome = SavedLocation(
  id: 'sl_1',
  label: 'Home',
  lat: 52.5851,
  lng: -2.1281,
);

const _hanley = PlaceSuggestion(
  label: 'Hanley, Stoke-on-Trent',
  lat: 53.0235,
  lng: -2.1774,
  postcode: 'ST1',
  source: 'map',
);
const _keele = PlaceSuggestion(
  label: 'Keele University',
  lat: 53.0044,
  lng: -2.2734,
  postcode: 'ST5',
  source: 'map',
);

void main() {
  late _MockPlaces places;
  late _MockSaved saved;
  ChosenRoute? received;

  Widget harness() {
    final router = GoRouter(
      initialLocation: AppRoutes.route,
      routes: [
        GoRoute(
          path: AppRoutes.route,
          builder: (_, __) => const RouteEntryScreen(),
        ),
        GoRoute(
          path: AppRoutes.fareConfirm,
          builder: (_, state) {
            received = state.extra as ChosenRoute?;
            return const Scaffold(body: Text('fare screen'));
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        placesRepositoryProvider.overrideWithValue(places),
        savedLocationsRepositoryProvider.overrideWithValue(saved),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
  }

  setUp(() {
    places = _MockPlaces();
    saved = _MockSaved();
    received = null;
    when(() => saved.list()).thenAnswer((_) async => const Ok([_savedHome]));
    when(() => places.search(any()))
        .thenAnswer((_) async => const Ok([_hanley, _keele]));
  });

  Future<void> pickInField(WidgetTester tester, String fieldText,
      PlaceSuggestion suggestion) async {
    final field = find.widgetWithText(TextField, fieldText).first;
    await tester.tap(field);
    await tester.pump();
    await tester.enterText(field, suggestion.label.substring(0, 3));
    await tester.pump(const Duration(milliseconds: 300)); // past the debounce
    await tester.pump(); // the search future resolves
    await tester.tap(find.text(suggestion.label).last);
    await tester.pump();
  }

  testWidgets('Confirm Route stays disabled until both ends are chosen',
      (tester) async {
    await tester.pumpWidget(harness());

    final button = find.widgetWithText(FilledButton, 'Confirm Route');
    expect(button, findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await pickInField(tester, 'Active Location', _hanley);
    expect(tester.widget<FilledButton>(button).onPressed, isNull,
        reason: 'a pickup alone cannot be quoted');

    await pickInField(tester, 'To', _keele);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('confirming pushes fare-confirm carrying the chosen route',
      (tester) async {
    await tester.pumpWidget(harness());
    await pickInField(tester, 'Active Location', _hanley);
    await pickInField(tester, 'To', _keele);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Route'));
    await tester.pumpAndSettle();

    expect(find.text('fare screen'), findsOneWidget);
    expect(received, isNotNull);
    expect(received!.pickup.label, _hanley.label);
    expect(received!.pickup.position.lat, _hanley.lat);
    expect(received!.dropoff.position.lng, _keele.lng);
    expect(received!.stops, isEmpty);
  });

  testWidgets('editing a chosen field invalidates it and disables confirm',
      (tester) async {
    await tester.pumpWidget(harness());
    await pickInField(tester, 'Active Location', _hanley);
    await pickInField(tester, 'To', _keele);

    // Type into the destination field after choosing: the text no longer
    // names a geocoded place, so booking it would send stale coordinates
    // under a fresh label.
    final toField = find.widgetWithText(TextField, _keele.label).first;
    await tester.enterText(toField, 'Keele Univ');
    await tester.pump();

    final button = find.widgetWithText(FilledButton, 'Confirm Route');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });
  testWidgets('the Saved tab lists your places without typing anything',
      (tester) async {
    // It used to filter the SEARCH results down to saved ones, so the tab was
    // empty until the rider typed something that happened to match a saved
    // label — "No saved places match" while My Addresses listed them all.
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('No saved places match.'), findsNothing);
  });

  testWidgets('an empty Saved tab says you have none, not that none matched',
      (tester) async {
    when(() => saved.list()).thenAnswer((_) async => const Ok([]));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('You have not saved any places yet.'), findsOneWidget);
  });

}
