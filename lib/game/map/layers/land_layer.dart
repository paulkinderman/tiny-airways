import 'dart:ui';

import 'package:flame/components.dart';

import '../../tiny_airways_game.dart';
import '../map_style.dart';
import '../world_geometry.dart';

/// The sea's shallows, the land of each region (muted while locked), lakes,
/// coastlines and region borders.
class LandLayer extends Component with HasGameReference<TinyAirwaysGame> {
  /// Below this zoom the coarse coastline is drawn, whole, in a handful of
  /// calls; above it the detailed one, skipping shapes off screen.
  static const detailZoom = 1.1;

  final _shallows = Paint()..color = MapStyle.shallows;
  final _land = Paint()..color = MapStyle.land;
  final _locked = Paint()..color = MapStyle.lockedLand;
  final _lake = Paint()..color = MapStyle.sea;
  final _coast = Paint()
    ..color = MapStyle.coast
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  final _border = Paint()
    ..color = MapStyle.border
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    final zoom = game.mapCamera.zoom;
    final locked = game.scene.lockedRegionIds;
    final coarse = zoom < detailZoom;
    final land = coarse ? game.geometry.coarse : game.geometry.detail;
    // Lines thin out when zoomed far out so small islands don't blot.
    final weight = zoom < 0.5 ? 0.6 : (zoom < 1 ? 0.8 : 1.0);
    _coast.strokeWidth = MapStyle.coastWidth * weight / zoom;
    _border.strokeWidth = MapStyle.borderWidth * weight / zoom;
    final drop = MapStyle.shallowsOffset * weight / zoom;

    game.paintWorld(canvas, (visible) {
      if (coarse) {
        canvas
          ..save()
          ..translate(0, drop);
        for (final p in land.regionPaths.values) {
          canvas.drawPath(p, _shallows);
        }
        canvas.restore();
        land.regionPaths.forEach(
          (id, p) => canvas.drawPath(p, locked.contains(id) ? _locked : _land),
        );
        canvas
          ..drawPath(land.lakePath, _lake)
          ..drawPath(land.lakePath, _coast)
          ..drawPath(land.coastPath, _coast)
          ..drawPath(land.borderPath, _border);
        return;
      }

      final area = visible.inflate(drop + 4);
      bool onScreen(MapShape s) => s.bounds.overlaps(area);
      canvas
        ..save()
        ..translate(0, drop);
      for (final shapes in land.regions.values) {
        for (final s in shapes.where(onScreen)) {
          canvas.drawPath(s.path, _shallows);
        }
      }
      canvas.restore();
      land.regions.forEach((id, shapes) {
        final paint = locked.contains(id) ? _locked : _land;
        for (final s in shapes.where(onScreen)) {
          canvas.drawPath(s.path, paint);
        }
      });
      for (final s in land.lakes.where(onScreen)) {
        canvas
          ..drawPath(s.path, _lake)
          ..drawPath(s.path, _coast);
      }
      for (final s in land.coast.where(onScreen)) {
        canvas.drawPath(s.path, _coast);
      }
      for (final s in land.borders.where(onScreen)) {
        canvas.drawPath(s.path, _border);
      }
    });
  }
}
