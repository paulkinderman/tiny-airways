import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../tiny_airways_game.dart';
import '../flight_curve.dart';
import '../map_style.dart';
import '../sprites.dart';

/// Planes in flight, facing along their arcs, with a countdown over each of
/// the player's planes. Rival planes fly in their livery without one.
///
/// While the player picks a route the planes fade back and lose their
/// countdowns, so the airports under them stay easy to see and tap.
class PlaneLayer extends Component with HasGameReference<TinyAirwaysGame> {
  /// Countdowns hide below this zoom (except on the selected plane) so a
  /// zoomed-out map isn't a pile of pills.
  static const pillZoom = 0.6;

  /// How strongly planes show while the player picks a route.
  static const pickingOpacity = 0.35;

  final _pills = <String, MapPill>{};
  final _halo = Paint()
    ..color = MapStyle.amber
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  @override
  void render(Canvas canvas) {
    final zoom = game.mapCamera.zoom;
    final scene = game.scene;
    final now = game.now;
    // Planes shrink a touch when zoomed far out.
    final scale = (0.65 + zoom * 0.35).clamp(0.65, 1.0);
    final live = <String>{};
    final picking = scene.routePicker != null;

    game.paintWorld(canvas, (visible) {
      final area = visible.inflate(40 / zoom);
      // Rivals first, so the player's planes draw on top.
      for (final rivals in [true, false]) {
        for (final f in scene.flights) {
          if (f.isRival != rivals) continue;
          final at = game.flightPosition(f);
          if (!area.contains(at.point)) continue;
          game.paintAt(canvas, at.point, () {
            if (f.planeId == scene.selectedPlaneId) {
              canvas.drawCircle(
                Offset.zero,
                20 + math.sin(game.seconds * 4) * 2,
                _halo,
              );
            }
            Sprites.plane(
              canvas,
              size:
                  (f.isRival ? MapStyle.rivalPlaneSize : MapStyle.planeSize) *
                  scale,
              heading: at.heading,
              wing: f.livery ?? MapStyle.planeWing,
              opacity: (f.isRival ? 0.85 : 1) * (picking ? pickingOpacity : 1),
            );
            final selected = f.planeId == scene.selectedPlaneId;
            if (!picking && !f.isRival && (zoom >= pillZoom || selected)) {
              live.add(f.planeId);
              _pill(
                f.planeId,
                formatCountdown(f.arriveAt.difference(now)),
              ).paintCentred(canvas, Offset(0, -22 * scale - 6));
            }
          });
        }
      }
    });
    _pills.removeWhere((id, _) => !live.contains(id));
  }

  /// The pill for [planeId], laid out again only when its text changes
  /// (about once a second).
  MapPill _pill(String planeId, String text) {
    final pill = _pills[planeId];
    if (pill != null && pill.text == text) return pill;
    return _pills[planeId] = MapPill(text);
  }
}
