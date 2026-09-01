import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoppin_rider/core/theme/app_theme.dart';
import 'package:hoppin_rider/shared/widgets/hoppin_logo.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
    );

/// The wordmark is outlined paths, not text, so nothing here can assert on a
/// string — these check which asset is chosen and that it is laid out at the
/// brand's aspect ratio.
void main() {
  group('HoppinLogo', () {
    String assetOf(WidgetTester tester) {
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      return (picture.bytesLoader as SvgAssetLoader).assetName;
    }

    testWidgets('renders the supplied brand vector', (tester) async {
      await tester.pumpWidget(_wrap(const HoppinLogo()));
      expect(assetOf(tester), 'assets/brand/hoppin_go.svg');
    });

    testWidgets('uses the light-wordmark variant in dark mode',
        (tester) async {
      // The wordmark is near-black in the supplied vector and would vanish
      // against a dark surface. The mark's red must not change with it, which
      // is why this is a second file rather than a colour filter.
      await tester.pumpWidget(
          _wrap(const HoppinLogo(), brightness: Brightness.dark));
      expect(assetOf(tester), 'assets/brand/hoppin_go_dark.svg');
    });

    testWidgets('keeps the brand aspect ratio at any height', (tester) async {
      await tester.pumpWidget(_wrap(const HoppinLogo(height: 64)));

      final size = tester.getSize(find.byType(SvgPicture));
      expect(size.height, 64);
      expect(size.width, closeTo(64 * 166 / 37.1, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('is announced to screen readers', (tester) async {
      await tester.pumpWidget(_wrap(const HoppinLogo()));
      expect(find.bySemanticsLabel("Hoppin' Go"), findsOneWidget);
    });
  });
}
