import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/world.dart';
import 'package:tiny_airways/game/map/geo.dart';
import 'package:tiny_airways/game/map/projection.dart';

City _at(double lat, double lon) => City(
  id: '$lat,$lon',
  name: '',
  country: 'XX',
  regionId: 'r',
  lat: lat,
  lon: lon,
  size: 1,
  population: 1,
);

void main() {
  test('a destination point is the given distance away', () {
    for (final bearing in [0.0, 45.0, 90.0, 200.0]) {
      final p = destinationPoint(41.9, -87.6, bearing, 1200);
      final d = WorldData.distanceKm(_at(41.9, -87.6), _at(p.lat, p.lon));
      expect(d, closeTo(1200, 0.5));
    }
  });

  test('a range ring stays in one piece across the date line', () {
    final ring = geodesicRing(-18.1, 178.4, 1500); // Suva, Fiji
    for (var i = 1; i < ring.length; i++) {
      expect(
        (ring[i].dx - ring[i - 1].dx).abs(),
        lessThan(MapProjection.worldWidth / 4),
      );
    }
  });

  test('a ring round a pole is closed along the map edge', () {
    final ring = geodesicRing(-77.85, 166.67, 2500); // McMurdo
    expect(ring.last.dy, MapProjection.worldHeight);
    expect(ring[ring.length - 2].dy, MapProjection.worldHeight);
    final xs = ring.map((p) => p.dx);
    final span =
        xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
    expect(span, closeTo(MapProjection.worldWidth, 40));
  });
}
