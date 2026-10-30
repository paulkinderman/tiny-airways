import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/game/map/flight_curve.dart';
import 'package:tiny_airways/game/map/projection.dart';

void main() {
  const a = Offset(100, 300);
  const b = Offset(300, 300);

  test('a plane starts at its origin and ends at its destination', () {
    final c = FlightCurve(a, b);
    expect(c.pointAt(0), a);
    expect((c.pointAt(1) - b).distance, lessThan(1e-9));
  });

  test('routes bow towards the top of the map', () {
    final east = FlightCurve(a, b).pointAt(0.5);
    final west = FlightCurve(b, a).pointAt(0.5);
    expect(east.dy, lessThan(300));
    expect(west.dy, lessThan(300));
  });

  test('a plane moves at an even speed along the arc', () {
    final c = FlightCurve(a, b);
    final steps = [
      for (var i = 0; i < 10; i++)
        (c.pointAt((i + 1) / 10) - c.pointAt(i / 10)).distance,
    ];
    for (final s in steps) {
      expect(s, closeTo(c.length / 10, c.length * 0.01));
    }
  });

  test('a plane faces along its arc', () {
    final c = FlightCurve(a, b);
    // Heading east at the top of the arc.
    expect(c.headingAt(0.5), closeTo(0, 0.02));
    // Climbing north-east at the start (y grows south).
    expect(c.headingAt(0), lessThan(0));
    expect(c.headingAt(0), greaterThan(-math.pi / 2));
  });

  test('a leg over the date line takes the short way', () {
    final la = MapProjection.project(34, -118);
    final tokyo = MapProjection.project(35.7, 139.7);
    final c = FlightCurve(la, tokyo);
    expect(c.length, lessThan(MapProjection.worldWidth / 2));
    expect(c.pointAt(0.5).dx, lessThan(la.dx));
  });

  test('progress runs from departure to arrival and stops at 1', () {
    final depart = DateTime.utc(2026, 10, 30, 20);
    final arrive = depart.add(const Duration(minutes: 10));
    expect(flightProgress(depart, arrive, depart), 0);
    expect(
      flightProgress(depart, arrive, depart.add(const Duration(minutes: 5))),
      0.5,
    );
    expect(
      flightProgress(depart, arrive, arrive.add(const Duration(hours: 1))),
      1,
    );
    expect(
      flightProgress(depart, arrive, depart.subtract(const Duration(hours: 1))),
      0,
    );
  });

  test('countdowns read like the mockups', () {
    expect(formatCountdown(const Duration(hours: 1, minutes: 40)), '1h 40m');
    expect(formatCountdown(const Duration(minutes: 11, seconds: 5)), '11m');
    expect(formatCountdown(const Duration(minutes: 4, seconds: 12)), '4m 12s');
    expect(formatCountdown(const Duration(seconds: 42)), '42s');
    expect(formatCountdown(const Duration(milliseconds: 41200)), '42s');
    expect(formatCountdown(Duration.zero), 'Landing');
  });
}
