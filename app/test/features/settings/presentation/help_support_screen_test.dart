import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/features/settings/data/faq_repository.dart';
import 'package:hoppin_rider/features/settings/presentation/help_support_screen.dart';

const _seededFaqs = [
  Faq(
    question: 'Penalty for cancellation after arrival?',
    answer: 'If a driver cancels a ride after arriving at pickup, then £5 fee '
        'is charged as penalty.',
  ),
  Faq(
    question: 'How to Dispute',
    answer: 'Email us at Support@hoppin.com with your ride details and we will '
        'look into it. A representative responds within 24 hours.',
  ),
];

Widget _harness({
  Brightness brightness = Brightness.light,
  List<Faq> faqs = _seededFaqs,
  Object? faqError,
}) =>
    ProviderScope(
      overrides: [
        riderFaqsProvider.overrideWith((ref) async {
          if (faqError != null) throw faqError;
          return faqs;
        }),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: const HelpSupportScreen(),
      ),
    );

void main() {
  testWidgets('shows a Help & Support title and back arrow', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('shows the three sections from the design', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Frequently Asked Questions (FAQs)'), findsOneWidget);
    expect(find.text('Contact to Support'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Legal'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Legal'), findsOneWidget);
    // The email card gave its slot to File a Complaint — the visible way
    // into the complaints flow the backend already had.
    expect(find.text('File a Complaint'), findsOneWidget);
  });

  testWidgets('first FAQ starts open, as the design draws it', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('£5 fee is charged as penalty'), findsOneWidget);
    // The others start closed.
    expect(find.textContaining('representative responds'), findsNothing);
  });

  testWidgets('tapping a question toggles its answer', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('How to Dispute'));
    await tester.pump();
    expect(find.textContaining('representative responds'), findsOneWidget);

    await tester.tap(find.text('How to Dispute'));
    await tester.pump();
    expect(find.textContaining('representative responds'), findsNothing);
  });

  testWidgets(
    'Open Ticket and the Legal rows are visibly not live — no endpoint and '
    'no documents exist behind them',
    (tester) async {
      await tester.pumpWidget(_harness());

      expect(find.text('Open Ticket'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Privacy Policy'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Terms of Services'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      // One Soon per disabled surface: the two legal rows. Open Ticket is
      // live now — POST /me/support-tickets exists.
      expect(find.text('Soon'), findsNWidgets(2));
    },
  );

  testWidgets('back arrow pops the route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HelpSupportScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Help & Support'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Help & Support'), findsNothing);
  });

  testWidgets('renders in dark mode', (tester) async {
    await tester.pumpWidget(_harness(brightness: Brightness.dark));
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Contact to Support'), findsOneWidget);
  });
  testWidgets('says why the answers are missing rather than showing none',
      (tester) async {
    // "Hoppin has no answers" and "we could not load them" are different
    // messages, and the rider opened this screen because something is wrong.
    await tester.pumpWidget(_harness(faqError: Exception('offline')));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not load the answers'), findsOneWidget);
  });

  testWidgets('an empty FAQ list is a sentence, not a blank card',
      (tester) async {
    await tester.pumpWidget(_harness(faqs: const []));
    await tester.pumpAndSettle();

    expect(find.text('No questions have been added yet.'), findsOneWidget);
  });

}
