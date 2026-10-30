import 'dart:convert';
import 'dart:ui';

import 'projection.dart';

/// A path in map units with its bounds, so layers can skip what is off
/// screen.
class MapShape {
  MapShape(this.path) : bounds = path.getBounds();

  final Path path;
  final Rect bounds;
}

/// The land at one level of detail.
class LandDetail {
  LandDetail({
    required this.regions,
    required this.coast,
    required this.borders,
    required this.lakes,
  }) : regionPaths = regions.map((id, shapes) => MapEntry(id, _merge(shapes))),
       coastPath = _merge(coast),
       borderPath = _merge(borders),
       lakePath = _merge(lakes);

  /// Filled land, one list of polygons per region id.
  final Map<String, List<MapShape>> regions;

  /// Coastlines (open or closed lines).
  final List<MapShape> coast;

  /// Lines where two regions meet on land, such as the Urals.
  final List<MapShape> borders;

  /// Large lakes, drawn as water over the land.
  final List<MapShape> lakes;

  /// The same shapes merged into one path each, for drawing the whole world
  /// in a handful of calls when zoomed out.
  final Map<String, Path> regionPaths;
  final Path coastPath;
  final Path borderPath;
  final Path lakePath;

  static Path _merge(List<MapShape> shapes) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final s in shapes) {
      path.addPath(s.path, Offset.zero);
    }
    return path;
  }
}

/// The world's land, from `assets/map/world.json` (built by
/// `tool/build_map.py` from Natural Earth).
class WorldGeometry {
  WorldGeometry({required this.detail, required this.coarse});

  factory WorldGeometry.parse(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    final scale = (json['scale'] as num).toDouble();
    final lods = json['lods'] as Map<String, dynamic>;
    LandDetail lod(String name) =>
        _parseLod(lods[name] as Map<String, dynamic>, scale);
    return WorldGeometry(detail: lod('detail'), coarse: lod('coarse'));
  }

  /// For zoomed-in views; finer coastlines, more islands.
  final LandDetail detail;

  /// For zoomed-out views; about a fifth of the points.
  final LandDetail coarse;

  /// True if [point] (map units) is on land.
  bool isLand(Offset point) {
    final x = MapProjection.wrapX(point.dx);
    final p = Offset(x, point.dy);
    for (final shapes in coarse.regions.values) {
      for (final s in shapes) {
        if (s.bounds.contains(p) && s.path.contains(p)) return true;
      }
    }
    return false;
  }

  static LandDetail _parseLod(Map<String, dynamic> json, double scale) {
    final regions = (json['regions'] as Map<String, dynamic>).map(
      (id, polys) => MapEntry(id, [
        for (final poly in polys as List<dynamic>)
          MapShape(_polygon(poly as List<dynamic>, scale)),
      ]),
    );
    List<MapShape> lines(String key) => [
      for (final line in json[key] as List<dynamic>)
        MapShape(_line(line as List<dynamic>, scale, close: false)),
    ];
    return LandDetail(
      regions: regions,
      coast: lines('coast'),
      borders: lines('borders'),
      lakes: [
        for (final poly in json['lakes'] as List<dynamic>)
          MapShape(_polygon(poly as List<dynamic>, scale)),
      ],
    );
  }

  static Path _polygon(List<dynamic> rings, double scale) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in rings) {
      path.addPath(
        _line(ring as List<dynamic>, scale, close: true),
        Offset.zero,
      );
    }
    return path;
  }

  static Path _line(List<dynamic> flat, double scale, {required bool close}) {
    final path = Path();
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final lon = (flat[i] as num) / scale;
      final lat = (flat[i + 1] as num) / scale;
      // Land cut at the date line is nudged half a unit past the edge, so
      // neighbouring copies of the map overlap instead of showing a seam.
      final x = lon.abs() >= 180
          ? MapProjection.xOf(lon) + lon.sign * 0.5
          : MapProjection.xOf(lon);
      final y = MapProjection.yOf(lat);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (close) path.close();
    return path;
  }
}
