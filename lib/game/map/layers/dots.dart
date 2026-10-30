import 'dart:ui';

/// Draws round dots every [spacing] along the polyline [points], as the
/// mockups do for flight trails and range rings. [spacing] and [radius] are
/// in the canvas's units.
void drawDots(
  Canvas canvas,
  List<Offset> points, {
  required double spacing,
  required double radius,
  required Paint paint,
  bool closed = false,
}) {
  if (points.length < 2) return;
  final dots = <Offset>[];
  var carry = 0.0;
  final count = closed ? points.length : points.length - 1;
  for (var i = 0; i < count; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    final segment = b - a;
    final length = segment.distance;
    if (length == 0) continue;
    var at = carry;
    while (at <= length) {
      dots.add(a + segment * (at / length));
      at += spacing;
    }
    carry = at - length;
  }
  final dot = Paint()
    ..color = paint.color
    ..strokeWidth = radius * 2
    ..strokeCap = StrokeCap.round;
  canvas.drawPoints(PointMode.points, dots, dot);
}
