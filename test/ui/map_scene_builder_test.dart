import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/game/map/map_scene.dart';
import 'package:tiny_airways/logic/simulation.dart';
import 'package:tiny_airways/ui/map_scene_builder.dart';
import 'package:tiny_airways/ui/ui_state.dart';

import '../logic/logic_test_helpers.dart';

void main() {
  late Simulation sim;
  late GameState started;
  final now = DateTime.utc(2026, 10, 30, 20);

  setUpAll(() async {
    sim = Simulation(Rules(await testConfig()));
  });

  setUp(() {
    final fresh = GameState.newGame(now: now, startingMoney: 2500);
    started = sim.startAirline(fresh, 'chicago', now);
  });

  test('airports, waiting planes and locked regions come from the state', () {
    final scene = buildMapScene(
      sim: sim,
      state: started,
      ui: const UiState(),
      now: now,
    );
    expect(scene.airports.map((a) => a.cityId), contains('chicago'));
    final home = scene.airports.firstWhere((a) => a.cityId == 'chicago');
    expect(home.level, 2);
    expect(home.waitingPlanes, 1);
    expect(scene.flights.where((f) => !f.isRival), isEmpty);
    expect(scene.lockedRegionIds, isNot(contains('north_america')));
    expect(scene.lockedRegionIds, contains('europe'));
  });

  test('a region license unlocks it on the map and paths show a badge', () {
    final licensed = started.copyWith(
      player: started.player.copyWith(level: 5, money: 100000),
    );
    var state = sim.growth.buyLicense(licensed, 'europe');
    state = sim.growth.buyPathTier(state, 'chicago', 'cargo', now);
    final scene = buildMapScene(
      sim: sim,
      state: state,
      ui: const UiState(),
      now: now,
    );
    expect(scene.lockedRegionIds, isNot(contains('europe')));
    expect(scene.lockedRegionIds, contains('asia'));
    final home = scene.airports.firstWhere((a) => a.cityId == 'chicago');
    expect(home.badgeColor, isNotNull);
    final before = buildMapScene(
      sim: sim,
      state: started,
      ui: const UiState(),
      now: now,
    );
    expect(sceneKey(scene), isNot(sceneKey(before)));
  });

  test('a plane in the air becomes a map flight with its later stops', () {
    final plane = started.planes.single;
    final other = started.airports.last.cityId;
    final flying = sim.depart(started, plane.id, [other, 'chicago'], now);
    final scene = buildMapScene(
      sim: sim,
      state: flying,
      ui: const UiState(),
      now: now,
    );
    final f = scene.flights.where((f) => !f.isRival).single;
    expect(f.planeId, plane.id);
    expect(f.fromCityId, 'chicago');
    expect(f.toCityId, other);
    expect(f.laterStops, ['chicago']);
    expect(f.arriveAt.isAfter(now), isTrue);
  });

  test('rival planes fly in livery, and city leaders fly their flag', () {
    final leading = started.copyWith(
      player: started.player.copyWith(level: 10),
      rivals: started.rivals
          .updateCity(
            'chicago',
            (_) => const CityShare(points: {playerAirlineId: 50}),
          )
          .updateCity(
            'dallas',
            (_) => const CityShare(points: {'skysaver': 50}),
          ),
    );
    final scene = buildMapScene(
      sim: sim,
      state: leading,
      ui: const UiState(),
      now: now,
    );
    final rivals = scene.flights.where((f) => f.isRival).toList();
    expect(rivals, isNotEmpty);
    for (final f in rivals) {
      expect(f.livery, isNotNull);
      expect(f.planeId, startsWith('rival:'));
    }
    expect(scene.cityFlags['chicago'], playerFlagColor);
    expect(scene.cityFlags['dallas'], liveryColor('#F28C28'));
    expect(
      sceneKey(scene),
      isNot(
        sceneKey(
          buildMapScene(
            sim: sim,
            state: started,
            ui: const UiState(),
            now: now,
          ),
        ),
      ),
    );
  });

  test('weather events map to the right kind of area', () {
    WeatherEvent event(String type, {String? city, double? lat}) =>
        WeatherEvent(
          id: type,
          typeId: type,
          regionId: 'north_america',
          forecastAt: now,
          startsAt: now.add(const Duration(minutes: 10)),
          endsAt: now.add(const Duration(minutes: 40)),
          cityId: city,
          bandLat: lat,
          eastbound: lat == null ? null : false,
        );
    final config = sim.rules.config;
    expect(
      mapWeather(config, event('thunderstorm', city: 'chicago')).area,
      isA<WeatherAtCity>(),
    );
    final snow = mapWeather(config, event('snowstorm', city: 'chicago')).area;
    expect(snow, isA<WeatherCluster>());
    expect((snow as WeatherCluster).radiusKm, config.weather.clusterRadiusKm);
    final jet = mapWeather(config, event('jet_stream', lat: 45)).area;
    expect(jet, isA<WeatherBand>());
    expect((jet as WeatherBand).eastward, isFalse);
  });

  test('the route picker shows the range ring and reachable airports', () {
    final plane = started.planes.single;
    final scene = buildMapScene(
      sim: sim,
      state: started,
      ui: UiState(panel: RoutePanel(plane.id)),
      now: now,
    );
    final picker = scene.routePicker!;
    expect(picker.originCityId, 'chicago');
    expect(picker.rangeKm, greaterThan(0));
    expect(picker.reachableCityIds, contains(started.airports.last.cityId));
    expect(picker.reachableCityIds, isNot(contains('chicago')));
  });

  test('the scene key changes only when something visible changes', () {
    MapScene scene(GameState s, [UiState ui = const UiState()]) =>
        buildMapScene(sim: sim, state: s, ui: ui, now: now);
    final a = sceneKey(scene(started));
    final ticked = started.copyWith(
      simulatedTo: now.add(const Duration(seconds: 1)),
    );
    expect(sceneKey(scene(ticked)), a);
    expect(
      sceneKey(scene(started, const UiState(panel: AirportPanel('chicago')))),
      isNot(a),
    );
  });
}
