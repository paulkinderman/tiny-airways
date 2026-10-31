import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../tiny_airways_game.dart';
import '../map_style.dart';
import '../projection.dart';
import '../sprites.dart';

/// Wave squiggles in the sea and a few clouds drifting east, so the map
/// feels alive. Purely decorative.
class DecorLayer extends Component with HasGameReference<TinyAirwaysGame> {
  /// Roughly how far apart waves are on screen, in pixels.
  static const waveSpacing = 150.0;

  /// Cloud drift in map units per second.
  static const cloudSpeed = 0.6;

  final _isSea = <int, bool>{};
  late final List<Offset> _clouds;

  @override
  Future<void> onLoad() async {
    final random = math.Random(11);
    _clouds = [
      for (var i = 0; i < 18; i++)
        MapProjection.project(
          -50 + random.nextDouble() * 115,
          -180 + random.nextDouble() * 360,
        ),
    ];
  }

  @override
  void render(Canvas canvas) {
    final cam = game.mapCamera;
    final zoom = cam.zoom;
    // Waves sit on a grid whose cell is a power of two in map units, so the
    // pattern stays put while panning and only re-spaces as zoom halves or
    // doubles.
    final level = (math.log(waveSpacing / zoom) / math.ln2).round();
    final cell = math.pow(2, level).toDouble();
    final bob = math.sin(game.seconds * 1.6) * 1.5;

    game.paintWorld(canvas, (visible) {
      final x0 = (math.max(visible.left, 0) / cell).floor();
      final x1 = (math.min(visible.right, MapProjection.worldWidth) / cell)
          .ceil();
      final y0 = (math.max(visible.top, 0) / cell).floor();
      final y1 = (math.min(visible.bottom, MapProjection.worldHeight) / cell)
          .ceil();
      for (var gx = x0; gx < x1; gx++) {
        for (var gy = y0; gy < y1; gy++) {
          final point = _wavePoint(gx, gy, level, cell);
          if (point == null) continue;
          game.paintAt(canvas, point, () {
            canvas.translate(0, bob);
            Sprites.wave(canvas, 22, MapStyle.wave);
          });
        }
      }

      // Clouds hide when zoomed far out, where they would cover whole
      // countries.
      if (zoom < 0.45) return;
      final drift = game.seconds * cloudSpeed;
      for (final c in _clouds) {
        final p = Offset(MapProjection.wrapX(c.dx + drift), c.dy);
        if (!visible.inflate(60 / zoom).contains(p)) continue;
        game.paintAt(canvas, p, () {
          Sprites.cloud(canvas, width: 46, color: const Color(0xF2FFFFFF));
        });
      }
    });
  }

  /// A jittered point in grid cell ([gx], [gy]), or null if it would land on
  /// or right next to land. Results are cached.
  Offset? _wavePoint(int gx, int gy, int level, double cell) {
    final h = _hash(gx, gy, level);
    final point = Offset(
      (gx + 0.2 + 0.6 * ((h & 0xff) / 255)) * cell,
      (gy + 0.2 + 0.6 * (((h >> 8) & 0xff) / 255)) * cell,
    );
    final key = h;
    final sea = _isSea.putIfAbsent(key, () {
      final margin = cell * 0.18;
      final geometry = game.geometry;
      return !geometry.isLand(point) &&
          !geometry.isLand(point + Offset(margin, 0)) &&
          !geometry.isLand(point - Offset(margin, 0)) &&
          !geometry.isLand(point + Offset(0, margin)) &&
          !geometry.isLand(point - Offset(0, margin));
    });
    return sea ? point : null;
  }

  static int _hash(int x, int y, int level) {
    var h = x * 73856093 ^ y * 19349663 ^ (level + 64) * 83492791;
    h = (h ^ (h >> 13)) * 0x5bd1e995;
    return (h ^ (h >> 15)) & 0x7fffffff;
  }
}
