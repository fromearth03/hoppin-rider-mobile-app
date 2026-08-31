@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the brand pin — the mark from the supplied vector, without the
/// wordmark — at 512px on a transparent ground. The output is cropped and
/// scaled into `web/favicon.png` and the PWA icons, so the browser tab shows
/// the pin instead of the stock Flutter logo.
const _pin = '''
<svg width="40" height="43" viewBox="0 0 40 43" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M30.3151 23.0032C32.811 18.2687 30.5949 12.0791 26.2253 9.04671C21.3784 5.68416 15.0101 6.23684 10.8253 10.1032C6.67053 13.9426 5.69367 20.6457 9.29882 25.3655L18.8476 35.1206L21.4034 33.2694L21.6308 43L11.7247 42.3446C12.2844 41.4226 12.9289 41.0191 14.0032 40.2341L5.07907 31.3472C-2.58592 23.7124 -1.25929 11.1792 6.93286 4.34647C14.9176 -2.31507 27.442 -1.22437 34.0726 6.9656C40.6858 15.136 39.4192 26.9722 30.8572 33.5873L18.1031 20.8829C17.2236 21.3182 16.7989 22.1057 15.3649 23.0276L15.1475 13.2725C18.6277 13.2554 21.4109 13.3532 25.1035 13.9279L22.9749 16.1827L30.3201 23.0056L30.3151 23.0032Z" fill="#E23136"/>
</svg>
''';

void main() {
  testWidgets('brand pin at 512', (tester) async {
    tester.view.physicalSize = const Size(512, 512);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          child: SizedBox(
            width: 512,
            height: 512,
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: SvgPicture.string(_pin, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('shots/brand_pin_512.png'),
    );
  });
}
