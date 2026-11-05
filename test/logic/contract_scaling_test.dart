import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

/// Contracts on the shipped numbers grow with the airline: more deliveries,
/// rivals that keep pace, and a bigger prize.
void main() {
  late GameConfig config;
  late Simulation sim;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    sim = Simulation(Rules(config));
  });

  GameState at(int level) => airline(
    airports: const [AirportState(cityId: 'chicago', level: 3)],
    planes: const [],
    level: level,
    money: 0,
  );

  test('deliveries to win grow 2.5 a level from 15, up to 100', () {
    int jobs(int level) => sim.rivals.contractJobsToWin(at(level));
    expect(jobs(7), 15);
    expect(jobs(14), 33);
    expect(jobs(20), 48);
    expect(jobs(30), 73);
    expect(jobs(60), 100);
  });

  test('the prize is 300 x city size x level', () {
    final size = config.world.city('chicago').size;
    for (final level in [7, 14, 30]) {
      expect(
        sim.rivals.contractPrize(at(level), 'chicago'),
        300 * size * level,
      );
    }
  });

  test('a Wingman needs about 2.5 hours at any level', () {
    final c = config.rivals.contracts;
    for (final level in [7, 14, 30]) {
      final target = sim.rivals.contractJobsToWin(at(level));
      final perHour = c['rivalJobsPerHour']! * target / c['jobsToWin']!;
      expect(target / perHour, closeTo(2.5, 0.01));
    }
  });
}
