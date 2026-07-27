import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/location/location_providers.dart';
import 'package:hoppin_rider/features/location/location_service.dart';
import 'package:hoppin_rider/features/safety/safety_screen.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// SAFETY — the SOS must not lie about what it does, and must never suppress
/// the 999 instruction.
///
/// Two life-safety defects are pinned here:
///
/// 1. The confirm dialog used to say the SOS sends "your location, trip
///    details, and driver information to authorities". `POST /me/sos` raises a
///    panic event on Hoppin's admin safety dashboard (DOCS/04 §Safety). There
///    is NO 999 integration and no emergency-services gateway. A rider who
///    believes the police have been called does not dial 999.
///
/// 2. The "Call 999 first" line rendered ONLY when there was no active trip.
///    During a live ride it was replaced by a logistics note — the highest-risk
///    state was the only one where the rider was not told to dial 999.

class _StubLocationService implements LocationService {
  @override
  Future<LocationPermissionResult> requestPermission() async =>
      LocationPermissionResult.granted;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<({double lat, double lng})?> currentPosition({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      (lat: 52.5862, lng: -2.1281);
}

class _StubSafetyRepository implements SafetyRepository {
  @override
  Future<String> raiseSos({
    String? rideId,
    double? lat,
    double? lng,
    String? note,
    String? liveShareUrl,
  }) async =>
      'c4000000-0000-4000-8000-000000000001';

  @override
  Future<List<SosEvent>> myEvents() async => const [];
}

/// Every string the rider can actually read on the rendered screen.
List<String> _renderedText(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        w.data ?? w.textSpan?.toPlainText() ?? '',
    ];

Future<void> _pumpSafety(
  WidgetTester tester, {
  String? rideId,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(_StubLocationService()),
        safetyRepositoryProvider.overrideWithValue(_StubSafetyRepository()),
      ],
      child: MaterialApp(
        theme: theme ?? HoppinTheme.riderLight(),
        home: SafetyScreen(rideId: rideId),
      ),
    ),
  );
  // Bounded pumps only — never pumpAndSettle.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

Future<void> _openConfirmDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sos_raise_button')));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

/// The words that would make a rider believe help is already on its way from
/// someone other than Hoppin. None of them is true of `POST /me/sos`.
const _forbidden = <String>[
  'authorities',
  'authority',
  'police',
  'emergency services',
  'emergency service',
  '911',
];

void main() {
  group('the SOS never claims the authorities are contacted', () {
    for (final rideId in <String?>[null, 'ride-1']) {
      final state = rideId == null ? 'no active trip' : 'during a live trip';

      testWidgets(
          '🔴 NO FALSE-AUTHORITY CLAIM: the safety screen ($state) never says '
          'authorities / police / emergency services are contacted',
          (tester) async {
        await _pumpSafety(tester, rideId: rideId);

        final rendered = _renderedText(tester).join('\n').toLowerCase();
        for (final lie in _forbidden) {
          expect(
            rendered.contains(lie),
            isFalse,
            reason: '🔴 POST /me/sos only raises a panic event on Hoppin\'s '
                'admin safety dashboard (DOCS/04 §Safety). There is no 999 '
                'integration and no emergency-services gateway. The screen '
                'must never contain "$lie" ANYWHERE — a rider who believes the '
                'police were called will not dial 999. The ban is absolute so '
                'that no future copy edit can reintroduce the claim',
          );
        }
      });

      testWidgets(
          '🔴 NO FALSE-AUTHORITY CLAIM: the SOS confirm dialog ($state) never '
          'says authorities / police / emergency services are contacted',
          (tester) async {
        await _pumpSafety(tester, rideId: rideId);
        await _openConfirmDialog(tester);

        expect(find.text('Trigger Emergency Alert?'), findsOneWidget,
            reason: 'the confirm dialog must be what the test is inspecting');

        final rendered = _renderedText(tester).join('\n').toLowerCase();
        for (final lie in _forbidden) {
          expect(
            rendered.contains(lie),
            isFalse,
            reason: '🔴 the confirm dialog is the LAST thing a rider reads '
                'before committing to the alarm. It must not contain "$lie" '
                'as a claim — the SOS reaches Hoppin\'s safety team, nobody '
                'else',
          );
        }
      });
    }

    testWidgets(
        'the confirm dialog never promises DRIVER INFORMATION is sent — the '
        'app does not have any (seam #5: driverInfo() always returns null)',
        (tester) async {
      await _pumpSafety(tester, rideId: 'ride-1');
      await _openConfirmDialog(tester);

      final rendered = _renderedText(tester).join('\n').toLowerCase();
      expect(
        rendered.contains('driver information'),
        isFalse,
        reason: 'rides_repository.driverInfo() is seam #5 and ALWAYS returns '
            'null — the trip screen renders DriverUnavailableCard on every '
            'live trip. The dialog cannot promise to transmit a fact the app '
            'has already disclosed it does not possess',
      );
    });

    testWidgets(
        'the confirm dialog states what the SOS ACTUALLY does: it alerts '
        "Hoppin's safety team, who see your location and trip", (tester) async {
      await _pumpSafety(tester, rideId: 'ride-1');
      await _openConfirmDialog(tester);

      expect(
        find.byKey(const Key('sos_confirm_what_happens')),
        findsOneWidget,
        reason: 'the dialog must tell the rider what POST /me/sos really does: '
            'raise a panic event that Hoppin\'s safety team sees',
      );
      final rendered = _renderedText(tester).join('\n').toLowerCase();
      expect(
        rendered.contains('safety team'),
        isTrue,
        reason: 'the honest destination of the SOS is Hoppin\'s safety team, '
            'and the rider must be told that is who receives it',
      );
    });
  });

  group('the 999 instruction is ALWAYS present', () {
    for (final rideId in <String?>[null, 'ride-1']) {
      final state = rideId == null ? 'no active trip' : 'during a live trip';

      testWidgets(
          '🔴 999 NEVER SUPPRESSED: "Call 999 first" renders on the safety '
          'screen $state', (tester) async {
        await _pumpSafety(tester, rideId: rideId);

        expect(
          find.byKey(const Key('sos_call_999_callout')),
          findsOneWidget,
          reason: '🔴 the 999 call-out must render in EVERY state. It used to '
              'be suppressed during a live trip — the stranger\'s moving car, '
              'the highest-risk state the product has — in favour of a '
              'logistics note. The rider who most needs to be told to dial '
              '999 was the only one who was not told',
        );
        expect(
          find.textContaining('999'),
          findsWidgets,
          reason: 'the literal number the rider must dial has to be on screen '
              'in state: $state',
        );
        expect(
          find.text('In immediate danger? Call 999 first.'),
          findsOneWidget,
          reason: 'the 999 instruction is the one genuinely life-saving line '
              'on this screen and must be present in state: $state',
        );
      });

      testWidgets(
          '🔴 999 NEVER SUPPRESSED: the confirm dialog repeats the 999 '
          'instruction $state', (tester) async {
        await _pumpSafety(tester, rideId: rideId);
        await _openConfirmDialog(tester);

        expect(
          find.byKey(const Key('sos_confirm_call_999')),
          findsOneWidget,
          reason: 'the confirm dialog is the last surface before the rider '
              'commits to the alarm; the 999 truth must be repeated there in '
              'state: $state, or the dialog implies the SOS is sufficient',
        );
      });
    }

    testWidgets(
        'the 999 instruction and the trip-linkage note COEXIST during a live '
        'trip — they were never mutually exclusive', (tester) async {
      await _pumpSafety(tester, rideId: 'ride-1');

      expect(
        find.byKey(const Key('sos_call_999_callout')),
        findsOneWidget,
        reason: 'the 999 guidance stays during a live trip',
      );
      expect(
        find.byKey(const Key('sos_trip_link_note')),
        findsOneWidget,
        reason: 'the trip linkage is still disclosed — the bug was trading one '
            'fact for the other, not showing either',
      );
    });

    testWidgets('there is no trip-linkage note when there is no trip',
        (tester) async {
      await _pumpSafety(tester);

      expect(
        find.byKey(const Key('sos_trip_link_note')),
        findsNothing,
        reason: 'with no ride there is nothing to link — the app must not claim '
            'a trip it does not have',
      );
      expect(
        find.byKey(const Key('sos_call_999_callout')),
        findsOneWidget,
        reason: 'the 999 guidance is unconditional and survives the absence of '
            'a trip',
      );
    });

    testWidgets('the 999 call-out renders in DARK theme too', (tester) async {
      await _pumpSafety(
        tester,
        rideId: 'ride-1',
        theme: HoppinTheme.riderDark(),
      );

      expect(
        find.text('In immediate danger? Call 999 first.'),
        findsOneWidget,
        reason: 'a rider in dark mode is in exactly the same danger and gets '
            'exactly the same instruction',
      );
    });

    testWidgets(
        'the 999 call-out states plainly that raising an SOS does NOT dial 999',
        (tester) async {
      await _pumpSafety(tester, rideId: 'ride-1');

      expect(
        find.textContaining('does not dial 999 for you'),
        findsOneWidget,
        reason: 'the disclaimer is the whole point: the rider must understand '
            'that raising an SOS is NOT a substitute for dialling 999',
      );
    });
  });
}
