import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/game/demo_scene.dart';
import 'package:tiny_airways/game/map/map_scene.dart';
import 'package:tiny_airways/game/map/world_geometry.dart';
import 'package:tiny_airways/game/tiny_airways_game.dart';
import 'package:tiny_airways/game/world_map_view.dart';

void main() {
  late GameConfig config;
  late WorldGeometry geometry;
  late FakeClock clock;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    geometry = WorldGeometry.parse(
      File('assets/map/world.json').readAsStringSync(),
    );
  });

  setUp(() => clock = FakeClock(DateTime.utc(2026, 10, 30, 20)));

  Future<TinyAirwaysGame> show(WidgetTester tester, MapScene scene) async {
    tester.view.physicalSize = const Size(390, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final game = TinyAirwaysGame(
      worldData: config.world,
      geometry: geometry,
      clock: clock,
      scene: scene,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorldMapView(game: game)),
      ),
    );
    // The game loop never settles, so pump frames by hand.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('the map opens on the player network and draws without errors', (
    tester,
  ) async {
    final demo = demoScene(clock.now());
    final northAmerica = demo.copyWith(
      airports: [
        for (final a in demo.airports)
          if (config.world.city(a.cityId).regionId == 'north_america') a,
      ],
    );
    final game = await show(tester, northAmerica);
    expect(tester.takeException(), isNull);
    // Every owned airport is in view.
    final view = game.mapCamera.visibleRect;
    for (final a in game.scene.airports) {
      final p = game.cityPoint(a.cityId);
      final shifted = [-2048.0, 0.0, 2048.0].map((d) => p.translate(d, 0));
      expect(shifted.any(view.contains), isTrue, reason: a.cityId);
    }
  });

  testWidgets('tapping a plane, a city and open sea reports each', (
    tester,
  ) async {
    final hits = <MapHit?>[];
    final game = await show(tester, demoScene(clock.now()));
    game.onTap = hits.add;
    game.showCity('chicago', zoom: 1.5, animate: false);
    await tester.pump(const Duration(milliseconds: 16));

    final plane = game.planePosition('p2')!.point;
    await tester.tapAt(game.mapCamera.worldToScreen(plane));
    final denver = game.cityPoint('denver');
    await tester.tapAt(game.mapCamera.worldToScreen(denver));
    game.showCity('honolulu', zoom: 3, animate: false);
    await tester.pump(const Duration(milliseconds: 16));
    final sea = game.cityPoint('honolulu') + const Offset(20, 40);
    await tester.tapAt(game.mapCamera.worldToScreen(sea));

    expect(hits, hasLength(3));
    expect((hits[0]! as PlaneHit).planeId, 'p2');
    expect((hits[1]! as CityHit).cityId, 'denver');
    expect(hits[2], isNull);
  });

  testWidgets('a rival plane reports a rival hit, not one of yours', (
    tester,
  ) async {
    MapHit? hit = const CityHit('none');
    final game = await show(tester, demoScene(clock.now()));
    game.onTap = (h) => hit = h;
    final rival = game.scene.flights.firstWhere((f) => f.planeId == 'r3');
    game.showCity(rival.fromCityId, zoom: 4, animate: false);
    await tester.pump(const Duration(milliseconds: 16));
    final at = game.flightPosition(rival).point;
    game.tapAt(game.mapCamera.worldToScreen(at));
    expect(hit, isNot(isA<PlaneHit>()));
    expect(hit, isA<RivalPlaneHit>());
    expect((hit! as RivalPlaneHit).planeId, 'r3');
  });

  testWidgets('planes move as the clock moves', (tester) async {
    final game = await show(tester, demoScene(clock.now()));
    final before = game.planePosition('p1')!;
    clock.advance(const Duration(minutes: 2));
    await tester.pump(const Duration(milliseconds: 16));
    final after = game.planePosition('p1')!;
    expect(after.progress, greaterThan(before.progress));
    expect(after.point, isNot(before.point));
  });

  testWidgets('drag pans, the buttons zoom', (tester) async {
    final game = await show(tester, const MapScene());
    final centre = game.mapCamera.centre;
    final zoom = game.mapCamera.zoom;

    await tester.drag(
      find.byKey(const Key('worldMap.gestures')),
      const Offset(-120, 0),
    );
    await settle(tester);
    expect(game.mapCamera.centre.dx, greaterThan(centre.dx));

    await tester.tap(find.byKey(const Key('worldMap.zoomIn')));
    await settle(tester);
    expect(game.mapCamera.zoom, closeTo(zoom * 2, 1e-6));
    await tester.tap(find.byKey(const Key('worldMap.zoomOut')));
    await settle(tester);
    expect(game.mapCamera.zoom, closeTo(zoom, 1e-6));
  });

  testWidgets('the route picker, weather and every zoom level draw cleanly', (
    tester,
  ) async {
    final game = await show(tester, demoRouteScene(clock.now()));
    for (final zoom in [game.mapCamera.minZoom, 0.8, 2.0, 8.0, 14.0]) {
      game.showCity('chicago', zoom: zoom, animate: false);
      game.mapCamera.jumpTo(game.cityPoint('chicago'), zoom: zoom);
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.scene = demoScene(clock.now())
        .copyWith(selectedCityId: () => 'miami', selectedPlaneId: () => 'p3');
    // Run through forecasts turning active and events ending.
    for (var i = 0; i < 8; i++) {
      clock.advance(const Duration(minutes: 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.showRegion('antarctica', animate: false);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a frame with 20 planes in the air stays well inside budget', (
    tester,
  ) async {
    // This measures the Dart side of a frame (moving planes and recording
    // the drawing) on the test machine. The GPU side is checked by eye on a
    // device; see docs/world-map.md.
    final game = await show(tester, demoScene(clock.now()));
    game.mapCamera.jumpTo(game.cityPoint('chicago'), zoom: 1.4);
    expect(game.scene.flights.where((f) => !f.isRival), hasLength(20));
    void frame() {
      clock.advance(const Duration(milliseconds: 16));
      game.update(1 / 60);
      final recorder = ui.PictureRecorder();
      game.render(Canvas(recorder));
      recorder.endRecording().dispose();
    }

    for (var i = 0; i < 30; i++) {
      frame();
    }
    const frames = 300;
    final watch = Stopwatch()..start();
    for (var i = 0; i < frames; i++) {
      frame();
    }
    final perFrame = watch.elapsedMicroseconds / frames / 1000;
    // ignore: avoid_print
    print('Map frame (update + record): ${perFrame.toStringAsFixed(2)} ms');
    expect(perFrame, lessThan(4));
  });
}
