import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real Poppins faces before any test runs.
///
/// Without this every golden render falls back to the block glyph font
/// (Ahem), which makes the `test/golden/shots/` renders useless for the
/// side-by-side fidelity pass against `docs` Figma frames — spacing reads
/// differently and type is unreviewable.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final loader = FontLoader('Poppins')
    ..addFont(rootBundle.load('assets/fonts/Poppins-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Poppins-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Poppins-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Poppins-Bold.ttf'));
  await loader.load();

  await testMain();
}
