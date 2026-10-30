import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../core/config/world.dart';
import '../../tiny_airways_game.dart';
import '../labels.dart';
import '../map_scene.dart';
import '../map_style.dart';
import '../projection.dart';
import '../sprites.dart';

/// City dots, the player's airport pins (sized by level, with waiting-plane
/// and upgrade badges), route picker stops, and name labels that never
/// overlap.
class CityLayer extends Component with HasGameReference<TinyAirwaysGame> {
  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  final _labels = <String, MapText>{};
  final _dimLabels = <String, MapText>{};
  final _boldLabels = <String, MapText>{};
  final _numbers = <String, MapText>{};

  Set<String> _shown = const {};
  double _shownZoom = 0;
  int _shownVersion = -1;

  @override
  void render(Canvas canvas) {
    final zoom = game.mapCamera.zoom;
    final scene = game.scene;
    final picker = scene.routePicker;
    final owned = {for (final a in scene.airports) a.cityId: a};
    final stops = picker?.stops ?? const <String>[];
    _updateLabels(zoom, scene, owned);

    // Dots shrink a little when zoomed far out so continents don't clot.
    final dotRadius = zoom < 0.5 ? 3.0 : (zoom < 1.5 ? 4.0 : 5.0);
    final pulse = (math.sin(game.seconds * 4) + 1) / 2;

    game.paintWorld(canvas, (visible) {
      final area = visible.inflate(80 / zoom);
      for (final city in game.worldData.cities) {
        final p = MapProjection.city(city);
        if (!area.contains(p)) continue;
        final airport = owned[city.id];
        final stopIndex = stops.indexOf(city.id);
        final dimmed =
            scene.lockedRegionIds.contains(city.regionId) ||
            (picker != null &&
                airport == null &&
                stopIndex < 0 &&
                city.id != picker.originCityId &&
                !picker.reachableCityIds.contains(city.id));
        game.paintAt(canvas, p, () {
          if (city.id == scene.selectedCityId) {
            _stroke
              ..color = MapStyle.amber
              ..strokeWidth = 4;
            canvas.drawCircle(
              Offset.zero,
              _pinRadius(airport) + 6 + pulse * 3,
              _stroke,
            );
          }
          if (picker != null && city.id == picker.originCityId) {
            _paintOrigin(canvas);
          } else if (stopIndex >= 0) {
            _paintStop(canvas, stopIndex + 1);
          } else if (airport != null) {
            _paintAirport(canvas, airport);
          } else if (picker != null &&
              picker.reachableCityIds.contains(city.id)) {
            _paintReachable(canvas);
          } else {
            _paintDot(canvas, dotRadius, dimmed ? 0.45 : 1);
          }
          if (_shown.contains(city.id)) {
            final text = airport != null || stopIndex >= 0
                ? _bold(city)
                : (dimmed ? _dimLabel(city) : _label(city));
            final gap = _labelGap(airport, stopIndex >= 0, dotRadius);
            text.paintTopCentre(canvas, Offset(0, gap));
          }
        });
      }
    });
  }

  void _updateLabels(
    double zoom,
    MapScene scene,
    Map<String, MapAirport> owned,
  ) {
    if (_shownVersion == game.sceneVersion &&
        (zoom / _shownZoom - 1).abs() < 0.02) {
      return;
    }
    _shownVersion = game.sceneVersion;
    _shownZoom = zoom;
    final picker = scene.routePicker;
    final dotRadius = zoom < 0.5 ? 3.0 : (zoom < 1.5 ? 4.0 : 5.0);
    // Zoomed out, only bigger cities are worth a label.
    final minSize = zoom < 0.35 ? 5 : (zoom < 0.7 ? 4 : (zoom < 1.2 ? 3 : 1));
    bool wanted(City city) =>
        city.size >= minSize ||
        owned.containsKey(city.id) ||
        city.id == scene.selectedCityId ||
        city.id == picker?.originCityId ||
        (picker?.stops.contains(city.id) ?? false) ||
        (picker?.reachableCityIds.contains(city.id) ?? false);
    _shown = placeLabels([
      for (final city in game.worldData.cities.where(wanted))
        () {
          final airport = owned[city.id];
          final isStop = picker?.stops.contains(city.id) ?? false;
          final important =
              city.id == scene.selectedCityId ||
              city.id == picker?.originCityId ||
              isStop;
          final text = airport != null || isStop ? _bold(city) : _label(city);
          return LabelCandidate(
            id: city.id,
            point: MapProjection.city(city),
            size: text.size,
            gap: _labelGap(airport, isStop, dotRadius),
            priority:
                (important ? 3e9 : 0) +
                (airport != null ? 2e9 : 0) +
                (picker?.reachableCityIds.contains(city.id) ?? false
                    ? 1e9
                    : 0) +
                (scene.lockedRegionIds.contains(city.regionId) ? 0 : 5e8) +
                city.size * 1e8 +
                city.population / 1e3,
          );
        }(),
    ], zoom);
  }

  double _pinRadius(MapAirport? airport) =>
      airport == null ? 6 : 10 + airport.level.clamp(1, 5) * 1.2;

  double _labelGap(MapAirport? airport, bool isStop, double dotRadius) {
    if (airport != null) return _pinRadius(airport) + 4;
    if (isStop) return 14;
    return dotRadius + 4;
  }

  MapText _label(City city) =>
      _labels.putIfAbsent(city.id, () => MapText(city.name));

  MapText _dimLabel(City city) => _dimLabels.putIfAbsent(
    city.id,
    () => MapText(
      city.name,
      color: MapStyle.label.withValues(alpha: 0.5),
      halo: MapStyle.halo.withValues(alpha: 0.5),
    ),
  );

  MapText _bold(City city) => _boldLabels.putIfAbsent(
    city.id,
    () => MapText(
      city.name,
      size: 12,
      weight: FontWeight.w700,
      color: MapStyle.ink,
    ),
  );

  MapText _number(String text, Color color, {double size = 13}) =>
      _numbers.putIfAbsent(
        '$text/$size/${color.toARGB32()}',
        () => MapText(
          text,
          size: size,
          weight: FontWeight.w700,
          color: color,
          halo: null,
        ),
      );

  void _paintDot(Canvas canvas, double radius, double opacity) {
    _fill.color = MapStyle.cityDot.withValues(alpha: opacity);
    _stroke
      ..color = MapStyle.cityRing.withValues(alpha: opacity)
      ..strokeWidth = radius * 0.5;
    canvas
      ..drawCircle(Offset.zero, radius, _fill)
      ..drawCircle(Offset.zero, radius, _stroke);
  }

  void _paintAirport(Canvas canvas, MapAirport airport) {
    final r = _pinRadius(airport);
    _fill.color = MapStyle.shadow;
    canvas.drawCircle(const Offset(0, 3), r, _fill);
    _fill.color = MapStyle.cityDot;
    _stroke
      ..color = MapStyle.owned
      ..strokeWidth = 4;
    canvas
      ..drawCircle(Offset.zero, r, _fill)
      ..drawCircle(Offset.zero, r, _stroke);
    _number(
      '${airport.level}',
      MapStyle.owned,
    ).paintCentred(canvas, Offset.zero);

    final badge = airport.badgeColor;
    if (badge != null) {
      _fill.color = badge;
      _stroke
        ..color = MapStyle.halo
        ..strokeWidth = 2;
      final at = Offset(r * 0.75, r * 0.75);
      canvas
        ..drawCircle(at, 5, _fill)
        ..drawCircle(at, 5, _stroke);
    }
    if (airport.waitingPlanes > 0) {
      final at = Offset(r * 0.8, -r * 0.8);
      _fill.color = MapStyle.amber;
      _stroke
        ..color = MapStyle.ink
        ..strokeWidth = 2;
      canvas
        ..drawCircle(at, 8, _fill)
        ..drawCircle(at, 8, _stroke);
      _number(
        '${airport.waitingPlanes}',
        MapStyle.ink,
        size: 10,
      ).paintCentred(canvas, at);
    }
  }

  void _paintReachable(Canvas canvas) {
    _fill.color = MapStyle.cityDot;
    _stroke
      ..color = MapStyle.owned
      ..strokeWidth = 3.5;
    canvas
      ..drawCircle(Offset.zero, 8, _fill)
      ..drawCircle(Offset.zero, 8, _stroke);
  }

  void _paintOrigin(Canvas canvas) {
    _fill.color = MapStyle.shadow;
    canvas.drawCircle(const Offset(0, 3), 13, _fill);
    _fill.color = MapStyle.owned;
    _stroke
      ..color = MapStyle.halo
      ..strokeWidth = 3;
    canvas
      ..drawCircle(Offset.zero, 13, _fill)
      ..drawCircle(Offset.zero, 13, _stroke);
  }

  void _paintStop(Canvas canvas, int number) {
    _fill.color = MapStyle.shadow;
    canvas.drawCircle(const Offset(0, 3), 11, _fill);
    _fill.color = MapStyle.cityDot;
    _stroke
      ..color = MapStyle.owned
      ..strokeWidth = 4;
    canvas
      ..drawCircle(Offset.zero, 11, _fill)
      ..drawCircle(Offset.zero, 11, _stroke);
    _number('$number', MapStyle.owned).paintCentred(canvas, Offset.zero);
  }
}
