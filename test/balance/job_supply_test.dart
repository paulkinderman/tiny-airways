import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

/// Job supply check: how often a fully upgraded plane parked at a hub can
/// fly a charter (every seat to one city) as the network grows. The player
/// flies each charter as soon as it is possible, taking those jobs (all of
/// them to that city, a bit more than a charter needs). Boards roll
/// [rotations] times on the shipped numbers, and on the old numbers (no
/// network growth, hot destinations, groups or charter chance) for
/// comparison. The table prints with the test; docs/balance.md explains it.
void main() {
  const rotations = 400;
  const home = 'chicago';
  const others = [
    'toronto',
    'minneapolis',
    'nashville',
    'atlanta',
    'denver',
    'dallas',
    'new_york',
    'washington',
    'boston',
    'montreal',
    'houston',
    'miami',
    'phoenix',
    'las_vegas',
    'new_orleans',
    'calgary',
    'los_angeles',
  ];
  const planes = {
    'sparrow_s1': 1,
    'kestrel_k3': 2,
    'pelican_p4': 3,
    'heron_m5': 3,
    'albatross_l6': 4,
    'goose_g10': 5,
  };
  const networks = [3, 8, 18];

  late GameConfig shipped;
  late GameConfig old;
  final results = <String, double>{};

  GameState network(GameConfig config, String modelId, int level, int n) {
    final t = DateTime.utc(2026, 11, 2, 12);
    return GameState(
      createdAt: t,
      lastSeenAt: t,
      player: const PlayerState(money: 0, xp: 0, level: 30),
      homeCityId: home,
      airports: [
        for (final id in [home, ...others.take(n - 1)])
          AirportState(cityId: id, level: level),
      ],
      planes: [
        Plane(
          id: 'p1',
          modelId: modelId,
          cityId: home,
          upgrades: const PlaneUpgrades(
            capacity: 3,
            cargo: 3,
            speed: 3,
            range: 3,
          ),
        ),
      ],
      weather: const WeatherState(events: [], nextEventAt: {}),
      nextId: 1,
      rngState: 7,
      simulatedTo: t,
      boardRotation: t.millisecondsSinceEpoch ~/ (5 * 60 * 1000),
    );
  }

  /// Whether some slots in [sizes] add up to exactly [target].
  bool exact(List<int> sizes, int target) {
    var reach = {0};
    for (final s in sizes) {
      reach = {
        ...reach,
        for (final r in reach)
          if (r + s <= target) r + s,
      };
    }
    return reach.contains(target);
  }

  /// Share of rotations a charter (and a full hold) is possible.
  ({double charter, double hold, int seats, int board}) run(
    GameConfig config,
    String modelId,
    int level,
    int n,
  ) {
    final rules = Rules(config);
    final boards = JobBoards(rules);
    var state = network(config, modelId, level, n);
    final plane = state.planes.first;
    final stats = PlaneStats.of(rules, state, plane);
    final range = stats.rangeFrom(rules, state.airport(home));
    var charters = 0;
    var holds = 0;
    var boardJobs = 0;
    for (var i = 0; i < rotations; i++) {
      final t = boards.rotationTime(state.boardRotation + 1);
      state = boards.rotate(
        state.copyWith(boardRotation: state.boardRotation + 1),
        home,
        t,
      );
      final board = state.airport(home)!.board;
      boardJobs += board.length;
      String? any(JobType type, int capacity) {
        if (capacity == 0) return null;
        final byCity = <String, List<int>>{};
        for (final j in board) {
          if (j.type != type) continue;
          if (rules.distanceKm(home, j.destCityId) > range) continue;
          (byCity[j.destCityId] ??= []).add(j.slots);
        }
        for (final e in byCity.entries) {
          if (exact(e.value, capacity)) return e.key;
        }
        return null;
      }

      // The player flies every charter they can, taking those jobs.
      final charter = any(JobType.passenger, stats.seats);
      final hold = any(JobType.cargo, stats.cargoSlots);
      if (charter != null) charters++;
      if (hold != null) holds++;
      if (charter != null || hold != null) {
        state = state.updateAirport(
          home,
          (a) => a.copyWith(
            board: [
              for (final j in a.board)
                if (!(j.type == JobType.passenger && j.destCityId == charter) &&
                    !(j.type == JobType.cargo && j.destCityId == hold))
                  j,
            ],
          ),
        );
      }
    }
    return (
      charter: 100 * charters / rotations,
      hold: 100 * holds / rotations,
      seats: stats.seats,
      board: (boardJobs / rotations).round(),
    );
  }

  setUpAll(() async {
    shipped = await ConfigLoader(DirectoryConfigSource('assets')).load();
    old = await ConfigLoader(_OldSupply()).load();
    final out = StringBuffer(
      'Charter possible (full hold possible) per rotation, fully upgraded '
      'plane parked at Chicago, every airport at the level shown:\n',
    );
    for (final MapEntry(key: model, value: level) in planes.entries) {
      for (final n in networks) {
        final now = run(shipped, model, level, n);
        final was = run(old, model, level, n);
        results['$model/$n'] = now.charter;
        out.writeln(
          '${model.padRight(13)} ${now.seats.toString().padLeft(2)} seats, '
          'Lv $level, ${n.toString().padLeft(2)} airports: '
          'board ${was.board} -> ${now.board} jobs, '
          'charter ${was.charter.toStringAsFixed(0)}% -> '
          '${now.charter.toStringAsFixed(0)}% '
          '(hold ${was.hold.toStringAsFixed(0)}% -> '
          '${now.hold.toStringAsFixed(0)}%)',
        );
      }
    }
    // ignore: avoid_print
    print(out);
  });

  test('jobs wait three rotations, and each rotation brings a batch', () {
    final rules = Rules(shipped);
    final boards = JobBoards(rules);
    var state = network(shipped, 'kestrel_k3', 2, 8);
    final t1 = boards.rotationTime(state.boardRotation + 1);
    state = boards.rotate(
      state.copyWith(boardRotation: state.boardRotation + 1),
      home,
      t1,
    );
    final size = boards.boardSize(state, state.airport(home)!);
    final batch = boards.batchSize(state, state.airport(home)!);
    // Empty the board, then let three rotations pass with nobody taking.
    state = state.updateAirport(home, (a) => a.copyWith(board: const []));
    final counts = <int>[];
    for (var i = 2; i <= 5; i++) {
      final t = boards.rotationTime(state.boardRotation + 1);
      state = boards.rotate(
        state.copyWith(boardRotation: state.boardRotation + 1),
        home,
        t,
      );
      final board = state.airport(home)!.board;
      counts.add(board.where((j) => j.createdAt == t).length);
      for (final j in board) {
        expect(t.difference(j.createdAt), lessThan(boards.jobLifetime));
      }
    }
    expect(counts.first, greaterThanOrEqualTo(batch.passenger + batch.cargo));
    final total = state.airport(home)!.board.length;
    expect(total, greaterThanOrEqualTo(size.passenger + size.cargo));
  });

  test('a paid refresh fills the board with staggered timers', () {
    final rules = Rules(shipped);
    final boards = JobBoards(rules);
    var state = network(
      shipped,
      'kestrel_k3',
      2,
      8,
    ).copyWith(player: const PlayerState(money: 100000, xp: 0, level: 30));
    final t = boards
        .rotationTime(state.boardRotation)
        .add(const Duration(minutes: 2));
    state = boards.refresh(state, home, t);
    final ages = {
      for (final j in state.airport(home)!.board)
        if (j.destCityId != home) t.difference(j.createdAt).inMinutes,
    };
    expect(ages, containsAll([0, 5, 10]));
  });

  test('a big network still brings charters regularly, but not always', () {
    for (final model in planes.keys) {
      final pct = results['$model/18']!;
      expect(pct, inInclusiveRange(20, 75), reason: model);
    }
  });

  test('charters are possible regularly on every network size', () {
    for (final e in results.entries) {
      expect(e.value, greaterThanOrEqualTo(20), reason: e.key);
    }
  });

  group('supply rules', () {
    late Rules rules;
    late JobBoards boards;
    setUp(() {
      rules = Rules(shipped);
      boards = JobBoards(rules);
    });

    test('boards grow by half a job per airport beyond the first', () {
      final a = shipped.airports;
      expect(a.jobBoardSize(2, 3), 9);
      expect(a.jobBoardSize(2, 3, airportsOwned: 3), 10);
      expect(a.jobBoardSize(2, 3, airportsOwned: 18), 17);
      expect(a.jobBoardSize(1, 1, airportsOwned: 18), 8);
    });

    test('demand follows city size, airport level and closeness', () {
      var state = network(shipped, 'kestrel_k3', 1, 8);
      final from = state.airport(home)!;
      double w(String c) => boards.destinationWeight(state, from, c);
      // Toronto (size 4) outpulls Nashville (size 3) at the same level.
      expect(w('toronto'), greaterThan(w('nashville')));
      final before = w('nashville');
      state = state.updateAirport('nashville', (a) => a.copyWith(level: 5));
      expect(w('nashville'), closeTo(before * 2.5, 1e-9));
      // Farther cities of the same size and level pull less.
      expect(w('minneapolis'), greaterThan(w('denver')));
    });

    test('hot destinations hold for two rotations, then change', () {
      var state = network(shipped, 'kestrel_k3', 2, 18);
      final start = state.boardRotation - state.boardRotation % 2;
      List<String> at(int r) =>
          boards.hotDestinations(state.copyWith(boardRotation: r), home);
      expect(at(start), hasLength(3));
      expect(at(start + 1), at(start));
      final later = {for (var i = 2; i < 40; i += 2) at(start + i).join()};
      expect(later.length, greaterThan(5));
      state = network(shipped, 'kestrel_k3', 2, 3);
      expect(boards.hotDestinations(state, home), hasLength(1));
    });

    test('most new jobs go to hot destinations', () {
      var state = network(shipped, 'kestrel_k3', 2, 18);
      var hot = 0;
      var all = 0;
      for (var i = 0; i < 50; i++) {
        final t = boards.rotationTime(state.boardRotation + 1);
        state = boards.rotate(
          state.copyWith(boardRotation: state.boardRotation + 1),
          home,
          t,
        );
        final hotNow = boards.hotDestinations(state, home);
        for (final j in state.airport(home)!.board) {
          if (j.destCityId == home || j.createdAt != t) continue;
          all++;
          if (hotNow.contains(j.destCityId)) hot++;
        }
      }
      expect(hot / all, inInclusiveRange(0.6, 0.85));
    });

    test('groups take several seats and pay per seat', () {
      var state = network(shipped, 'goose_g10', 5, 18);
      final groups = <Job>[];
      for (var i = 0; i < 20; i++) {
        final t = boards.rotationTime(state.boardRotation + 1);
        state = boards.rotate(
          state.copyWith(boardRotation: state.boardRotation + 1),
          home,
          t,
        );
        groups.addAll(state.airport(home)!.board.where((j) => j.slots > 1));
      }
      expect(groups, isNotEmpty);
      for (final g in groups) {
        expect(g.type, JobType.passenger);
        expect(g.slots, inInclusiveRange(2, 4));
      }
      // A Sparrow-only fleet sees few, and only pairs.
      state = network(shipped, 'sparrow_s1', 1, 18);
      final sizes = <int>{};
      for (var i = 0; i < 20; i++) {
        final t = boards.rotationTime(state.boardRotation + 1);
        state = boards.rotate(
          state.copyWith(boardRotation: state.boardRotation + 1),
          home,
          t,
        );
        sizes.addAll(state.airport(home)!.board.map((j) => j.slots));
      }
      expect(sizes, everyElement(lessThanOrEqualTo(2)));
    });

    test('a charter top-up fills the parked plane to one city', () {
      final config = shipped;
      final state = network(config, 'goose_g10', 5, 18);
      final stats = PlaneStats.of(rules, state, state.planes.first);
      // Roll until the charter chance hits.
      for (var seed = 1; seed < 50; seed++) {
        final before = state.copyWith(rngState: seed);
        final after = boards.charterChance(before, home, before.simulatedTo);
        final added = after.airport(home)!.board;
        if (added.isEmpty) continue;
        final dests = added.map((j) => j.destCityId).toSet();
        expect(dests, hasLength(1));
        expect(boards.hotDestinations(state, home), contains(dests.single));
        int sum(JobType type) =>
            added.where((j) => j.type == type).fold(0, (n, j) => n + j.slots);
        expect(sum(JobType.passenger), stats.seats);
        expect(sum(JobType.cargo), stats.cargoSlots);
        return;
      }
      fail('the charter chance never hit');
    });
  });
}

/// The shipped config with the job supply rules turned off, as boards
/// worked before them.
class _OldSupply implements ConfigSource {
  final _shipped = DirectoryConfigSource('assets');

  @override
  Future<String> read(String name) async {
    final text = await _shipped.read(name);
    if (name != 'config/jobs' && name != 'config/airports') return text;
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (name == 'config/airports') json['networkJobsPerAirport'] = 0;
    if (name == 'config/jobs') {
      json
        ..['jobLifetimeRotations'] = 1
        ..['gravityKm'] = 1e12
        ..['hotShare'] = 0
        ..['groupChancePctPerSeat'] = 0
        ..['groupMaxChancePct'] = 0
        ..['charterChancePct'] = 0;
    }
    return jsonEncode(json);
  }
}
