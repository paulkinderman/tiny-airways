import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../ui/theme.dart';

/// The Flame game that will draw the world map (package 4). For now it shows
/// a sky with one little plane circling, which proves the engine runs.
class TinyAirwaysGame extends FlameGame {
  @override
  Color backgroundColor() => TinyColors.sky;

  @override
  Future<void> onLoad() async {
    add(CirclingPlane());
  }
}

class CirclingPlane extends PositionComponent with HasGameReference {
  CirclingPlane() : super(size: Vector2.all(36), anchor: Anchor.center);

  static const _radius = 90.0;
  static const _radiansPerSecond = 0.6;
  double _angle = 0;

  final _body = Paint()..color = TinyColors.panel;
  final _trim = Paint()..color = TinyColors.accent;

  @override
  void update(double dt) {
    _angle += _radiansPerSecond * dt;
    final centre = game.size / 2;
    position = centre + Vector2(math.cos(_angle), math.sin(_angle)) * _radius;
    // Face along the direction of travel (the tangent of the circle).
    angle = _angle + math.pi;
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    // Top-down plane pointing up (nose at the top).
    final fuselage = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w / 2, h / 2), width: w * 0.2, height: h),
      Radius.circular(w * 0.1),
    );
    final wings = Rect.fromCenter(
      center: Offset(w / 2, h * 0.45),
      width: w,
      height: h * 0.18,
    );
    final tail = Rect.fromCenter(
      center: Offset(w / 2, h * 0.9),
      width: w * 0.45,
      height: h * 0.12,
    );
    canvas
      ..drawRRect(fuselage, _body)
      ..drawRect(wings, _trim)
      ..drawRect(tail, _trim);
  }
}
