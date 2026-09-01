import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

/// Canvas-drawn circular pins with a label inside ("A", "1", "2", "B") for
/// the Google engine — the stock marker cannot carry visible text, and the
/// rider must be able to tell Stop 1 from Stop 2 at a glance. Drawn once per
/// (label, colour) and cached for the session.
final _markerCache = <String, gmaps.BitmapDescriptor>{};

Future<gmaps.BitmapDescriptor> circleLabelMarker(
    String label, Color color) async {
  final key = '$label-${color.toARGB32()}';
  final hit = _markerCache[key];
  if (hit != null) return hit;

  const size = 84.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(const Offset(size / 2, size / 2), size / 2,
      Paint()..color = Colors.white);
  canvas.drawCircle(
      const Offset(size / 2, size / 2), size / 2 - 5, Paint()..color = color);
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 36,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(
      canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final descriptor = gmaps.BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    imagePixelRatio: 2.4,
  );
  _markerCache[key] = descriptor;
  return descriptor;
}
