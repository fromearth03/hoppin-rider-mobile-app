import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_text_field.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: child),
    );

void main() {
  group('HoppinTextField', () {
    testWidgets('shows its label and reports changes', (tester) async {
      String? seen;
      await tester.pumpWidget(_wrap(
          HoppinTextField(label: 'Email', onChanged: (v) => seen = v)));

      expect(find.text('Email'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'a@b.com');
      expect(seen, 'a@b.com');
    });

    testWidgets('obscures text when asked', (tester) async {
      await tester.pumpWidget(
          _wrap(const HoppinTextField(label: 'Password', obscurable: true)));
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
          isTrue);
    });

    testWidgets('shows an error message when given one', (tester) async {
      await tester.pumpWidget(_wrap(const HoppinTextField(
          label: 'Email', errorText: 'That email is already in use')));
      expect(find.text('That email is already in use'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      // A rider fills this in from a dark cab at night as often as in daylight.
      // The button had a dark-mode test from the start; this one did not.
      await tester.pumpWidget(
        _wrap(
          const HoppinTextField(label: 'Email', hint: 'example@gmail.com'),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('example@gmail.com'), findsOneWidget);
    });

    testWidgets('error text stays visible in dark mode', (tester) async {
      // The error colour is one token shared by both themes, so it is the most
      // likely thing to disappear against a dark surface.
      await tester.pumpWidget(
        _wrap(
          const HoppinTextField(label: 'Email', errorText: 'Something is wrong'),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('Something is wrong'), findsOneWidget);
    });

    group('design fidelity', () {
      testWidgets('floats the label on the border even when empty',
          (tester) async {
        // The design draws every label sitting on the field's top border, not
        // above the field and not inside it as a placeholder.
        await tester.pumpWidget(_wrap(const HoppinTextField(label: 'Email')));

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.decoration!.labelText, 'Email');
        expect(
          Theme.of(tester.element(find.byType(TextField)))
              .inputDecorationTheme
              .floatingLabelBehavior,
          FloatingLabelBehavior.always,
        );
      });

      testWidgets('puts an eye toggle inside a password field', (tester) async {
        await tester.pumpWidget(
            _wrap(const HoppinTextField(label: 'Password', obscurable: true)));

        // Inside the field's decoration, not a separate button beneath it.
        expect(
          find.descendant(
            of: find.byType(TextField),
            matching: find.byIcon(Icons.visibility_outlined),
          ),
          findsOneWidget,
        );
        expect(find.text('Show password'), findsNothing);
      });

      testWidgets('the eye toggle reveals and re-hides the password',
          (tester) async {
        await tester.pumpWidget(
            _wrap(const HoppinTextField(label: 'Password', obscurable: true)));

        TextField field() => tester.widget<TextField>(find.byType(TextField));
        expect(field().obscureText, isTrue);

        await tester.tap(find.byIcon(Icons.visibility_outlined));
        await tester.pump();
        expect(field().obscureText, isFalse);

        await tester.tap(find.byIcon(Icons.visibility_off_outlined));
        await tester.pump();
        expect(field().obscureText, isTrue);
      });

      testWidgets('a non-password field has no eye toggle', (tester) async {
        await tester.pumpWidget(_wrap(const HoppinTextField(label: 'Email')));
        expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      });
    });
  });
}
