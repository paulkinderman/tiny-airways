import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'projection.dart';

/// Where the map is looking: a centre in map units and a zoom in screen
/// pixels per map unit. Handles panning, pinch zoom, flings and animated
/// jumps, keeps the map inside its top and bottom edges, and wraps east to
/// west so the Pacific is never a dead end.
class MapCamera {
  MapCamera();

  /// Closest zoom: about 600 km across a phone screen.
  static const maxZoom = 14.0;

  Size _viewport = Size.zero;
  Offset _centre = const Offset(MapProjection.worldWidth / 2, 600);
  double _zoom = 1;

  Offset _velocity = Offset.zero;
  _Flight? _flight;

  Size get viewport => _viewport;
  Offset get centre => _centre;
  double get zoom => _zoom;

  /// Parts of the screen covered by panels, so jumps centre a city in the
  /// part of the map that is still visible.
  EdgeInsets insets = EdgeInsets.zero;

  /// Furthest zoom: the map's full height fills the screen (on a phone in
  /// portrait that shows about half the world, and panning wraps round).
  /// On a wide screen, the whole world's width.
  double get minZoom {
    if (_viewport.isEmpty) return 0.05;
    return math.max(
      _viewport.width / MapProjection.worldWidth,
      _viewport.height / MapProjection.worldHeight,
    );
  }

  bool get isMoving => _velocity != Offset.zero || _flight != null;

  void resize(Size viewport) {
    _viewport = viewport;
    _zoom = _zoom.clamp(minZoom, maxZoom);
    _clamp();
  }

  /// The visible area in map units (x not wrapped).
  Rect get visibleRect => Rect.fromCenter(
    center: _centre,
    width: _viewport.width / _zoom,
    height: _viewport.height / _zoom,
  );

  Offset worldToScreen(Offset world) =>
      (world - _centre) * _zoom + _viewport.center(Offset.zero);

  Offset screenToWorld(Offset screen) =>
      (screen - _viewport.center(Offset.zero)) / _zoom + _centre;

  /// Moves the map with a finger drag of [screenDelta] pixels.
  void panBy(Offset screenDelta) {
    _flight = null;
    _velocity = Offset.zero;
    _centre -= screenDelta / _zoom;
    _clamp();
  }

  /// Zooms by [factor] keeping the map point under [focus] (screen pixels)
  /// in place, as a pinch does.
  void zoomBy(double factor, Offset focus) {
    _flight = null;
    _velocity = Offset.zero;
    final anchor = screenToWorld(focus);
    _zoom = (_zoom * factor).clamp(minZoom, maxZoom);
    _centre = anchor - (focus - _viewport.center(Offset.zero)) / _zoom;
    _clamp();
  }

  /// Keeps the map gliding after a drag ends at [screenVelocity] px/s.
  void fling(Offset screenVelocity) {
    _flight = null;
    _velocity = screenVelocity / _zoom;
  }

  void stop() {
    _velocity = Offset.zero;
    _flight = null;
  }

  /// Glides to centre [target] (map units) in the visible part of the map,
  /// at [zoom] if given. With [keepCentre], [target] becomes the camera
  /// centre itself, ignoring [insets].
  void flyTo(
    Offset target, {
    double? zoom,
    Duration duration = const Duration(milliseconds: 700),
    bool keepCentre = false,
  }) {
    _velocity = Offset.zero;
    final endZoom = (zoom ?? _zoom).clamp(minZoom, maxZoom);
    final shift = keepCentre
        ? Offset.zero
        : Offset(
            (insets.right - insets.left) / 2,
            (insets.bottom - insets.top) / 2,
          );
    final end = MapProjection.nearest(target + shift / endZoom, _centre);
    _flight = _Flight(
      fromCentre: _centre,
      toCentre: end,
      fromZoom: _zoom,
      toZoom: endZoom,
      seconds: duration.inMilliseconds / 1000,
    );
  }

  /// Sets the camera straight away, with [target] in the visible part of
  /// the map.
  void jumpTo(Offset target, {double? zoom}) {
    flyTo(target, zoom: zoom, duration: Duration.zero);
    update(0);
  }

  /// Zoom that fits [bounds] (map units) in the visible part of the map.
  double zoomToFit(Rect bounds, {double padding = 48}) {
    final w = _viewport.width - insets.horizontal - padding * 2;
    final h = _viewport.height - insets.vertical - padding * 2;
    if (w <= 0 || h <= 0) return _zoom;
    final zx = bounds.width == 0 ? maxZoom : w / bounds.width;
    final zy = bounds.height == 0 ? maxZoom : h / bounds.height;
    return math.min(zx, zy).clamp(minZoom, maxZoom);
  }

  /// Advances flings and jumps by [dt] seconds.
  void update(double dt) {
    final flight = _flight;
    if (flight != null) {
      flight.elapsed += dt;
      final t = flight.seconds <= 0
          ? 1.0
          : (flight.elapsed / flight.seconds).clamp(0.0, 1.0);
      final e = Curves.easeInOutCubic.transform(t);
      _centre = Offset.lerp(flight.fromCentre, flight.toCentre, e)!;
      _zoom = math.exp(
        _lerp(math.log(flight.fromZoom), math.log(flight.toZoom), e),
      );
      if (t >= 1) _flight = null;
      _clamp();
      return;
    }
    if (_velocity != Offset.zero) {
      _centre -= _velocity * dt;
      // Friction: lose about 95% of the speed each second.
      _velocity *= math.pow(0.05, dt).toDouble();
      if (_velocity.distance * _zoom < 20) _velocity = Offset.zero;
      _clamp();
    }
  }

  void _clamp() {
    if (_viewport.isEmpty) return;
    final halfHeight = _viewport.height / 2 / _zoom;
    final mapHeight = MapProjection.worldHeight;
    final y = 2 * halfHeight >= mapHeight
        ? mapHeight / 2
        : _centre.dy.clamp(halfHeight, mapHeight - halfHeight);
    if (y != _centre.dy) _velocity = Offset(_velocity.dx, 0);
    // Keep x on the first copy of the map so numbers stay small. A jump in
    // progress recomputes its position from both ends each frame, so
    // wrapping here never throws it off.
    _centre = Offset(MapProjection.wrapX(_centre.dx), y);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _Flight {
  _Flight({
    required this.fromCentre,
    required this.toCentre,
    required this.fromZoom,
    required this.toZoom,
    required this.seconds,
  });

  final Offset fromCentre;
  final Offset toCentre;
  final double fromZoom;
  final double toZoom;
  final double seconds;
  double elapsed = 0;
}
