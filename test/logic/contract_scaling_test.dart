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

  group('several open contracts', () {
    const planes = [Plane(id: 'p1', modelId: 'pelican_p4', cityId: 'chicago')];
    const airports = [
      AirportState(cityId: 'chicago', level: 3),
      AirportState(cityId: 'atlanta'),
      AirportState(cityId: 'dallas'),
      AirportState(cityId: 'los_angeles'),
      AirportState(cityId: 'miami'),
    ];
    GameState due(int level) =>
        airline(
          airports: airports,
          planes: planes,
          level: level,
          money: 0,
        ).copyWith(
          rivals: RivalsState(lastStepAt: t0, nextContractAt: t0),
        );

    test('one open at level 7, two at 15, three at 25, four at 40', () {
      for (final (level, slots) in [
        (7, 1),
        (14, 1),
        (15, 2),
        (25, 3),
        (40, 4),
      ]) {
        expect(sim.rivals.contractSlots(due(level)), slots, reason: '$level');
      }
    });

    test('fill their slots in different cities with different goals', () {
      var s = due(25);
      for (var h = 1; h <= 3; h++) {
        s = runTo(sim, s, t0.add(Duration(minutes: 50 * h)));
      }
      final live = s.rivals.liveContracts;
      expect(live, hasLength(3));
      expect(live.map((c) => c.cityId).toSet(), hasLength(3));
      expect(live.map((c) => c.goal).toSet(), hasLength(3));
      for (final c in live) {
        final pct = config.rivals.contractGoal(c.goal).targetPct;
        final base = sim.rivals.contractJobsToWin(s);
        expect(
          c.jobsToWin,
          pct == 100 ? base : (base * pct / 100).round().clamp(5, base),
        );
      }
      // Full: nothing more starts until one finishes.
      final later = runTo(sim, s, t0.add(const Duration(minutes: 170)));
      expect(later.rivals.liveContracts.length, lessThanOrEqualTo(3));
    });

    test('count only the deliveries their goal asks for', () {
      final rivals = sim.rivals;
      Contract goal(String g) => Contract(
        id: 'c',
        cityId: 'chicago',
        goal: g,
        jobsToWin: 10,
        prize: 1,
        startsAt: t0,
        endsAt: t0,
        rivalIds: const [],
      );
      final near = job('a', 'atlanta', 'chicago');
      final far = job('b', 'los_angeles', 'chicago');
      final crate = cargo('c', 'atlanta', 'chicago');
      expect(rivals.contractCounts(goal('any'), crate, 'chicago'), isTrue);
      expect(
        rivals.contractCounts(goal('passengers'), near, 'chicago'),
        isTrue,
      );
      expect(
        rivals.contractCounts(goal('passengers'), crate, 'chicago'),
        isFalse,
      );
      expect(rivals.contractCounts(goal('cargo'), crate, 'chicago'), isTrue);
      expect(rivals.contractCounts(goal('cargo'), near, 'chicago'), isFalse);
      expect(rivals.contractCounts(goal('long_haul'), far, 'chicago'), isTrue);
      expect(
        rivals.contractCounts(goal('long_haul'), near, 'chicago'),
        isFalse,
      );
    });
  });
}
