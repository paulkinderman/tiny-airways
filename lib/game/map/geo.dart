import 'dart:math' as math;
import 'dart:ui';

import '../../core/config/world.dart';
import 'projection.dart';

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// The point [km] from ([lat], [lon]) heading [bearingDeg] (0 is north)
/// along a great circle.
({double lat, double lon}) destinationPoint(
  double lat,
  double lon,
  double bearingDeg,
  double km,
) {
  final d = km / WorldData.earthRadiusKm;
  final phi1 = _rad(lat);
  final theta = _rad(bearingDeg);
  final phi2 = math.asin(
    math.sin(phi1) * math.cos(d) +
        math.cos(phi1) * math.sin(d) * math.cos(theta),
  );
  final lambda2 =
      _rad(lon) +
      math.atan2(
        math.sin(theta) * math.sin(d) * math.cos(phi1),
        math.cos(d) - math.sin(phi1) * math.sin(phi2),
      );
  final lon2 = (_deg(lambda2) + 540) % 360 - 180;
  return (lat: _deg(phi2), lon: lon2);
}

/// Every point [km] from ([lat], [lon]), as a closed outline in map units:
/// a plane's range or a weather cluster.
///
/// Points are unwrapped so each sits next to the one before, which keeps the
/// outline in one piece across the date line. An outline that goes round a
/// pole is closed along the top or bottom edge of the map, so filling it
/// covers the polar cap too.
List<Offset> geodesicRing(double lat, double lon, double km, {int steps = 96}) {
  final centreX = MapProjection.xOf(lon);
  final points = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final p = destinationPoint(lat, lon, 360 * i / steps, km);
    var point = MapProjection.project(p.lat, p.lon);
    final near = points.isEmpty ? centreX : points.last.dx;
    point = Offset(MapProjection.nearestX(point.dx, near), point.dy);
    points.add(point);
  }
  final drift = points.last.dx - points.first.dx;
  if (drift.abs() > MapProjection.worldWidth / 2) {
    final northPole = lat + km / 111.2 > 90;
    final edge = northPole ? 0.0 : MapProjection.worldHeight;
    points
      ..add(Offset(points.last.dx, edge))
      ..add(Offset(points.first.dx, edge));
  } else {
    points.removeLast();
  }
  return points;
}
