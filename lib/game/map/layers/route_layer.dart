import 'dart:ui';

import 'package:flame/components.dart';

import '../../tiny_airways_game.dart';
import '../map_scene.dart';
import '../map_style.dart';
import 'dots.dart';

/// Dotted trails ahead of the player's planes, and the route picker's range
/// ring and chosen legs.
class RouteLayer extends Component with HasGameReference<TinyAirwaysGame> {
  final _trail = Paint()..color = MapStyle.ink.withValues(alpha: 0.75);
  final _laterTrail = Paint()..color = MapStyle.ink.withValues(alpha: 0.4);
  final _rangeFill = Paint()..color = MapStyle.rangeFill;
  final _rangeEdge = Paint()..color = MapStyle.owned;
  final _legUnder = Paint()
    ..color = MapStyle.halo
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final _leg = Paint()
    ..color = MapStyle.owned
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas) {
    final zoom = game.mapCamera.zoom;
    final scene = game.scene;
    final picker = scene.routePicker;

    game.paintWorld(canvas, (visible) {
      if (picker != null) _paintPicker(canvas, picker, zoom);
      for (final f in scene.flights) {
        if (f.isRival) continue;
        final at = game.flightPosition(f);
        final ahead = game
            .curve(f.fromCityId, f.toCityId)
            .pointsFrom(at.progress);
        drawDots(
          canvas,
          ahead,
          spacing: 8 / zoom,
          radius: 1.4 / zoom,
          paint: _trail,
        );
        var from = f.toCityId;
        var anchor = ahead.last;
        for (final stop in f.laterStops) {
          final c = game.curve(from, stop);
          // Keep the later legs on the same copy of the map as the first.
          final shift = anchor - c.start;
          drawDots(
            canvas,
            [for (final p in c.pointsFrom(0)) p + shift],
            spacing: 8 / zoom,
            radius: 1.2 / zoom,
            paint: _laterTrail,
          );
          from = stop;
          anchor = c.end + shift;
        }
      }
    });
  }

  void _paintPicker(Canvas canvas, MapRoutePicker picker, double zoom) {
    final centre = game.worldData.city(picker.rangeCentreCityId);
    final ring = game.ring(centre.lat, centre.lon, picker.rangeKm);
    canvas.drawPath(Path()..addPolygon(ring, true), _rangeFill);
    drawDots(
      canvas,
      ring,
      spacing: 10 / zoom,
      radius: 1.6 / zoom,
      paint: _rangeEdge,
      closed: true,
    );

    _legUnder.strokeWidth = 7 / zoom;
    _leg.strokeWidth = 4 / zoom;
    var from = picker.originCityId;
    var shift = Offset.zero;
    for (final stop in picker.stops) {
      final c = game.curve(from, stop);
      final path = Path()
        ..addPolygon([for (final p in c.pointsFrom(0)) p + shift], false);
      canvas
        ..drawPath(path, _legUnder)
        ..drawPath(path, _leg);
      shift += c.end - game.cityPoint(stop);
      from = stop;
    }
  }
}
