import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/scheduling/presentation/schedule_ride_screen.dart';

/// The backend does expose `POST/GET/DELETE /api/v1/scheduled-rides`
/// (`docs/SCREEN-API-MATRIX.md:74`), but scheduled rides is explicitly listed
/// under "Out — later milestones" in the milestone-1 design doc
/// (`docs/superpowers/specs/2026-08-30-rider-app-milestone1-design.md:57`)
/// and `booking_repository.dart`'s `request()` has no scheduled-time
/// parameter at all. There is no `scheduled_rides_repository.dart` anywhere
/// in this codebase. So this screen matches the Figma layout element for
/// element, but the submit path is honestly unavailable rather than wired to
/// nothing — in the same spirit as the disabled milestone-2 drawer
/// destinations described in `docs/SCREEN-DECISIONS.md`.
Widget _harness({Brightness brightness = Brightness.light}) => MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: const ScheduleRideScreen(),
    );

/// The sheet's content is a lazily-built scrollable, so anything below the
/// fold in the default 800x600 test surface must be scrolled into the
/// viewport before it can be found or tapped. Scrolls the given finder into
/// view rather than dragging a fixed distance, so it neither undershoots nor
/// scrolls straight past the target.
Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    // The GridView inside the sheet has its own (non-scrolling) Scrollable,
    // so the sheet's real Scrollable is the first descendant match.
    scrollable: find
        .descendant(
          of: find.byKey(const Key('scheduleRideSheetList')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the Schedule Ride heading and subtitle', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Schedule Ride'), findsOneWidget);
    expect(find.text('Book your ride in advance'), findsOneWidget);
  });

  testWidgets('renders From and To fields', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
  });

  testWidgets('renders the Schedule for field', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Schedule for'), findsOneWidget);
  });

  testWidgets('renders all four vehicle categories under Ride Type',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Ride Type'));

    expect(find.text('Ride Type'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Estate'), findsOneWidget);
    expect(find.text('MPV'), findsOneWidget);
    expect(find.text('Minibus'), findsOneWidget);
  });

  testWidgets('does not fabricate a fare estimate', (tester) async {
    // There is no estimate call wired to a scheduled future time anywhere in
    // this codebase. A number here would be invented, not quoted by the
    // server -- the project's "no demo fakeness" rule.
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Not available yet'));

    expect(find.text('Fare Estimate'), findsNothing);
    expect(find.textContaining('Base Fare'), findsNothing);
    expect(find.textContaining('£'), findsNothing);
  });

  testWidgets('does not show a working Confirm Schedule submit button',
      (tester) async {
    // A booking control that silently drops the rider's chosen time would be
    // the worst possible outcome here -- so there must be no button that
    // claims to submit a schedule request.
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Not available yet'));

    expect(find.widgetWithText(FilledButton, 'Confirm Schedule'), findsNothing);
  });

  testWidgets('explains scheduled rides arrive in a later milestone',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Not available yet'));

    expect(
      find.textContaining('later'),
      findsWidgets,
    );
  });

  testWidgets('tapping a vehicle category selects it without crashing',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await _scrollUntilVisible(tester, find.text('Estate'));

    await tester.tap(find.text('Estate'));
    await tester.pump();

    // Still on the same screen, nothing thrown.
    expect(find.byType(ScheduleRideScreen), findsOneWidget);
  });

  testWidgets('tapping the schedule-for field opens a date picker',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a date and time'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(find.text('Schedule Ride'), findsOneWidget);

    await _scrollUntilVisible(tester, find.text('Ride Type'));
    expect(find.text('Ride Type'), findsOneWidget);
  });

  testWidgets('has a const constructor taking only a key', (tester) async {
    const screen = ScheduleRideScreen(key: Key('sched'));
    await tester.pumpWidget(MaterialApp(home: screen));
    expect(find.byKey(const Key('sched')), findsOneWidget);
  });
}
