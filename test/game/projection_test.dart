
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/world.dart';
import 'package:tiny_airways/game/map/projection.dart';

void main() {
  test('latitude and longitude round trip', () {
    for (final (lat, lon) in [(0.0, 0.0), (51.5, -0.13), (-33.9, 151.2)]) {
      final p = MapProjection.project(lat, lon);
      expect(MapProjection.latOf(p.dy), closeTo(lat, 1e-9));
      expect(MapProjection.lonOf(p.dx), closeTo(lon, 1e-9));
    }
  });

  test('the map runs from the northern cut at y 0 to the South Pole', () {
    expect(MapProjection.yOf(MapProjection.northLat), 0);
    expect(MapProjection.worldHeight, MapProjection.yOf(-90));
    expect(MapProjection.worldHeight.isFinite, isTrue);
    expect(MapProjection.xOf(-180), 0);
    expect(MapProjection.xOf(180), MapProjection.worldWidth);
  });

  test('the South Pole station sits inside the map, above its edge', () {
    const pole = City(
      id: 'south_pole_station',
      name: 'South Pole Station',
      country: 'AQ',
      regionId: 'antarctica',
      lat: -90,
      lon: 0,
      size: 1,
      population: 150,
    );
    final p = MapProjection.city(pole);
    expect(p.dy, lessThan(MapProjection.worldHeight));
    expect(MapProjection.latOf(p.dy), closeTo(-85, 1e-9));
  });

  test('x wraps east to west', () {
    const w = MapProjection.worldWidth;
    expect(MapProjection.wrapX(w + 10), 10);
    expect(MapProjection.wrapX(-10), w - 10);
    // Tokyo seen from Los Angeles is the copy to the west, across the
    // Pacific, not the one across the Atlantic.
    final la = MapProjection.project(34, -118);
    final tokyo = MapProjection.project(35.7, 139.7);
    final near = MapProjection.nearest(tokyo, la);
    expect(near.dx, lessThan(la.dx));
    expect((near - la).distance, lessThan(w / 2));
    expect(near, Offset(tokyo.dx - w, tokyo.dy));
  });
}
