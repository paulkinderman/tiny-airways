import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../tiny_airways_game.dart';
import '../flight_curve.dart';
import '../map_scene.dart';
import '../map_style.dart';
import '../projection.dart';
import '../sprites.dart';
import 'city_layer.dart';

/// Planes in flight, facing along their arcs, with a countdown over each of
/// the player's planes. Rival planes fly in their livery without one.
///
/// A busy sky is kept readable (see [PlaneLayer.layout]):
/// - countdowns never overlap each other or an airport pin; when two would,
///   the plane landing sooner keeps its countdown;
/// - a plane taking off from or landing on an airport slips under the pin
///   (drawn by a second [PlaneLayer] with [underAirports] set, below the
///   cities) and drops its countdown, so the airport's level and badges
///   stay readable;
/// - planes flying on top of each other draw as one plane, with a count
///   when zoomed in;
/// - rival planes are smaller and fainter than the player's.
///
/// While the player picks a route the planes fade back and lose their
/// countdowns, so the airports under them stay easy to see and tap.
class PlaneLayer extends Component with HasGameReference<TinyAirwaysGame> {
  PlaneLayer({this.underAirports = false});

  /// Draws only the planes sitting on an airport pin, below the cities. The
  /// layer above the cities (with this false) works out the layout each
  /// frame and draws everything else.
  final bool underAirports;

  /// Countdowns hide below this zoom (except on the selected plane) so a
  /// zoomed-out map isn't a pile of pills.
  static const pillZoom = 0.6;

  /// How strongly planes show while the player picks a route.
  static const pickingOpacity = 0.35;

  /// How strongly a plane shows while it sits under an airport pin.
  static const overAirportOpacity = 0.8;

  /// How strongly rival planes show.
  static const rivalOpacity = 0.6;

  /// Player planes closer than this (screen pixels) draw as one; further
  /// apart when zoomed out, where the map has less room.
  static double stackDistance(double zoom) =>
      CityLayer.compactAt(zoom) ? 18 : 14;

  final _pills = <String, MapPill>{};
  final _counts = <int, MapText>{};
  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;
  final _halo = Paint()
    ..color = MapStyle.amber
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  /// How each plane is drawn this frame, by plane id.
  Map<String, PlaneLook> looks = const {};

  @override
  void update(double dt) {
    if (!underAirports) looks = layout();
  }

  Map<String, PlaneLook> get _frameLooks => underAirports
      ? game.children
                .whereType<PlaneLayer>()
                .where((l) => !l.underAirports)
                .firstOrNull
                ?.looks ??
            const {}
      : looks;

  @override
  void render(Canvas canvas) {
    final zoom = game.mapCamera.zoom;
    final scene = game.scene;
    final now = game.now;
    final scale = planeScale(zoom);
    final picking = scene.routePicker != null;
    final looks = _frameLooks;
    final live = <String>{};

    game.paintWorld(canvas, (visible) {
      final area = visible.inflate(40 / zoom);
      // Rivals first, so the player's planes draw on top.
      for (final rivals in [true, false]) {
        for (final f in scene.flights) {
          if (f.isRival != rivals) continue;
          final look = looks[f.planeId];
          if (look == null || look.hidden) continue;
          if (look.underAirport != underAirports) continue;
          final at = game.flightPosition(f);
          if (!area.contains(at.point)) continue;
          final selected = f.planeId == scene.selectedPlaneId;
          game.paintAt(canvas, at.point, () {
            if (selected) {
              canvas.drawCircle(
                Offset.zero,
                20 + math.sin(game.seconds * 4) * 2,
                _halo,
              );
            }
            final size =
                (f.isRival ? MapStyle.rivalPlaneSize : MapStyle.planeSize) *
                scale;
            Sprites.plane(
              canvas,
              size: size,
              heading: at.heading,
              wing: f.livery ?? MapStyle.planeWing,
              opacity: look.opacity * (picking ? pickingOpacity : 1),
            );
            if (look.stacked > 1 && !picking && !CityLayer.compactAt(zoom)) {
              _paintCount(canvas, look.stacked, size);
            }
            if (look.pill) {
              live.add(f.planeId);
              _pill(
                f.planeId,
                formatCountdown(f.arriveAt.difference(now)),
              ).paintCentred(canvas, pillOffset(scale));
            }
          });
        }
      }
    });
    if (!underAirports) _pills.removeWhere((id, _) => !live.contains(id));
  }

  /// Planes shrink when zoomed out, so a zoomed-out network is a scatter
  /// of small planes rather than a pile.
  static double planeScale(double zoom) => (0.4 + zoom * 0.6).clamp(0.6, 1.0);

  /// Where a countdown sits relative to its plane, in screen pixels.
  static Offset pillOffset(double scale) => Offset(0, -22 * scale - 6);

  /// Works out how every plane in the scene is drawn this frame: faded or
  /// not, with a countdown or not, and which planes fold into a stack.
  Map<String, PlaneLook> layout() {
    final cam = game.mapCamera;
    final zoom = cam.zoom;
    final scene = game.scene;
    final picking = scene.routePicker != null;
    final scale = planeScale(zoom);
    Offset screenOf(Offset p) =>
        cam.worldToScreen(MapProjection.nearest(p, cam.centre));
    final onScreen = (Offset.zero & cam.viewport).inflate(60);

    // Airport pins on screen, as circles in screen pixels.
    final compact = CityLayer.compactAt(zoom);
    final pins = <(Offset, double)>[];
    for (final a in scene.airports) {
      final p = screenOf(game.cityPoint(a.cityId));
      if (onScreen.contains(p)) {
        pins.add((p, CityLayer.pinRadius(a, compact: compact)));
      }
    }
    bool overPin(Offset p, double margin) =>
        pins.any((pin) => (pin.$1 - p).distance < pin.$2 + margin);

    final looks = <String, PlaneLook>{};
    final mine = <(MapFlight, Offset)>[];
    for (final f in scene.flights) {
      final p = screenOf(game.flightPosition(f).point);
      if (f.isRival) {
        looks[f.planeId] = PlaneLook(
          opacity: rivalOpacity,
          underAirport: overPin(p, 4),
        );
      } else if (onScreen.contains(p)) {
        mine.add((f, p));
      } else {
        looks[f.planeId] = const PlaneLook();
      }
    }

    // The selected plane first, then whichever lands soonest.
    final selectedId = scene.selectedPlaneId;
    mine.sort((a, b) {
      if (a.$1.planeId == selectedId) return -1;
      if (b.$1.planeId == selectedId) return 1;
      return a.$1.arriveAt.compareTo(b.$1.arriveAt);
    });

    // Fold planes flying on top of each other into the first of them.
    final leaders = <(MapFlight, Offset)>[];
    final stackOf = <String, int>{};
    for (final (f, p) in mine) {
      final selected = f.planeId == selectedId;
      final under = selected
          ? null
          : leaders
                .where(
                  (l) =>
                      l.$1.planeId != selectedId &&
                      (l.$2 - p).distance < stackDistance(zoom),
                )
                .firstOrNull;
      if (under != null) {
        stackOf[under.$1.planeId] = (stackOf[under.$1.planeId] ?? 1) + 1;
        looks[f.planeId] = const PlaneLook(hidden: true);
      } else {
        leaders.add((f, p));
      }
    }

    // Countdowns: never on top of another countdown or an airport pin.
    final taken = <Rect>[
      for (final (c, r) in pins) Rect.fromCircle(center: c, radius: r + 2),
    ];
    for (final (f, p) in leaders) {
      final selected = f.planeId == selectedId;
      final landing = !selected && overPin(p, 8);
      var pill = false;
      if (!picking && !landing && (zoom >= pillZoom || selected)) {
        final size = _pill(
          f.planeId,
          formatCountdown(f.arriveAt.difference(game.now)),
        ).size;
        final rect = Rect.fromCenter(
          center: p + pillOffset(scale),
          width: size.width,
          height: size.height,
        ).inflate(2);
        if (selected || !taken.any(rect.overlaps)) {
          taken.add(rect);
          pill = true;
        }
      }
      looks[f.planeId] = PlaneLook(
        opacity: landing ? overAirportOpacity : 1,
        pill: pill,
        stacked: stackOf[f.planeId] ?? 1,
        underAirport: landing,
      );
    }
    return looks;
  }

  /// A small orange tag with how many planes are stacked here, styled
  /// like the planes' wings so it never reads as an airport level.
  void _paintCount(Canvas canvas, int count, double planeSize) {
    final text = _counts.putIfAbsent(
      count,
      () => MapText(
        '×$count',
        size: 10,
        weight: FontWeight.w700,
        color: MapStyle.ink,
        halo: null,
      ),
    );
    final at = Offset(planeSize * 0.45, planeSize * 0.4);
    final tag = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: at,
        width: text.size.width + 8,
        height: text.size.height + 2,
      ),
      const Radius.circular(6),
    );
    _fill.color = MapStyle.planeWing;
    _stroke
      ..color = MapStyle.ink
      ..strokeWidth = 1.5;
    canvas
      ..drawRRect(tag, _fill)
      ..drawRRect(tag, _stroke);
    text.paintCentred(canvas, at);
  }

  /// The pill for [planeId], laid out again only when its text changes
  /// (about once a second).
  MapPill _pill(String planeId, String text) {
    final pill = _pills[planeId];
    if (pill != null && pill.text == text) return pill;
    return _pills[planeId] = MapPill(text);
  }
}

/// How one plane is drawn in a frame.
class PlaneLook {
  const PlaneLook({
    this.opacity = 1,
    this.pill = false,
    this.stacked = 1,
    this.hidden = false,
    this.underAirport = false,
  });

  final double opacity;

  /// Whether its countdown shows.
  final bool pill;

  /// How many planes draw as this one (1 when it flies alone).
  final int stacked;

  /// Folded into a stack led by another plane.
  final bool hidden;

  /// Taking off from or landing on an airport, so drawn under its pin.
  final bool underAirport;
}
