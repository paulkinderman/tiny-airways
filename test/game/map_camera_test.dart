
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/game/map/map_camera.dart';
import 'package:tiny_airways/game/map/projection.dart';

void main() {
  late MapCamera camera;
  const phone = Size(390, 700);

  setUp(() {
    camera = MapCamera()..resize(phone);
    camera.jumpTo(MapProjection.project(40, -90), zoom: 2);
  });

  test('screen and map points convert both ways', () {
    const screen = Offset(50, 600);
    final world = camera.screenToWorld(screen);
    expect(camera.worldToScreen(world), offsetMoreOrLessEquals(screen));
    expect(camera.worldToScreen(camera.centre), const Offset(195, 350));
  });

  test('a pinch keeps the point under the fingers still', () {
    const focus = Offset(80, 200);
    final before = camera.screenToWorld(focus);
    camera.zoomBy(1.7, focus);
    expect(camera.zoom, closeTo(3.4, 1e-9));
    expect(camera.screenToWorld(focus), offsetMoreOrLessEquals(before));
  });

  test('zoom stays between the whole map height and city level', () {
    camera.zoomBy(1000, Offset.zero);
    expect(camera.zoom, MapCamera.maxZoom);
    camera.zoomBy(0.0001, Offset.zero);
    expect(camera.zoom, camera.minZoom);
    expect(
      camera.minZoom,
      closeTo(phone.height / MapProjection.worldHeight, 1e-9),
    );
  });

  test('panning stops at the top and bottom of the map', () {
    camera.panBy(const Offset(0, 100000));
    expect(camera.visibleRect.top, closeTo(0, 1e-6));
    camera.panBy(const Offset(0, -100000));
    expect(camera.visibleRect.bottom, closeTo(MapProjection.worldHeight, 1e-6));
  });

  test('panning east forever wraps round the world', () {
    for (var i = 0; i < 50; i++) {
      camera.panBy(const Offset(-500, 0));
    }
    expect(camera.centre.dx, inInclusiveRange(0, MapProjection.worldWidth));
  });

  test('a fling glides then comes to rest', () {
    final start = camera.centre;
    camera.fling(const Offset(-1500, 0));
    expect(camera.isMoving, isTrue);
    for (var i = 0; i < 300; i++) {
      camera.update(1 / 60);
    }
    expect(camera.isMoving, isFalse);
    expect(camera.centre.dx, greaterThan(start.dx));
  });

  test('a jump centres the target in the part of the map not under panels', () {
    camera.insets = const EdgeInsets.only(top: 100, bottom: 300);
    final paris = MapProjection.project(48.86, 2.35);
    camera.flyTo(paris, zoom: 4);
    for (var i = 0; i < 60; i++) {
      camera.update(1 / 60);
    }
    expect(camera.isMoving, isFalse);
    expect(camera.zoom, 4);
    // The visible strip runs from y 100 to y 400; its middle is 250.
    expect(
      camera.worldToScreen(paris),
      offsetMoreOrLessEquals(const Offset(195, 250)),
    );
  });

  test('a jump across the date line goes the short way', () {
    camera.jumpTo(MapProjection.project(21.3, -157.9), zoom: 2); // Honolulu
    final tokyo = MapProjection.project(35.7, 139.7);
    camera.flyTo(tokyo);
    camera.update(0.35);
    // Halfway there it is over the Pacific, not over the Americas.
    final lon = MapProjection.lonOf(camera.centre.dx);
    expect(lon < -157.9 || lon > 139.7, isTrue);
    camera.update(1);
    expect(
      camera.worldToScreen(tokyo),
      offsetMoreOrLessEquals(const Offset(195, 350)),
    );
  });
}
