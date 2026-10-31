import 'dart:math' as math;
import 'dart:ui';

import '../../core/config/world.dart';

/// Turns latitude and longitude into flat map ("world") units.
///
/// Uses the Miller cylindrical projection: it looks like the familiar
/// Mercator map at city latitudes but stays finite at the poles, so the South
/// Pole station (latitude -90) has a real position. The map is
/// [worldWidth] units wide, x grows east from the antimeridian and y grows
/// south from [northLat]. It wraps east to west, so x is only meaningful
/// modulo [worldWidth].
abstract final class MapProjection {
  static const worldWidth = 2048.0;

  /// The top and bottom of the map. Land north of [northLat] is cut off;
  /// [southLat] leaves a strip of the Antarctic interior below the pole
  /// station.
  static const northLat = 84.0;
  static const southLat = -90.0;

  /// Cities are drawn no further south than this, so the pole station sits
  /// on the map rather than on its bottom edge.
  static const southmostCityLat = -85.0;

  static const _unitsPerRadian = worldWidth / (2 * math.pi);
  static final double _top = _miller(northLat);
  static final double worldHeight = yOf(southLat);

  static double _miller(double lat) {
    final phi = lat.clamp(-90.0, 90.0) * math.pi / 180;
    return 1.25 * math.log(math.tan(math.pi / 4 + 0.4 * phi));
  }

  static double xOf(double lon) => (lon + 180) / 360 * worldWidth;

  static double yOf(double lat) => (_top - _miller(lat)) * _unitsPerRadian;

  static Offset project(double lat, double lon) => Offset(xOf(lon), yOf(lat));

  /// Where [city]'s pin goes.
  static Offset city(City city) =>
      project(math.max(city.lat, southmostCityLat), city.lon);

  static double lonOf(double x) => x / worldWidth * 360 - 180;

  static double latOf(double y) {
    final m = _top - y / _unitsPerRadian;
    return (2.5 * math.atan(math.exp(0.8 * m)) - 0.625 * math.pi) *
        180 /
        math.pi;
  }

  /// [x] moved into 0 to [worldWidth].
  static double wrapX(double x) {
    final w = x % worldWidth;
    return w < 0 ? w + worldWidth : w;
  }

  /// The copy of [x] (shifted by whole map widths) closest to [nearX].
  static double nearestX(double x, double nearX) =>
      x + worldWidth * ((nearX - x) / worldWidth).roundToDouble();

  /// [point] shifted by whole map widths to sit closest to [near].
  static Offset nearest(Offset point, Offset near) =>
      Offset(nearestX(point.dx, near.dx), point.dy);
}
