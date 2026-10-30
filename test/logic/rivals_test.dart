import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

void main() {
  late GameConfig config;
  late Simulation sim;
  late Rivals rivals;

  setUpAll(() async {
    config = await testConfig();
    sim = Simulation(Rules(config));
    rivals = sim.rivals;
  });

  const p1 = Plane(id: 'p1', modelId: 'pelican_p4', cityId: 'chicago');
  const home = [
    AirportState(cityId: 'chicago', level: 3),
    AirportState(cityId: 'atlanta'),
    AirportState(cityId: 'dallas'),
  ];

  /// A level [level] airline in North America whose rivals stepped at t0.
  GameState started({
    int level = 10,
    int money = 1000000,
    List<AirportState> airports = home,
    List<Plane> planes = const [p1],
    RivalsState rivalsState = const RivalsState(),
  }) => airline(
    airports: airports,
    planes: planes,
    level: level,
    money: money,
  ).copyWith(rivals: rivalsState.copyWith(lastStepAt: t0));

  GameState withShare(
    GameState s,
    String cityId,
    Map<String, double> points, {
    DateTime? hubSince,
    DateTime? leadSince,
  }) => s.copyWith(
    rivals: s.rivals.updateCity(
      cityId,
      (_) => CityShare(
        points: points,
        playerHubSince: hubSince,
        playerLeadSince: leadSince,
      ),
    ),
  );

  /// Runs the clock in 2-minute ticks, as when the game is open.
  GameState play(
    GameState s,
    Duration d, {
    GameState Function(GameState s, DateTime t)? each,
  }) {
    var next = s;
    final end = s.simulatedTo.add(d);
    var t = s.simulatedTo;
    while (t.isBefore(end)) {
      t = t.add(const Duration(minutes: 2));
      next = runTo(sim, next, t);
      if (each != null) next = each(next, t);
    }
    return next;
  }

  group('city share', () {
    test('turns on at airline level 5', () {
      final low = started(level: 4);
      final delivered = rivals.playerDelivered(
        low,
        job('j1', 'atlanta', 'chicago'),
        'chicago',
        400,
        t0,
      );
      expect(delivered.rivals.cities, isEmpty);
      expect(rivals.leaderOf(delivered, 'chicago'), isNull);

      final s = started(level: 5);
      final after = rivals.playerDelivered(
        s,
        job('j1', 'atlanta', 'chicago'),
        'chicago',
        400,
        t0,
      );
      expect(rivals.leaderOf(after, 'chicago'), playerAirlineId);
    });

    test('a delivery adds share in proportion to pay, +10% per path tier', () {
      final plain = started();
      final points = rivals.playerSharePoints(plain, 'atlanta', 400);
      expect(points, closeTo(400 * 0.01, 1e-9));
      final upgraded = plain.updateAirport(
        'atlanta',
        (a) => a.copyWith(pathTiers: {'passenger': 2, 'cargo': 1}),
      );
      expect(
        rivals.playerSharePoints(upgraded, 'atlanta', 400),
        closeTo(400 * 0.01 * 1.3, 1e-9),
      );
    });

    test('share decays about 2% an hour', () {
      final s = withShare(started(), 'chicago', {playerAirlineId: 1000});
      final later = rivals.step(s, t0.add(const Duration(hours: 10)), 1);
      // Rivals deliver here too, so only the player's points are exact.
      expect(
        later.rivals.share('chicago').of(playerAirlineId),
        closeTo(1000 * 0.817, 1),
      );
    });

    test('the leader earns +10% pay on jobs delivered there', () {
      final j = job('j1', 'atlanta', 'chicago', payout: 1000);
      final plain = started();
      expect(sim.flights.deliveryPay(plain, p1, j, t0), 1000);
      final leading = withShare(plain, 'chicago', {
        playerAirlineId: 50,
        'skysaver': 10,
      });
      expect(sim.flights.deliveryPay(leading, p1, j, t0), 1100);
      final trailing = withShare(plain, 'chicago', {
        playerAirlineId: 5,
        'skysaver': 10,
      });
      expect(sim.flights.deliveryPay(trailing, p1, j, t0), 1000);
    });

    test('landing a plane adds share to the city it delivers to', () {
      final s = started()
          .updateAirport('atlanta', (a) => a.copyWith(level: 3))
          .updatePlane(
            'p1',
            (p) => p.copyWith(
              load: [job('j1', 'chicago', 'atlanta', payout: 500)],
            ),
          );
      final flying = sim.depart(s, 'p1', ['atlanta'], t0);
      final landed = runTo(sim, flying, t0.add(const Duration(hours: 1)));
      expect(
        landed.rivals.share('atlanta').of(playerAirlineId),
        greaterThan(0),
      );
      expect(rivals.leaderOf(landed, 'atlanta'), isNotNull);
    });

    test('while a rival leads, new jobs are its for the first minute', () {
      final fresh = job('j1', 'chicago', 'atlanta');
      var s = withShare(started(), 'chicago', {'skysaver': 100});
      s = s.updateAirport('chicago', (a) => a.copyWith(board: [fresh]));
      final soon = t0.add(const Duration(seconds: 20));
      expect(rivals.isHeld(s, fresh, soon), isTrue);
      expect(
        () => sim.loading.load(s, 'p1', 'j1', soon),
        throwsA(
          isA<RuleException>().having(
            (e) => e.error,
            'error',
            RuleError.rivalFirstLook,
          ),
        ),
      );
      final later = t0.add(const Duration(seconds: 61));
      expect(rivals.isHeld(s, fresh, later), isFalse);
      expect(sim.loading.load(s, 'p1', 'j1', later).plane('p1')!.load, [fresh]);
      // The player's own lead never holds jobs back.
      final mine = withShare(s, 'chicago', {playerAirlineId: 100});
      expect(rivals.isHeld(mine, fresh, soon), isFalse);
    });
  });

  group('a simulated week', () {
    test(
      'a rival can win and lose a city; nothing the player owns is taken',
      () {
        var s = started();
        final before = s;
        var minMoney = s.player.money;
        String? rivalLed;
        var hour = 0;
        // The player hammers Chicago for two days, leaves it alone for three,
        // then comes back for two.
        for (final (hours, delivering) in [
          (48, true),
          (72, false),
          (48, true),
        ]) {
          for (var h = 0; h < hours; h++, hour++) {
            s = play(
              s,
              const Duration(hours: 1),
              each: (s, t) => delivering && t.minute % 6 == 0
                  ? rivals.playerDelivered(
                      s,
                      job('j$hour', 'atlanta', 'chicago'),
                      'chicago',
                      400,
                      t,
                    )
                  : s,
            );
            final leader = rivals.leaderOf(s, 'chicago');
            if (hour == 47) expect(leader, playerAirlineId);
            if (leader != null && leader != playerAirlineId) rivalLed = leader;
            if (s.player.money < minMoney) minMoney = s.player.money;
          }
        }
        expect(rivalLed, isNotNull, reason: 'a rival should take Chicago');
        expect(rivals.leaderOf(s, 'chicago'), playerAirlineId);

        // Rivals never touch what the player owns.
        expect(minMoney, before.player.money);
        expect(
          [for (final a in s.airports) (a.cityId, a.level, a.pathTiers)],
          [for (final a in before.airports) (a.cityId, a.level, a.pathTiers)],
        );
        expect(s.planes, before.planes);
      },
    );

    test('rivals play at half pace while the game is closed', () {
      final live = play(started(), const Duration(hours: 2));
      final away = runTo(sim, started(), t0.add(const Duration(hours: 2)));
      double total(GameState s) =>
          s.rivals.cities.values.fold(0.0, (sum, c) => sum + c.total);
      expect(total(away) / total(live), closeTo(0.5, 0.03));
    });

    test('a long time away catches up quickly in coarser steps', () {
      final watch = Stopwatch()..start();
      final s = runTo(sim, started(), t0.add(const Duration(days: 60)));
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      expect(s.rivals.lastStepAt, isNotNull);
      expect(s.rivals.season.number, greaterThan(4));
    });
  });

  group('hubs and terminals', () {
    test('50% share held for 3 days makes a hub with an extra board slot', () {
      var s = withShare(started(), 'chicago', {
        playerAirlineId: 100,
        'skysaver': 10,
      }, hubSince: t0);
      final airport = s.airport('chicago')!;
      final before = sim.boards.boardSize(s, airport);
      expect(rivals.isHub(s, 'chicago', t0), isFalse);
      s = s.copyWith(simulatedTo: t0.add(const Duration(days: 3)));
      expect(rivals.isHub(s, 'chicago', s.simulatedTo), isTrue);
      final after = sim.boards.boardSize(s, airport);
      expect(
        after.passenger + after.cargo,
        before.passenger + before.cargo + 1,
      );
    });

    test('dropping under 50% restarts the hub clock', () {
      final s = withShare(started(), 'chicago', {
        playerAirlineId: 10,
        'skysaver': 100,
      }, hubSince: t0);
      final next = rivals.step(s, t0.add(const Duration(minutes: 5)), 1);
      expect(next.rivals.share('chicago').playerHubSince, isNull);
    });

    test('building a terminal needs a hub, the level and the coins', () {
      var s = withShare(started(level: 9), 'chicago', {
        playerAirlineId: 100,
      }, hubSince: t0.subtract(const Duration(days: 4)));
      expect(rivals.terminalProblem(s, 'chicago', t0), RuleError.locked);
      s = s.copyWith(player: s.player.copyWith(level: 10));
      expect(rivals.terminalProblem(s, 'atlanta', t0), RuleError.notAHub);
      expect(rivals.terminalProblem(s, 'paris', t0), RuleError.notOwned);
      final size = config.world.city('chicago').size;
      expect(rivals.terminalCost(s, 'chicago'), 50000 * size);
      final built = sim.buildTerminal(s, 'chicago', t0);
      expect(built.rivals.terminal('chicago'), isNotNull);
      expect(built.player.money, s.player.money - 50000 * size);
      expect(
        rivals.terminalProblem(built, 'chicago', t0),
        RuleError.terminalBuilt,
      );
      // One terminal at level 10, a second at 15.
      final second = withShare(built, 'atlanta', {
        playerAirlineId: 100,
      }, hubSince: t0.subtract(const Duration(days: 4)));
      expect(
        rivals.terminalProblem(second, 'atlanta', t0),
        RuleError.terminalLimit,
      );
      final at15 = second.copyWith(player: second.player.copyWith(level: 15));
      expect(rivals.terminalProblem(at15, 'atlanta', t0), isNull);
    });

    test('terminal points come from jobs and buy nodes down each branch', () {
      var s = started().copyWith(
        rivals: RivalsState(
          lastStepAt: t0,
          terminals: [PlayerTerminal(cityId: 'chicago', builtAt: t0)],
        ),
      );
      for (var i = 0; i < 85; i++) {
        s = rivals.playerDelivered(
          s,
          job('j$i', 'chicago', 'atlanta'),
          'atlanta',
          100,
          t0,
        );
      }
      final terminal = s.rivals.terminal('chicago')!;
      expect(terminal.jobs, 85);
      expect(rivals.pointsEarned(terminal), 2);
      s = sim.learnTerminalNode(s, 'chicago', 'lounges', t0);
      s = sim.learnTerminalNode(s, 'chicago', 'gates', t0);
      expect(
        () => sim.learnTerminalNode(s, 'chicago', 'fortress', t0),
        throwsA(isA<RuleException>()),
      );
      expect(rivals.terminalEffect(s, 'chicago', 'passengerPayPct'), 5);
      expect(rivals.terminalEffect(s, 'chicago', 'boardSlots'), 1);

      // Lounges pay on passengers to or from the city.
      final j = job('j1', 'chicago', 'dallas', payout: 1000);
      expect(sim.flights.deliveryPay(s, p1, j, t0), 1050);
    });

    test('points stop at 10, so no terminal fills every node', () {
      final t = PlayerTerminal(cityId: 'chicago', builtAt: t0, jobs: 4000);
      expect(rivals.pointsEarned(t), 10);
    });

    test('gates halve the refresh; a premium lounge brings a VIP', () {
      var s = started().copyWith(
        rivals: RivalsState(
          lastStepAt: t0,
          terminals: [
            PlayerTerminal(
              cityId: 'chicago',
              builtAt: t0,
              nodes: const {'gates': 2, 'lounges': 4},
            ),
          ],
        ),
      );
      final full = sim.boards.refreshCost('chicago');
      expect(sim.boards.refreshCost('chicago', s), (full / 2).round());
      s = sim.boards.rotate(s, 'chicago', t0);
      expect(
        s.airport('chicago')!.board.where((j) => j.kind == JobKind.vip),
        isNotEmpty,
      );
    });

    test('rivals never take a terminal; its tree keeps working', () {
      final s = withShare(
        started().copyWith(
          rivals: RivalsState(
            lastStepAt: t0,
            terminals: [
              PlayerTerminal(
                cityId: 'chicago',
                builtAt: t0,
                nodes: const {'lounges': 1},
              ),
            ],
          ),
        ),
        'chicago',
        {'velvet_air': 5000},
      );
      final later = runTo(sim, s, t0.add(const Duration(days: 8)));
      expect(rivals.leaderOf(later, 'chicago'), 'velvet_air');
      expect(later.rivals.terminal('chicago'), isNotNull);
      final j = job('j1', 'atlanta', 'chicago', payout: 1000);
      // Lounges still pay; the leader's +10% is paused.
      expect(sim.flights.deliveryPay(later, p1, j, later.simulatedTo), 1050);
    });

    test('leading a rival hub for 7 days puts its terminal up for lease', () {
      expect(rivals.rivalTerminalAt(started(), 'dallas'), 'skysaver');
      final s = withShare(started(), 'dallas', {
        playerAirlineId: 1e7,
      }, leadSince: t0);
      final six = runTo(sim, s, t0.add(const Duration(days: 6)));
      expect(rivals.rivalTerminalAt(six, 'dallas'), 'skysaver');
      expect(rivals.isHeated(six, config.rivals.rival('skysaver')), isTrue);
      final seven = runTo(sim, six, t0.add(const Duration(days: 7, hours: 1)));
      expect(rivals.rivalTerminalAt(seven, 'dallas'), isNull);
      expect(rivals.isForLease(seven, 'dallas'), isTrue);
      expect(seven.rivals.heatedRivalIds, contains('skysaver'));
      final size = config.world.city('dallas').size;
      expect(rivals.terminalCost(seven, 'dallas'), 25000 * size);
      // No hub needed to lease it.
      final leased = sim.buildTerminal(seven, 'dallas', seven.simulatedTo);
      expect(leased.rivals.terminal('dallas')!.spent, 0);
    });

    test('Jumbos hold 3 fortified hubs, others 1', () {
      expect(rivals.fortifiedCities(config.rivals.rival('velvet_air')), [
        'new_york',
        ...rivals.fortifiedCities(config.rivals.rival('velvet_air')).skip(1),
      ]);
      expect(
        rivals.fortifiedCities(config.rivals.rival('velvet_air')),
        hasLength(3),
      );
      expect(rivals.fortifiedCities(config.rivals.rival('skysaver')), [
        'dallas',
      ]);
    });
  });

  group('contracts', () {
    GameState withContractDue(int level) => started(level: level).copyWith(
      rivals: RivalsState(lastStepAt: t0, nextContractAt: t0),
    );

    test('start at level 7 in one of the player\'s cities', () {
      final early = runTo(
        sim,
        withContractDue(6),
        t0.add(const Duration(minutes: 5)),
      );
      expect(early.rivals.contracts, isEmpty);
      final s = runTo(
        sim,
        withContractDue(7),
        t0.add(const Duration(minutes: 5)),
      );
      final c = s.rivals.liveContract!;
      expect(home.map((a) => a.cityId), contains(c.cityId));
      expect(c.rivalIds.length, inInclusiveRange(1, 2));
      for (final id in c.rivalIds) {
        expect(config.rivals.rival(id).regionId, 'north_america');
      }
      expect(c.prize, 10000 * config.world.city(c.cityId).size);
      expect(c.jobsToWin, 15);
      expect(
        s.rivals.nextContractAt,
        t0.add(const Duration(minutes: 5, hours: 3)),
      );
    });

    test('the first to 15 deliveries wins the prize and a burst of share', () {
      var s = runTo(
        sim,
        withContractDue(10),
        t0.add(const Duration(minutes: 5)),
      );
      final c = s.rivals.liveContract!;
      final money = s.player.money;
      final t = s.simulatedTo;
      for (var i = 0; i < 15; i++) {
        s = rivals.playerDelivered(
          s,
          job('j$i', 'paris', c.cityId),
          c.cityId,
          100,
          t,
        );
      }
      final won = s.rivals.contracts.firstWhere((x) => x.id == c.id);
      expect(won.winnerId, playerAirlineId);
      expect(s.rivals.liveContract, isNull);
      expect(s.player.money, money + c.prize);
      final region = config.world.city(c.cityId).regionId;
      expect(s.rivals.season.wins[SeasonState.playerKey(region)], 1);
      // 15 deliveries of 100 coins would be 15 points; the burst adds more.
      expect(s.rivals.share(c.cityId).of(playerAirlineId), greaterThan(15));
    });

    test('losing a contract costs nothing', () {
      var s = runTo(
        sim,
        withContractDue(10),
        t0.add(const Duration(minutes: 5)),
      );
      final c = s.rivals.liveContract!;
      final money = s.player.money;
      s = play(s, const Duration(hours: 4));
      final done = s.rivals.contracts.firstWhere((x) => x.id == c.id);
      expect(done.isLive, isFalse);
      expect(done.winnerId, isNot(playerAirlineId));
      expect(s.player.money, money);
      if (done.winnerId != null) {
        expect(s.rivals.season.wins[done.winnerId], 1);
      }
    });
  });

  group('seasons', () {
    test('after two weeks, results and trophies; rivals reset their wins', () {
      final start = t0.subtract(const Duration(days: 14));
      var s = withShare(started(), 'chicago', {playerAirlineId: 1000});
      s = withShare(s, 'atlanta', {playerAirlineId: 1000});
      s = s.copyWith(
        rivals: s.rivals.copyWith(
          season: SeasonState(
            startedAt: start,
            wins: {'skysaver': 2, SeasonState.playerKey('north_america'): 1},
          ),
        ),
      );
      final standings = rivals.standings(s, 'north_america');
      expect(standings.first.airlineId, playerAirlineId);

      final next = runTo(sim, s, t0.add(const Duration(minutes: 5)));
      final season = next.rivals.season;
      expect(season.number, 2);
      expect(season.startedAt, t0);
      expect(season.wins, isEmpty);
      final result = season.history.single;
      expect(result.regionId, 'north_america');
      expect(result.rank, 1);
      expect(result.difficulty, 'cruising_altitude');
      expect(result.trophyRivalIds, hasLength(4));
      expect(next.player.level, s.player.level);
      expect(next.player.money, s.player.money);
    });

    test('no results are recorded before the leaderboard unlocks', () {
      final s = started(level: 9).copyWith(
        rivals: RivalsState(
          lastStepAt: t0,
          season: SeasonState(startedAt: t0.subtract(const Duration(days: 14))),
        ),
      );
      final next = runTo(sim, s, t0.add(const Duration(minutes: 5)));
      expect(next.rivals.season.number, 2);
      expect(next.rivals.season.history, isEmpty);
    });
  });

  group('difficulty and tiers', () {
    test('rivals grow with the player, scaled by tier and setting', () {
      final s = started(level: 20);
      final velvet = config.rivals.rival('velvet_air');
      final maple = config.rivals.rival('maple_hop');
      expect(rivals.levelOf(s, velvet), 28);
      expect(rivals.levelOf(s, maple), 14);
      final blimp = sim.setDifficulty(s, 'blimp_mode', t0);
      expect(rivals.levelOf(blimp, velvet), 24);
      expect(rivals.levelOf(blimp, maple), 10);
      final dogfight = sim.setDifficulty(s, 'dogfight', t0);
      expect(rivals.levelOf(dogfight, velvet), 32);
      expect(
        () => sim.setDifficulty(s, 'nightmare', t0),
        throwsA(isA<RuleException>()),
      );
    });

    test('Blimp Mode slows rivals down; Dogfight reacts twice as hard', () {
      double gained(String difficulty) {
        final s = sim.setDifficulty(started(), difficulty, t0);
        final next = rivals.step(s, t0.add(const Duration(hours: 1)), 1);
        return next.rivals.cities.values.fold(0.0, (a, c) => a + c.total);
      }

      final cruise = gained('cruising_altitude');
      expect(gained('blimp_mode'), lessThan(cruise / 1.5 + 1));
      expect(gained('dogfight'), greaterThan(cruise));
    });

    test('starting in Antarctica moves every rival up a tier', () {
      final s = airline(
        airports: const [AirportState(cityId: 'esperanza_base')],
        level: 10,
      );
      final penguin = config.rivals.rival('penguin_post');
      expect(penguin.tier, 'puddle_jumper');
      expect(rivals.tierOf(s, penguin), 'wingman');
      expect(
        rivals.tierOf(started(), config.rivals.rival('maple_hop')),
        'puddle_jumper',
      );
    });
  });

  group('rival planes', () {
    test('fly in the player\'s regions, in range, and the same each time', () {
      final s = started();
      final t = t0.add(const Duration(minutes: 37));
      final flights = rivals.flights(s, t);
      expect(flights, isNotEmpty);
      expect(flights.length, lessThanOrEqualTo(40));
      for (final f in flights) {
        final r = config.rivals.rival(f.rivalId);
        expect(r.regionId, 'north_america');
        expect([f.fromCityId, f.toCityId], contains(r.hubCityId));
        final model = rivals.planeFor(s, r);
        expect(
          sim.rules.distanceKm(f.fromCityId, f.toCityId),
          lessThanOrEqualTo(model.rangeKm),
        );
        expect(f.departAt.isAfter(t), isFalse);
        expect(f.arriveAt.isAfter(t), isTrue);
      }
      expect(
        [for (final f in rivals.flights(s, t)) f.planeId],
        [for (final f in flights) f.planeId],
      );
      // A plane keeps flying the same leg as the clock moves.
      final f = flights.first;
      final mid = f.departAt.add(f.arriveAt.difference(f.departAt) ~/ 2);
      final again = rivals
          .flights(s, mid)
          .firstWhere((x) => x.planeId == f.planeId);
      expect((again.fromCityId, again.toCityId), (f.fromCityId, f.toCityId));
    });

    test('rivals fly freight in cargo-only planes', () {
      final s = started();
      expect(rivals.planeFor(s, config.rivals.rival('boxline')).seats, 0);
      expect(
        rivals.planeFor(s, config.rivals.rival('skysaver')).seats,
        greaterThan(0),
      );
    });
  });

  group('saving', () {
    test('rival state round-trips through JSON', () {
      final s =
          withShare(started(), 'chicago', {
            playerAirlineId: 12.5,
            'skysaver': 3,
          }, hubSince: t0).copyWith(
            rivals: RivalsState(
              difficulty: 'dogfight',
              lastStepAt: t0,
              terminals: [
                PlayerTerminal(
                  cityId: 'chicago',
                  builtAt: t0,
                  jobs: 41,
                  nodes: const {'gates': 1},
                ),
              ],
              lostTerminalCityIds: const ['dallas'],
              heatedRivalIds: const ['skysaver'],
              contracts: [
                Contract(
                  id: 'c1',
                  cityId: 'atlanta',
                  jobsToWin: 15,
                  prize: 40000,
                  startsAt: t0,
                  endsAt: t0.add(const Duration(hours: 3)),
                  rivalIds: const ['skysaver'],
                  scores: const {'skysaver': 4},
                ),
              ],
              nextContractAt: t0,
              season: SeasonState(
                number: 3,
                startedAt: t0,
                wins: const {'skysaver': 1},
                history: const [
                  SeasonResult(
                    number: 2,
                    regionId: 'north_america',
                    rank: 2,
                    difficulty: 'blimp_mode',
                    trophyRivalIds: ['maple_hop'],
                  ),
                ],
              ),
            ),
          );
      expect(GameState.fromJson(s.toJson()), s);
    });

    test('a save from before rivals loads with none', () {
      final json = started().toJson()..remove('rivals');
      final loaded = GameState.fromJson(json);
      expect(loaded.rivals.difficulty, 'cruising_altitude');
      expect(loaded.rivals.cities, isEmpty);
    });
  });
}
