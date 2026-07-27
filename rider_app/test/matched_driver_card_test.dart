import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/features/trip/widgets/matched_driver_card.dart';
import 'package:hoppin_rider/features/trip/widgets/seam_unavailable_states.dart';
import 'package:hoppin_shared/hoppin_shared.dart';
import 'package:hoppin_ui/hoppin_ui.dart';

/// RIDER-02 acceptance: the matched-driver card renders the locked
/// plate-FIRST hierarchy (riders find cars by plate), the initials-avatar
/// identity row, and a 44px+ contact/share/safety action row — pure
/// presentation, state in, events out.
void main() {
  const info = RideDriverInfo(
    fullName: 'Gurpreet Singh',
    rating: 4.9,
    tripsCount: 1480,
    vehicleMake: 'Toyota',
    vehicleModel: 'Prius',
    vehicleColour: 'Silver',
    plate: 'BK72 WNH',
    etaSeconds: 120,
    originLabel: 'Wolverhampton Rail Station',
    destinationLabel: 'New Cross Hospital',
  );

  Widget host(Widget child) => MaterialApp(
        theme: HoppinTheme.riderLight(),
        home: Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      );

  /// Bounded settle — never pumpAndSettle (project convention).
  Future<void> pumpBounded(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('plate is rendered and visually dominant', (tester) async {
    await tester.pumpWidget(host(const MatchedDriverCard(info: info)));
    await pumpBounded(tester);

    final plateText = tester.widget<Text>(find.descendant(
      of: find.byType(PlateChip),
      matching: find.text('BK72 WNH'),
    ));
    final nameText = tester.widget<Text>(find.text('Gurpreet Singh'));
    expect(
      plateText.style!.fontSize!,
      greaterThanOrEqualTo(nameText.style!.fontSize!),
      reason: 'plate-first hierarchy: the plate must lead the card',
    );
  });

  testWidgets('vehicle line renders colour make model', (tester) async {
    await tester.pumpWidget(host(const MatchedDriverCard(info: info)));
    await pumpBounded(tester);

    expect(find.text('Silver Toyota Prius'), findsOneWidget);
  });

  testWidgets('identity row renders initials avatar, name, rating, trips',
      (tester) async {
    // No photoUrl on the fixture — the initials fallback must render.
    await tester.pumpWidget(host(const MatchedDriverCard(info: info)));
    await pumpBounded(tester);

    expect(find.text('GS'), findsOneWidget);
    expect(find.text('Gurpreet Singh'), findsOneWidget);
    expect(find.textContaining('4.9'), findsOneWidget);
    expect(find.textContaining('1,480'), findsOneWidget);
    expect(find.textContaining('trips'), findsOneWidget);
  });

  testWidgets('action row fires callbacks from 44px+ targets', (tester) async {
    var contact = 0;
    var share = 0;
    var safety = 0;
    await tester.pumpWidget(host(MatchedDriverCard(
      info: info,
      onContact: () => contact++,
      onShare: () => share++,
      onSafety: () => safety++,
    )));
    await pumpBounded(tester);

    for (final label in ['Message', 'Share trip', 'Safety']) {
      final target = find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first;
      final size = tester.getSize(target);
      expect(size.height, greaterThanOrEqualTo(44),
          reason: '$label tap target must be at least 44px tall');
      expect(size.width, greaterThanOrEqualTo(44),
          reason: '$label tap target must be at least 44px wide');
      await tester.tap(target);
    }
    await pumpBounded(tester);

    expect(contact, 1);
    expect(share, 1);
    expect(safety, 1);
  });

  // COMMS-02: Wave 0 killed the phone→chat lie at the "Contact" button. The
  // card now carries FOUR distinct affordances — Message (chat, BOUND) and
  // Call (the masked-voice seam #45) are two different buttons doing two
  // different things. That distinction IS the fix.
  group('four distinct affordances — Message and Call are NOT the same button',
      () {
    testWidgets('renders a Call affordance beside Message, Share and Safety',
        (tester) async {
      await tester.pumpWidget(host(MatchedDriverCard(
        info: info,
        onContact: () {},
        onCall: () {},
        onShare: () {},
        onSafety: () {},
      )));
      await pumpBounded(tester);

      for (final label in ['Message', 'Call', 'Share trip', 'Safety']) {
        expect(find.text(label), findsOneWidget,
            reason: '$label is one of the four distinct affordances');
      }
      expect(find.byIcon(Icons.phone_outlined), findsOneWidget,
          reason: 'Call gets the phone icon — and it now leads somewhere that '
              'is actually about calling, not chat');
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget,
          reason: 'Message keeps the chat icon');
    });

    testWidgets('onCall fires SEPARATELY from onContact', (tester) async {
      var contact = 0;
      var call = 0;
      await tester.pumpWidget(host(MatchedDriverCard(
        info: info,
        onContact: () => contact++,
        onCall: () => call++,
      )));
      await pumpBounded(tester);

      final target = find
          .ancestor(of: find.text('Call'), matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44),
          reason: 'Call tap target must be at least 44px tall');
      await tester.tap(target);
      await pumpBounded(tester);

      expect(call, 1, reason: 'Call fired its own callback');
      expect(contact, 0,
          reason: 'Call must NOT route to chat — that was the Wave-0 lie');
    });
  });

  testWidgets('compact density hides the action row and shrinks to a mini-card',
      (tester) async {
    await tester.pumpWidget(host(const MatchedDriverCard(
      info: info,
      compact: true,
    )));
    await pumpBounded(tester);

    // No action row, no vehicle line — a single identity strip.
    expect(find.text('Message'), findsNothing);
    expect(find.text('Call'), findsNothing);
    expect(find.text('Share trip'), findsNothing);
    expect(find.text('Safety'), findsNothing);
    expect(find.text('Silver Toyota Prius'), findsNothing);

    // Small plate + name + rating survive the shrink.
    final chip = tester.widget<PlateChip>(find.byType(PlateChip));
    expect(chip.size, PlateSize.md);
    expect(find.text('Gurpreet Singh'), findsOneWidget);
    expect(find.textContaining('4.9'), findsOneWidget);

    final height = tester.getSize(find.byType(MatchedDriverCard)).height;
    expect(height, lessThan(100),
        reason: 'compact is a mini-card the on-road state can inline');
  });

  // TRIP-03 (#5 seam): when driverInfo is null the card degrades to a
  // DESIGNED, real-sized, honest "driver details unavailable" surface —
  // never a blank SizedBox, never a fabricated identity.
  group('#5 driver-info seam degrade rung', () {
    testWidgets('renders a designed, non-blank unavailable surface',
        (tester) async {
      await tester.pumpWidget(host(const DriverUnavailableCard()));
      await pumpBounded(tester);

      // A designed HopEmptyState surface, not an empty SizedBox.
      expect(find.byType(HopEmptyState), findsOneWidget);
      expect(find.byType(SizedBox), findsWidgets); // never the ONLY child
      final size = tester.getSize(find.byType(DriverUnavailableCard));
      expect(size.height, greaterThan(48),
          reason: 'the degrade rung is a real-sized surface, not blank');
    });

    testWidgets('is honest about the gap and never fabricates a driver',
        (tester) async {
      await tester.pumpWidget(host(const DriverUnavailableCard()));
      await pumpBounded(tester);

      // Honest copy — the seam is disclosed, not faked.
      expect(find.textContaining('Driver details'), findsWidgets);
      // No invented identity leaks in.
      expect(find.text('Gurpreet Singh'), findsNothing);
      expect(find.byType(PlateChip), findsNothing);
    });
  });
}
