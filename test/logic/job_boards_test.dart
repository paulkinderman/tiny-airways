import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

void main() {
  late GameConfig config;
  late Rules rules;
  late JobBoards boards;
  late Simulation sim;

  setUpAll(() async {
    config = await testConfig();
    rules = Rules(config);
    boards = JobBoards(rules);
    sim = Simulation(rules);
  });

  GameState network({
    int level = 1,
    int money = 10000,
    Map<String, int> chicagoPaths = const {},
    List<Job> chicagoBoard = const [],
    List<String> others = const ['toronto', 'minneapolis', 'nashville'],
    List<Plane> planes = const [
      Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago'),
    ],
  }) => airline(
    airports: [
      AirportState(
        cityId: 'chicago',
        level: 2,
        pathTiers: chicagoPaths,
        board: chicagoBoard,
      ),
      for (final id in others) AirportState(cityId: id),
    ],
    planes: planes,
    level: level,
    money: money,
  );

  List<Job> boardOf(GameState s, String city) => s.airport(city)!.board;

  group('filling a board', () {
    test('fills to the level size, 40% cargo', () {
      final state = boards.fill(network(), 'chicago', t0);
      final board = boardOf(state, 'chicago');
      expect(board, hasLength(9)); // level 2
      expect(board.where((j) => j.type == JobType.cargo), hasLength(4));
      expect(
        boardOf(boards.fill(state, 'toronto', t0), 'toronto'),
        hasLength(6),
      );
    });

    test(
      'jobs only go to owned airports at least the minimum distance away',
      () {
        final state = boards.fill(network(), 'chicago', t0);
        for (final j in boardOf(state, 'chicago')) {
          expect([
            'toronto',
            'minneapolis',
            'nashville',
          ], contains(j.destCityId));
          expect(j.originCityId, 'chicago');
          expect(
            rules.distanceKm('chicago', j.destCityId),
            greaterThanOrEqualTo(config.jobs.minJobDistanceKm),
          );
        }
      },
    );

    test('an airport with nowhere to send jobs has an empty board', () {
      final state = boards.fill(network(others: const []), 'chicago', t0);
      expect(boardOf(state, 'chicago'), isEmpty);
    });

    test('payout is rate x distance', () {
      final state = boards.fill(
        network(others: const ['toronto']),
        'chicago',
        t0,
      );
      final km = rules.distanceKm('chicago', 'toronto');
      for (final j in boardOf(state, 'chicago')) {
        final rate = j.type == JobType.passenger ? 0.35 : 0.45;
        expect(j.payout, (rate * km).round());
        expect(j.kind, JobKind.standard);
      }
    });

    test('Passenger and Cargo paths pay 15% more and add 3 jobs each', () {
      final state = boards.fill(
        network(
          others: const ['toronto'],
          chicagoPaths: const {'passenger': 2, 'cargo': 2},
        ),
        'chicago',
        t0,
      );
      final board = boardOf(state, 'chicago');
      expect(board.where((j) => j.type == JobType.passenger), hasLength(5 + 3));
      expect(board.where((j) => j.type == JobType.cargo), hasLength(4 + 3));
      final km = rules.distanceKm('chicago', 'toronto');
      final pax = board.firstWhere((j) => j.type == JobType.passenger);
      expect(pax.payout, (0.35 * km * 1.15).round());
    });

    test('cross-region jobs pay the cross-region bonus', () {
      final state = airline(
        airports: const [
          AirportState(cityId: 'miami'),
          AirportState(cityId: 'havana'),
          AirportState(cityId: 'bogota'),
        ],
      );
      final filled = boards.fill(state, 'miami', t0);
      final toBogota = boardOf(
        filled,
        'miami',
      ).where((j) => j.destCityId == 'bogota' && j.type == JobType.passenger);
      expect(toBogota, isNotEmpty);
      final km = rules.distanceKm('miami', 'bogota');
      expect(toBogota.first.payout, (0.35 * km * 1.2).round());
    });

    test('legs leaving Antarctica pay 3x', () {
      final state = airline(
        airports: const [
          AirportState(cityId: 'esperanza_base'),
          AirportState(cityId: 'ushuaia'),
        ],
      );
      final filled = boards.fill(state, 'esperanza_base', t0);
      final pax = boardOf(
        filled,
        'esperanza_base',
      ).firstWhere((j) => j.type == JobType.passenger);
      final km = rules.distanceKm('esperanza_base', 'ushuaia');
      expect(pax.payout, (0.35 * km * 3 * 1.2).round());
    });

    test(
      'Transfer hub tier 2 offers jobs beyond the fleet\'s reach at +30%',
      () {
        // A Sparrow reaches 1,200 km; Chicago to Miami is about 1,900.
        final state = boards.fill(
          network(others: const ['miami'], chicagoPaths: const {'transfer': 2}),
          'chicago',
          t0,
        );
        final km = rules.distanceKm('chicago', 'miami');
        final pax = boardOf(
          state,
          'chicago',
        ).firstWhere((j) => j.type == JobType.passenger);
        expect(pax.payout, (0.35 * km * 1.3).round());
        final plain = boards.fill(
          network(others: const ['miami']),
          'chicago',
          t0,
        );
        expect(
          boardOf(
            plain,
            'chicago',
          ).firstWhere((j) => j.type == JobType.passenger).payout,
          (0.35 * km).round(),
        );
      },
    );
  });

  group('special jobs', () {
    List<Job> rollMany(GameState state) {
      var s = state;
      final jobs = <Job>[];
      for (var i = 0; i < 60; i++) {
        s = boards.rotate(s, 'chicago', t0);
        jobs.addAll(boardOf(s, 'chicago'));
      }
      return jobs;
    }

    test('none appear before the special-jobs level', () {
      final jobs = rollMany(network(level: 6));
      expect(jobs.where((j) => j.kind != JobKind.standard), isEmpty);
    });

    test('VIP, fragile and rush jobs appear from level 7', () {
      final jobs = rollMany(network(level: 7));
      final kinds = jobs.map((j) => j.kind).toSet();
      expect(kinds, containsAll([JobKind.vip, JobKind.fragile, JobKind.rush]));
      expect(kinds, isNot(contains(JobKind.bulk)));
      final vip = jobs.firstWhere((j) => j.kind == JobKind.vip);
      expect(vip.type, JobType.passenger);
      expect(vip.deadline, t0.add(const Duration(minutes: 120)));
      final base = (0.35 * rules.distanceKm('chicago', vip.destCityId)).round();
      expect(vip.payout, closeTo(base * 3, 1));
    });

    test('a VIP lounge brings VIP jobs before level 7', () {
      final jobs = rollMany(network(chicagoPaths: const {'passenger': 3}));
      expect(jobs.where((j) => j.kind == JobKind.vip), isNotEmpty);
    });

    test('a freight yard brings bulk crates that take 2 slots', () {
      final jobs = rollMany(network(chicagoPaths: const {'cargo': 3}));
      final bulk = jobs.where((j) => j.kind == JobKind.bulk).toList();
      expect(bulk, isNotEmpty);
      expect(
        bulk.every((j) => j.type == JobType.cargo && j.slots == 2),
        isTrue,
      );
    });
  });

  group('rotation', () {
    test(
      'every 5 minutes, unclaimed jobs are replaced and connecting jobs stay',
      () {
        final waiting = job('w1', 'nashville', 'toronto', connectingSince: t0);
        final state = boards.fill(
          network(chicagoBoard: [waiting]),
          'chicago',
          t0,
        );
        final before = boardOf(state, 'chicago').map((j) => j.id).toSet();

        final early = runTo(
          sim,
          state,
          t0.add(const Duration(minutes: 4, seconds: 59)),
        );
        expect(boardOf(early, 'chicago').map((j) => j.id).toSet(), before);

        final rotated = runTo(sim, state, t0.add(const Duration(minutes: 5)));
        final after = boardOf(rotated, 'chicago');
        expect(after.map((j) => j.id), contains('w1'));
        expect(after.map((j) => j.id).toSet().intersection(before), {'w1'});
        expect(after.where((j) => !j.isConnecting), hasLength(9));
      },
    );

    test('after hours away, boards rotate once as of the latest mark', () {
      final state = boards.fill(network(), 'chicago', t0);
      final later = t0.add(const Duration(hours: 3, minutes: 7));
      final (after, _) = sim.advance(state, later);
      final board = boardOf(after, 'chicago');
      expect(board, hasLength(9));
      expect(
        board.every(
          (j) => j.createdAt == t0.add(const Duration(hours: 3, minutes: 5)),
        ),
        isTrue,
      );
      expect(after.boardRotation, boards.rotationIndex(later));
    });

    test(
      'connecting jobs expire after a while, unless the hub has Codeshare',
      () {
        final waiting = job('w1', 'nashville', 'toronto', connectingSince: t0);
        final state = network(chicagoBoard: [waiting]);
        final expiry = Duration(minutes: config.jobs.connectionExpiryMinutes);
        final gone = runTo(sim, state, t0.add(expiry));
        expect(
          boardOf(gone, 'chicago').map((j) => j.id),
          isNot(contains('w1')),
        );

        final codeshare = state.updateAirport(
          'chicago',
          (a) => a.copyWith(pathTiers: {'transfer': 3}),
        );
        final kept = runTo(sim, codeshare, t0.add(expiry * 3));
        expect(boardOf(kept, 'chicago').map((j) => j.id), contains('w1'));
      },
    );
  });

  group('paid refresh', () {
    test('costs 25 x city size and swaps every unclaimed job', () {
      final waiting = job('w1', 'nashville', 'toronto', connectingSince: t0);
      final state = boards.fill(
        network(chicagoBoard: [waiting]),
        'chicago',
        t0,
      );
      final before = boardOf(state, 'chicago').map((j) => j.id).toSet();
      expect(boards.refreshCost('chicago'), 100); // size 4

      final after = sim.refreshBoard(state, 'chicago', t0);
      expect(after.player.money, 10000 - 100);
      final ids = boardOf(after, 'chicago').map((j) => j.id).toSet();
      expect(ids.intersection(before), {'w1'});
      expect(ids, hasLength(10));
    });

    test('jobs already loaded on a plane are untouched', () {
      var state = boards.fill(network(), 'chicago', t0);
      final first = boardOf(state, 'chicago').first;
      state = sim.loadJob(state, 'p1', first.id, t0);
      final after = sim.refreshBoard(state, 'chicago', t0);
      expect(after.plane('p1')!.load.single.id, first.id);
    });

    test('is refused when the player cannot pay', () {
      final state = network(money: 99);
      expect(
        () => sim.refreshBoard(state, 'chicago', t0),
        throwsA(
          isA<RuleException>().having(
            (e) => e.error,
            'error',
            RuleError.notEnoughMoney,
          ),
        ),
      );
    });
  });
}
