import 'package:flutter/material.dart';

import '../../../../core/geo.dart';
import '../../../../core/theme/colors.dart';

/// The completed journey drawn from `GET /rides/:id`'s `geo.route` — the real
/// polyline scaled into a rounded card, so the preview works on web without a
/// Maps key and never fakes a shape. A dot marks the pickup, a pin the
/// dropoff.
///
/// Callers must not build this with fewer than two points; a route that short
/// has no line to draw, and the screen omits the card instead.
class RoutePreview extends StatelessWidget {
  final List<LatLng> points;
  final double height;

  const RoutePreview({super.key, required this.points, this.height = 180});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: height,
        width: double.infinity,
        color: const Color(0xFFEAE8F2),
        child: CustomPaint(painter: _RoutePainter(points)),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<LatLng> points;

  const _RoutePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    var minLat = points.first.lat, maxLat = points.first.lat;
    var minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }

    // A straight north–south or east–west route has zero extent on one axis;
    // the epsilon keeps the division finite and centres the line instead.
    const epsilon = 1e-9;
    final latSpan = (maxLat - minLat).abs() < epsilon ? 1.0 : maxLat - minLat;
    final lngSpan = (maxLng - minLng).abs() < epsilon ? 1.0 : maxLng - minLng;

    const inset = 28.0;
    final drawW = size.width - inset * 2;
    final drawH = size.height - inset * 2;

    Offset place(LatLng p) => Offset(
          inset + (p.lng - minLng) / lngSpan * drawW,
          // Higher latitude is further north — up the canvas, so y inverts.
          inset + (1 - (p.lat - minLat) / latSpan) * drawH,
        );

    final path = Path()..moveTo(place(points.first).dx, place(points.first).dy);
    for (final p in points.skip(1)) {
      final o = place(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.primary,
    );

    // Pickup: a solid dot with a white core.
    final start = place(points.first);
    canvas.drawCircle(start, 7, Paint()..color = AppColors.primary);
    canvas.drawCircle(start, 3, Paint()..color = Colors.white);

    // Dropoff: the map-pin teardrop, orange like the frames' markers.
    final end = place(points.last);
    final pin = Paint()..color = AppColors.accent;
    canvas.drawCircle(end.translate(0, -10), 8, pin);
    final tail = Path()
      ..moveTo(end.dx - 5.5, end.dy - 6)
      ..lineTo(end.dx + 5.5, end.dy - 6)
      ..lineTo(end.dx, end.dy + 2)
      ..close();
    canvas.drawPath(tail, pin);
    canvas.drawCircle(end.translate(0, -10), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.points != points;
}
