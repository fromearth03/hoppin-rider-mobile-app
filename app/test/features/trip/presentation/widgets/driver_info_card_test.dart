import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/money.dart';
import 'package:hoppin_rider/core/result.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/payments/data/payment_methods_repository.dart';
import 'package:hoppin_rider/features/trip/data/live_trip_source.dart';
import 'package:hoppin_rider/features/trip/presentation/widgets/driver_info_card.dart';
import 'package:mocktail/mocktail.dart';

class _MockPayments extends Mock implements PaymentMethodsRepository {}

/// The card's default-card chip reads the payments repository; the harness
/// stubs it empty so the chip stays hidden unless a test opts in.
Widget _harness(Widget child,
    {Brightness brightness = Brightness.light, List<SavedCard>? cards}) {
  final payments = _MockPayments();
  when(() => payments.list()).thenAnswer((_) async => Ok(cards ?? const []));
  return ProviderScope(
    overrides: [
      paymentMethodsRepositoryProvider.overrideWithValue(payments),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders the awaiting-driver state without crashing or a blank card',
      (tester) async {
    await tester.pumpWidget(_harness(
      DriverInfoCard(
        driver: null,
        onChat: () {},
        onSafety: () {},
        onCancel: () {},
      ),
    ));

    expect(find.text('Finding your driver'), findsOneWidget);
    // No driver name, rating or vehicle details should render.
    expect(find.textContaining('★'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the driver name and rating with count once assigned',
      (tester) async {
    const driver = TripDriver(
      name: 'George',
      rating: 4.3,
      ratingCount: 113,
      tripsCompleted: 1130,
      plate: 'RV 20 OZT',
      vehicleType: 'White Prius',
      seats: 4,
      bags: 2,
    );

    await tester.pumpWidget(_harness(
      DriverInfoCard(driver: driver, onChat: () {}, onSafety: () {}, onCancel: () {}),
    ));

    expect(find.text('George'), findsOneWidget);
    expect(find.text('4.3 (113)'), findsOneWidget);
  });

  testWidgets('never renders a fabricated rating for a driver with no rating yet',
      (tester) async {
    const driver = TripDriver(
      name: 'New Driver',
      rating: null,
      ratingCount: 0,
      tripsCompleted: 0,
      plate: 'AB 12 CDE',
      vehicleType: 'Blue Civic',
      seats: 4,
      bags: 2,
    );

    await tester.pumpWidget(_harness(
      DriverInfoCard(driver: driver, onChat: () {}, onSafety: () {}, onCancel: () {}),
    ));

    expect(find.text('New Driver'), findsOneWidget);
    // Never a default 5.0 or any fabricated score.
    expect(find.textContaining('5.0'), findsNothing);
    expect(find.textContaining('(0)'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('Cancel Ride, chat and safety actions fire their callbacks',
      (tester) async {
    const driver = TripDriver(
      name: 'George',
      rating: 4.3,
      ratingCount: 113,
      tripsCompleted: 1130,
      plate: 'RV 20 OZT',
      vehicleType: 'White Prius',
      seats: 4,
      bags: 2,
    );

    var chatTapped = false;
    var safetyTapped = false;
    var cancelTapped = false;

    await tester.pumpWidget(_harness(
      DriverInfoCard(
        driver: driver,
        onChat: () => chatTapped = true,
        onSafety: () => safetyTapped = true,
        onCancel: () => cancelTapped = true,
      ),
    ));

    await tester.tap(find.byIcon(Icons.chat_bubble));
    await tester.tap(find.byIcon(Icons.warning_rounded));
    // With a driver assigned the frame labels the action Cancel Booking.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cancel Booking'));
    await tester.pump();

    expect(chatTapped, isTrue);
    expect(safetyTapped, isTrue);
    expect(cancelTapped, isTrue);
  });

  testWidgets('does not draw the call button -- no phone number exists on any endpoint',
      (tester) async {
    const driver = TripDriver(
      name: 'George',
      rating: 4.3,
      ratingCount: 113,
      tripsCompleted: 1130,
      plate: 'RV 20 OZT',
      vehicleType: 'White Prius',
      seats: 4,
      bags: 2,
    );

    await tester.pumpWidget(_harness(
      DriverInfoCard(driver: driver, onChat: () {}, onSafety: () {}, onCancel: () {}),
    ));

    expect(find.byIcon(Icons.call), findsNothing);
    expect(find.byIcon(Icons.phone), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    const driver = TripDriver(
      name: 'George',
      rating: 4.3,
      ratingCount: 113,
      tripsCompleted: 1130,
      plate: 'RV 20 OZT',
      vehicleType: 'White Prius',
      seats: 4,
      bags: 2,
    );

    await tester.pumpWidget(_harness(
      DriverInfoCard(driver: driver, onChat: () {}, onSafety: () {}, onCancel: () {}),
      brightness: Brightness.dark,
    ));

    expect(find.text('George'), findsOneWidget);
  });

  testWidgets(
      'renders the frame\'s spec rows, fare total and Cancel Booking label',
      (tester) async {
    const driver = TripDriver(
      name: 'George',
      rating: 4.3,
      ratingCount: 1130,
      tripsCompleted: 1130,
      plate: 'RV 20 OZT',
      vehicleType: 'White Prius',
      seats: 4,
      bags: 2,
    );

    await tester.pumpWidget(_harness(
      DriverInfoCard(
        driver: driver,
        totalPence: const Pence(886),
        onChat: () {},
        onSafety: () {},
        onCancel: () {},
      ),
    ));
    await tester.pump();

    expect(find.text('Ride Details'), findsOneWidget);
    expect(find.text('Complete Rides'), findsOneWidget);
    expect(find.text('1130'), findsOneWidget);
    expect(find.text('Vehicle Number'), findsOneWidget);
    expect(find.text('RV 20 OZT'), findsOneWidget);
    expect(find.text('White Prius'), findsOneWidget);
    expect(find.text('4 Seats 2 Bags'), findsOneWidget);
    expect(find.text('£8.86'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Cancel Booking'),
        findsOneWidget);
  });

  testWidgets('shows the default card chip only when a card exists',
      (tester) async {
    const driver = TripDriver(
      name: 'George',
      rating: null,
      ratingCount: 0,
      tripsCompleted: 3,
      plate: null,
      vehicleType: null,
      seats: 0,
      bags: 0,
    );
    const visa = SavedCard(
      paymentMethodId: 'pm_1',
      brand: 'visa',
      last4: '4242',
      expMonth: 12,
      expYear: 2030,
      isDefault: true,
    );

    await tester.pumpWidget(_harness(
      DriverInfoCard(
          driver: driver, onChat: () {}, onSafety: () {}, onCancel: () {}),
      cards: const [visa],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Visa ····4242'), findsOneWidget);
  });

  testWidgets('the awaiting state carries no spec rows and keeps Cancel Ride',
      (tester) async {
    await tester.pumpWidget(_harness(
      DriverInfoCard(
          driver: null, onChat: () {}, onSafety: () {}, onCancel: () {}),
    ));

    expect(find.text('Ride Details'), findsNothing);
    expect(find.text('Complete Rides'), findsNothing);
    expect(
        find.widgetWithText(ElevatedButton, 'Cancel Ride'), findsOneWidget);
  });
}
