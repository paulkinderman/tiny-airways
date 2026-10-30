import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'map_style.dart';

/// Hand-drawn shapes for the map. Each draws in screen pixels centred on
/// the canvas origin; callers translate and scale first.
abstract final class Sprites {
  static final _fill = Paint();
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  static final Path _fuselage = Path()
    ..moveTo(0.5, 0)
    ..cubicTo(0.5, 0.07, 0.38, 0.09, 0.3, 0.09)
    ..lineTo(-0.38, 0.07)
    ..lineTo(-0.5, 0.03)
    ..lineTo(-0.5, -0.03)
    ..lineTo(-0.38, -0.07)
    ..lineTo(0.3, -0.09)
    ..cubicTo(0.38, -0.09, 0.5, -0.07, 0.5, 0)
    ..close();

  static final Path _wings = Path()
    ..moveTo(0.12, 0.06)
    ..lineTo(-0.12, 0.48)
    ..lineTo(-0.22, 0.48)
    ..lineTo(-0.08, 0.06)
    ..close()
    ..moveTo(0.12, -0.06)
    ..lineTo(-0.12, -0.48)
    ..lineTo(-0.22, -0.48)
    ..lineTo(-0.08, -0.06)
    ..close()
    ..moveTo(-0.32, 0.05)
    ..lineTo(-0.46, 0.2)
    ..lineTo(-0.5, 0.2)
    ..lineTo(-0.44, 0.04)
    ..close()
    ..moveTo(-0.32, -0.05)
    ..lineTo(-0.46, -0.2)
    ..lineTo(-0.5, -0.2)
    ..lineTo(-0.44, -0.04)
    ..close();

  /// A top-down plane [size] pixels long, nose pointing along [heading]
  /// (radians clockwise from east).
  static void plane(
    Canvas canvas, {
    required double size,
    required double heading,
    Color wing = MapStyle.planeWing,
    double opacity = 1,
  }) {
    canvas
      ..save()
      ..rotate(heading)
      ..scale(size);
    // Shadow on the ground below and behind.
    canvas
      ..save()
      ..translate(-0.06, 0.12);
    _fill.color = MapStyle.shadow.withValues(alpha: 0.18 * opacity);
    canvas
      ..drawPath(_wings, _fill)
      ..drawPath(_fuselage, _fill)
      ..restore();
    _stroke
      ..color = MapStyle.ink.withValues(alpha: opacity)
      ..strokeWidth = 0.07;
    _fill.color = wing.withValues(alpha: opacity);
    canvas
      ..drawPath(_wings, _stroke)
      ..drawPath(_wings, _fill);
    _fill.color = MapStyle.planeBody.withValues(alpha: opacity);
    canvas
      ..drawPath(_fuselage, _stroke)
      ..drawPath(_fuselage, _fill);
    // Cockpit window.
    _fill.color = MapStyle.ink.withValues(alpha: 0.8 * opacity);
    canvas
      ..drawCircle(const Offset(0.34, 0), 0.045, _fill)
      ..restore();
  }

  /// A puffy cartoon cloud [width] pixels wide.
  static void cloud(
    Canvas canvas, {
    required double width,
    Color color = const Color(0xFFFFFFFF),
    Color? outline,
  }) {
    final u = width / 46;
    final puffs = [
      (Offset(-12 * u, 2 * u), 9 * u),
      (Offset(-1 * u, -4 * u), 12 * u),
      (Offset(12 * u, 2 * u), 9 * u),
    ];
    final base = RRect.fromRectAndRadius(
      Rect.fromLTRB(-21 * u, 0, 21 * u, 11 * u),
      Radius.circular(5.5 * u),
    );
    if (outline != null) {
      _stroke
        ..color = outline
        ..strokeWidth = 2.5;
      for (final (c, r) in puffs) {
        canvas.drawCircle(c, r, _stroke);
      }
      canvas.drawRRect(base, _stroke);
    }
    _fill.color = color;
    for (final (c, r) in puffs) {
      canvas.drawCircle(c, r, _fill);
    }
    canvas.drawRRect(base, _fill);
  }

  /// A lightning bolt [height] pixels tall.
  static void bolt(Canvas canvas, double height) {
    final u = height / 20;
    final path = Path()
      ..moveTo(2 * u, -10 * u)
      ..lineTo(-5 * u, 1 * u)
      ..lineTo(0, 1 * u)
      ..lineTo(-2 * u, 10 * u)
      ..lineTo(5 * u, -2 * u)
      ..lineTo(0, -2 * u)
      ..close();
    _fill.color = MapStyle.amber;
    _stroke
      ..color = MapStyle.ink
      ..strokeWidth = 1.5;
    canvas
      ..drawPath(path, _stroke)
      ..drawPath(path, _fill);
  }

  /// A cartoon sun [radius] pixels across its disc.
  static void sun(Canvas canvas, double radius) {
    _stroke
      ..color = const Color(0xFFFF8A3D)
      ..strokeWidth = radius * 0.28;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(d * radius * 1.35, d * radius * 1.85, _stroke);
    }
    _fill.color = MapStyle.amber;
    canvas.drawCircle(Offset.zero, radius, _fill);
  }

  /// A six-armed snowflake [radius] pixels from centre to tip.
  static void snowflake(Canvas canvas, double radius, Color color) {
    _stroke
      ..color = color
      ..strokeWidth = radius * 0.22;
    for (var i = 0; i < 3; i++) {
      final a = i * math.pi / 3 + math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawLine(-d, d, _stroke);
    }
  }

  /// Horizontal fog streaks [width] pixels wide.
  static void fogLines(Canvas canvas, double width, Color color) {
    _stroke
      ..color = color
      ..strokeWidth = width * 0.09;
    for (var i = -1; i <= 1; i++) {
      final y = i * width * 0.2;
      final inset = i == 0 ? 0.0 : width * 0.12;
      canvas.drawLine(
        Offset(-width / 2 + inset + i * 3, y),
        Offset(width / 2 - inset + i * 3, y),
        _stroke,
      );
    }
  }

  /// A small wave squiggle in the sea.
  static void wave(Canvas canvas, double width, Color color) {
    final u = width / 24;
    final path = Path()
      ..moveTo(-12 * u, 0)
      ..quadraticBezierTo(-9 * u, -6 * u, -6 * u, 0)
      ..quadraticBezierTo(-3 * u, 6 * u, 0, 0)
      ..quadraticBezierTo(3 * u, -6 * u, 6 * u, 0)
      ..quadraticBezierTo(9 * u, 6 * u, 12 * u, 0);
    _stroke
      ..color = color
      ..strokeWidth = 2.5;
    canvas.drawPath(path, _stroke);
  }
}

/// Text drawn on the map, laid out once and reused every frame.
class MapText {
  MapText(
    String text, {
    double size = 11,
    FontWeight weight = FontWeight.w600,
    Color color = MapStyle.label,
    Color? halo = MapStyle.halo,
  }) : _fill = _layout(text, size, weight, Paint()..color = color),
       _halo = halo == null
           ? null
           : _layout(
               text,
               size,
               weight,
               Paint()
                 ..color = halo
                 ..style = PaintingStyle.stroke
                 ..strokeWidth = 4
                 ..strokeJoin = StrokeJoin.round,
             );

  final TextPainter _fill;
  final TextPainter? _halo;

  Size get size => _fill.size;

  static TextPainter _layout(String text, double size, FontWeight w, Paint p) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, fontWeight: w, foreground: p),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  /// Paints with the text's top-centre at [topCentre].
  void paintTopCentre(Canvas canvas, Offset topCentre) {
    final at = topCentre - Offset(size.width / 2, 0);
    _halo?.paint(canvas, at);
    _fill.paint(canvas, at);
  }

  /// Paints centred on [centre].
  void paintCentred(Canvas canvas, Offset centre) =>
      paintTopCentre(canvas, centre - Offset(0, size.height / 2));
}

/// A dark rounded pill with white text, for countdowns.
class MapPill {
  MapPill(this.text, {Color background = MapStyle.ink})
    : _text = MapText(
        text,
        size: 11,
        weight: FontWeight.w700,
        color: const Color(0xFFFFFFFF),
        halo: null,
      ),
      _paint = Paint()..color = background;

  final String text;
  final MapText _text;
  final Paint _paint;

  Size get size => Size(_text.size.width + 16, _text.size.height + 6);

  void paintCentred(Canvas canvas, Offset centre) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: size.width, height: size.height),
        Radius.circular(size.height / 2),
      ),
      _paint,
    );
    _text.paintCentred(canvas, centre);
  }
}
