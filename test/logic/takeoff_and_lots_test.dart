import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/rng.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

/// Takeoff fuel and cargo lots, checked against the shipped
/// config (the pinned rules config predates them).
void main() {
  late GameConfig config;
  late Rules rules;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    rules = Rules(config);
  });

  GameState withPlane(String modelId) => airline(
    airports: const [
      AirportState(cityId: 'chicago', level: 5),
      AirportState(cityId: 'toronto', level: 5),
      AirportState(cityId: 'new_york', level: 5),
      AirportState(cityId: 'london', level: 5),
    ],
    planes: [Plane(id: 'p1', modelId: modelId, cityId: 'chicago')],
  );

  test('every takeoff burns the class takeoff km of extra fuel', () {
    final km = rules.distanceKm('chicago', 'toronto');
    for (final id in ['sparrow_s1', 'heron_m5', 'goose_g10']) {
      final state = withPlane(id);
      final model = config.planes.model(id);
      final takeoff = config.planes.planeClass(model.classId).takeoffKm;
      expect(takeoff, greaterThan(0));
      expect(
        Economy(rules)
            .fuelCost(state, state.plane('p1')!, 'chicago', 'toronto', never),
        (model.fuelPerKm * (km + takeoff)).round(),
      );
    }
  });

  test('big holds bring cargo lots that pay per slot', () {
    final boards = JobBoards(rules);
    final state = withPlane('condor_c9');
    final airport = state.airport('chicago')!;
    final rng = GameRng(7);
    final lots = <Job>[];
    for (var i = 0; i < 400; i++) {
      final j = boards.generate(
        state,
        rng,
        airport,
        JobType.cargo,
        t0,
        'j$i',
        double.infinity,
      )!;
      if (j.kind == JobKind.standard && j.slots > 1) lots.add(j);
    }
    expect(lots, isNotEmpty);
    expect(lots.every((j) => j.slots <= config.jobs.lotMaxSize), isTrue);
    expect(lots.map((j) => j.slots).toSet().length, greaterThan(1));
  });

  test('no lots when the fleet has no hold of two or more', () {
    final boards = JobBoards(rules);
    final state = withPlane('firefly_fx1');
    final airport = state.airport('chicago')!;
    final rng = GameRng(7);
    for (var i = 0; i < 200; i++) {
      final j = boards.generate(
        state,
        rng,
        airport,
        JobType.cargo,
        t0,
        'j$i',
        double.infinity,
      )!;
      if (j.kind == JobKind.standard) expect(j.slots, 1);
    }
  });
}
