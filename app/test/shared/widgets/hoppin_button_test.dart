import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_button.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: child),
    );

void main() {
  group('HoppinButton', () {
    testWidgets('shows its label and fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
          _wrap(HoppinButton(label: 'Login', onPressed: () => taps++)));

      expect(find.text('Login'), findsOneWidget);
      await tester.tap(find.byType(HoppinButton));
      expect(taps, 1);
    });

    testWidgets('shows a spinner and swallows taps while loading',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(HoppinButton(
          label: 'Login', isLoading: true, onPressed: () => taps++)));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      await tester.tap(find.byType(HoppinButton));
      expect(taps, 0, reason: 'a loading button must not submit twice');
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(_wrap(const HoppinButton(label: 'Login')));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_wrap(
          HoppinButton(label: 'Login', onPressed: () {}),
          brightness: Brightness.dark));
      expect(find.text('Login'), findsOneWidget);
    });
  });
}
