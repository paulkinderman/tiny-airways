import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';

import '../core/clock/clock.dart';
import '../core/config/world.dart';
import 'map/flight_curve.dart';
import 'map/geo.dart';
import 'map/layers/city_layer.dart';
import 'map/layers/decor_layer.dart';
import 'map/layers/land_layer.dart';
import 'map/layers/plane_layer.dart';
import 'map/layers/route_layer.dart';
import 'map/layers/weather_layer.dart';
import 'map/map_camera.dart';
import 'map/map_scene.dart';
import 'map/map_style.dart';
import 'map/projection.dart';
import 'map/world_geometry.dart';

/// The Flame game that draws the world map: land, cities and airports,
/// planes in flight, the route picker and weather.
///
/// It only draws. Screens hand it a [MapScene] built from the game state and
/// hear about taps through [onTap]; the map never changes game state.
class TinyAirwaysGame extends FlameGame {
  TinyAirwaysGame({
    required this.worldData,
    required this.geometry,
    required this.clock,
    MapScene scene = const MapScene(),
  }) : _now = clock.now() {
    this.scene = scene;
  }

  /// Cities and regions.
  final WorldData worldData;
  final WorldGeometry geometry;
  final Clock clock;
  final mapCamera = MapCamera();

  /// Called when the player taps the map, with what was under their finger
  /// (null for open land or sea).
  void Function(MapHit? hit)? onTap;

  MapScene _scene = const MapScene();
  int _sceneVersion = 0;
  DateTime _now;
  double _seconds = 0;
  void Function()? _pendingView;
  final _curves = <String, FlightCurve>{};
  final _rings = <String, List<Offset>>{};

  MapScene get scene => _scene;
  set scene(MapScene value) {
    _scene = value;
    _sceneVersion++;
  }

  /// Bumped whenever [scene] changes, so layers can rebuild caches.
  int get sceneVersion => _sceneVersion;

  /// The time this frame is drawn at, read from the [Clock] once a frame.
  DateTime get now => _now;

  /// Seconds since the map started, for idle animations.
  double get seconds => _seconds;

  @override
  Color backgroundColor() => MapStyle.sea;

  @override
  Future<void> onLoad() async {
    await addAll([
      LandLayer(),
      DecorLayer(),
      WeatherLayer(icons: false),
      RouteLayer(),
      CityLayer(),
      PlaneLayer(),
      WeatherLayer(icons: true),
    ]);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final first = mapCamera.viewport.isEmpty;
    mapCamera.resize(Size(size.x, size.y));
    if (first && !mapCamera.viewport.isEmpty) {
      (_pendingView ?? _defaultView)();
      _pendingView = null;
    }
  }

  @override
  void update(double dt) {
    _now = clock.now();
    _seconds += dt;
    mapCamera.update(dt);
    super.update(dt);
  }

  // Camera moves -------------------------------------------------------------

  void _whenSized(void Function() move) {
    if (mapCamera.viewport.isEmpty) {
      _pendingView = move;
    } else {
      move();
    }
  }

  void _defaultView() {
    final owned = [for (final a in _scene.airports) cityPoint(a.cityId)];
    if (owned.isNotEmpty) {
      _fit(owned, animate: false);
    } else {
      mapCamera.jumpTo(
        MapProjection.project(30, -20),
        zoom: mapCamera.minZoom * 2.2,
      );
    }
  }

  void _fit(List<Offset> points, {required bool animate}) {
    final anchor = points.first;
    final unwrapped = [
      for (final p in points) MapProjection.nearest(p, anchor),
    ];
    var bounds = Rect.fromPoints(unwrapped.first, unwrapped.first);
    for (final p in unwrapped) {
      bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
    }
    // A lone airport gets a view about 2,500 km across.
    final zoom = math.min(mapCamera.zoomToFit(bounds), 3.0);
    if (animate) {
      mapCamera.flyTo(bounds.center, zoom: zoom);
    } else {
      mapCamera.jumpTo(bounds.center, zoom: zoom);
    }
  }

  /// Glides to [cityId], zooming in to at least [zoom].
  void showCity(String cityId, {double zoom = 3, bool animate = true}) =>
      _whenSized(() {
        final z = math.max(mapCamera.zoom, zoom);
        if (animate) {
          mapCamera.flyTo(cityPoint(cityId), zoom: z);
        } else {
          mapCamera.jumpTo(cityPoint(cityId), zoom: z);
        }
      });

  /// Glides to where plane [planeId] is now.
  void showPlane(String planeId, {double zoom = 3}) => _whenSized(() {
    final at = planePosition(planeId);
    if (at != null) {
      mapCamera.flyTo(at.point, zoom: math.max(mapCamera.zoom, zoom));
    }
  });

  /// Fits every city in [regionId] on screen.
  void showRegion(String regionId, {bool animate = true}) => _whenSized(() {
    final cities = worldData.citiesIn(regionId);
    if (cities.isEmpty) return;
    _fit([for (final c in cities) MapProjection.city(c)], animate: animate);
  });

  /// Fits all the player's airports on screen.
  void showNetwork({bool animate = true}) => _whenSized(() {
    final owned = [for (final a in _scene.airports) cityPoint(a.cityId)];
    if (owned.isNotEmpty) _fit(owned, animate: animate);
  });

  void zoomIn() => _zoomStep(2);
  void zoomOut() => _zoomStep(0.5);

  void _zoomStep(double factor) => mapCamera.flyTo(
    mapCamera.centre,
    zoom: mapCamera.zoom * factor,
    duration: const Duration(milliseconds: 300),
    keepCentre: true,
  );

  // Geometry helpers for the layers ------------------------------------------

  Offset cityPoint(String cityId) => MapProjection.city(worldData.city(cityId));

  /// The arc for a leg, cached.
  FlightCurve curve(String fromCityId, String toCityId) => _curves.putIfAbsent(
    '$fromCityId>$toCityId',
    () => FlightCurve(cityPoint(fromCityId), cityPoint(toCityId)),
  );

  /// A great-circle ring, cached.
  List<Offset> ring(double lat, double lon, double km) =>
      _rings.putIfAbsent('$lat,$lon,$km', () => geodesicRing(lat, lon, km));

  /// Where a flight's plane is at [now] and which way it faces.
  ({Offset point, double heading, double progress}) flightPosition(
    MapFlight f,
  ) {
    final c = curve(f.fromCityId, f.toCityId);
    final progress = flightProgress(f.departAt, f.arriveAt, _now);
    return (
      point: c.pointAt(progress),
      heading: c.headingAt(progress),
      progress: progress,
    );
  }

  ({Offset point, double heading, double progress})? planePosition(
    String planeId,
  ) {
    for (final f in _scene.flights) {
      if (f.planeId == planeId) return flightPosition(f);
    }
    return null;
  }

  /// Where a weather event's icon sits, in map units.
  Offset weatherAnchor(MapWeather w) => switch (w.area) {
    WeatherAtCity(:final cityId) => cityPoint(cityId),
    WeatherCluster(:final lat, :final lon) => MapProjection.project(lat, lon),
    WeatherBand(:final lat) => Offset(
      mapCamera.centre.dx,
      MapProjection.yOf(lat),
    ),
  };

  /// Applies the camera to [canvas] and calls [draw] once for each copy of
  /// the world that is on screen (the map wraps east to west). [draw] gets
  /// the visible area in that copy's map units.
  void paintWorld(Canvas canvas, void Function(Rect visible) draw) {
    final cam = mapCamera;
    final visible = cam.visibleRect;
    const w = MapProjection.worldWidth;
    canvas
      ..save()
      ..translate(cam.viewport.width / 2, cam.viewport.height / 2)
      ..scale(cam.zoom)
      ..translate(-cam.centre.dx, -cam.centre.dy);
    final first = (visible.left / w).floor() - 1;
    final last = (visible.right / w).floor() + 1;
    for (var k = first; k <= last; k++) {
      final shift = k * w;
      final local = visible.shift(Offset(-shift, 0));
      // Skip copies that cannot hold anything visible, allowing for shapes
      // that reach half a world past the edges (unwrapped flight arcs).
      if (local.right < -w / 2 || local.left > w * 1.5) continue;
      canvas
        ..save()
        ..translate(shift, 0);
      draw(local);
      canvas.restore();
    }
    canvas.restore();
  }

  /// Runs [draw] with the canvas at [point] (map units) and scaled back to
  /// screen pixels, for things that keep their size as the map zooms.
  void paintAt(Canvas canvas, Offset point, void Function() draw) {
    final s = 1 / mapCamera.zoom;
    canvas
      ..save()
      ..translate(point.dx, point.dy)
      ..scale(s);
    draw();
    canvas.restore();
  }

  // Taps --------------------------------------------------------------------

  /// What is under [screenPoint]: a plane first, then an airport or city,
  /// then a weather icon. Null for open land or sea.
  MapHit? hitTest(Offset screenPoint) {
    final world = mapCamera.screenToWorld(screenPoint);
    final zoom = mapCamera.zoom;
    double distance(Offset p) =>
        (MapProjection.nearest(p, world) - world).distance * zoom;

    String? best;
    var bestDistance = double.infinity;
    for (final f in _scene.flights) {
      if (f.isRival) continue;
      final d = distance(flightPosition(f).point);
      if (d < 26 && d < bestDistance) {
        best = f.planeId;
        bestDistance = d;
      }
    }
    if (best != null) return PlaneHit(best);

    bestDistance = double.infinity;
    for (final c in worldData.cities) {
      final d = distance(MapProjection.city(c));
      if (d < 22 && d < bestDistance) {
        best = c.id;
        bestDistance = d;
      }
    }
    if (best != null) return CityHit(best);

    for (final w in _scene.weather) {
      if (w.isOverAt(_now)) continue;
      final anchor = weatherAnchor(w);
      final offset = w.area is WeatherAtCity
          ? const Offset(0, -34)
          : Offset.zero;
      final icon = mapCamera.worldToScreen(
        MapProjection.nearest(anchor, world),
      );
      if ((icon + offset - screenPoint).distance < 30) return WeatherHit(w.id);
    }
    return null;
  }

  /// Reports a tap at [screenPoint] to [onTap].
  void tapAt(Offset screenPoint) => onTap?.call(hitTest(screenPoint));
}
