import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/game/map/projection.dart';
import 'package:tiny_airways/game/map/world_geometry.dart';

void main() {
  late WorldGeometry geometry;
  late GameConfig config;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    geometry = WorldGeometry.parse(
      File('assets/map/world.json').readAsStringSync(),
    );
  });

  test('both levels of detail have land for every region', () {
    for (final lod in [geometry.detail, geometry.coarse]) {
      expect(lod.regions.keys.toSet(), {
        for (final r in config.world.regions) r.id,
      });
      for (final shapes in lod.regions.values) {
        expect(shapes, isNotEmpty);
      }
      expect(lod.coast, isNotEmpty);
      expect(lod.lakes, isNotEmpty);
    }
    expect(
      geometry.coarse.regions.values.expand((s) => s).length,
      lessThan(geometry.detail.regions.values.expand((s) => s).length),
    );
  });

  test("every city is on (or right by) its own region's land", () {
    // Coastal cities can sit a whisker offshore once the coast is
    // simplified, so look a few map units around each one.
    const reach = [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0];
    final misplaced = <String>[];
    for (final city in config.world.cities) {
      final p = MapProjection.city(city);
      final shapes = geometry.detail.regions[city.regionId]!;
      final found = [
        for (final dx in reach)
          for (final dy in reach) p + Offset(dx, dy),
      ].any((q) => shapes.any((s) => s.path.contains(q)));
      if (!found) misplaced.add(city.id);
    }
    expect(misplaced, isEmpty);
  });

  test('land and sea are told apart', () {
    expect(geometry.isLand(MapProjection.project(48.86, 2.35)), isTrue);
    expect(geometry.isLand(MapProjection.project(30, -40)), isFalse);
    // Wrapped x works too.
    final paris = MapProjection.project(48.86, 2.35);
    expect(
      geometry.isLand(paris + const Offset(MapProjection.worldWidth, 0)),
      isTrue,
    );
  });
}
