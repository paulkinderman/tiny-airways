import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

Matcher refusedWith(RuleError error) =>
    throwsA(isA<RuleException>().having((e) => e.error, 'error', error));

void main() {
  late GameConfig config;
  late Rules rules;
  late Simulation sim;

  setUpAll(() async {
    config = await testConfig();
    rules = Rules(config);
    sim = Simulation(rules);
  });

  Duration sparrowTime(String a, String b) =>
      config.flights.realDuration(rules.distanceKm(a, b), 280);

  int sparrowFuel(String a, String b) =>
      (0.17 * rules.distanceKm(a, b)).round();

  GameState midwest({
    List<Job> board = const [],
    int money = 10000,
    List<Plane>? planes,
    int torontoLevel = 2,
    List<WeatherEvent> weather = const [],
  }) => airline(
    airports: [
      AirportState(cityId: 'chicago', level: 3, board: board),
      AirportState(cityId: 'toronto', level: torontoLevel),
      const AirportState(cityId: 'minneapolis', level: 2),
      const AirportState(cityId: 'nashville', level: 2),
      const AirportState(cityId: 'miami', level: 2),
    ],
    planes:
        planes ??
        const [Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago')],
    money: money,
    weather: weather,
  );

  WeatherEvent storm(String city, {DateTime? from, int minutes = 30}) =>
      WeatherEvent(
        id: 'storm',
        typeId: 'thunderstorm',
        regionId: 'north_america',
        cityId: city,
        forecastAt: (from ?? t0).subtract(const Duration(minutes: 10)),
        startsAt: from ?? t0,
        endsAt: (from ?? t0).add(Duration(minutes: minutes)),
      );

  group('route picker', () {
    test('quotes time, fuel and expected pay for each leg', () {
      var state = midwest(board: [job('a', 'chicago', 'toronto', payout: 250)]);
      state = sim.loadJob(state, 'p1', 'a', t0);
      final quote = sim.quote(state, 'p1', ['toronto'], t0);
      expect(quote.canDepart, isTrue);
      expect(quote.legs.single.duration, sparrowTime('chicago', 'toronto'));
      expect(quote.fuel, sparrowFuel('chicago', 'toronto'));
      expect(quote.expectedPayout, 250);
    });

    test('flight time is scheduled hours / 20, at least 30 seconds', () {
      final km = rules.distanceKm('chicago', 'toronto');
      expect(
        sparrowTime('chicago', 'toronto').inSeconds,
        (km / 280 * 3600 / 20).round(),
      );
      expect(config.flights.realDuration(10, 820), const Duration(seconds: 30));
    });

    test('lists only owned airports in range that allow the plane', () {
      // Miami is beyond a Sparrow's 1,200 km from Chicago.
      expect(
        sim.flights.reachable(midwest(), 'p1', t0),
        unorderedEquals(['toronto', 'minneapolis', 'nashville']),
      );
    });

    test(
      'refuses legs that are out of range, unowned, too small or closed',
      () {
        final state = midwest(
          planes: const [
            Plane(id: 'p1', modelId: 'pelican_p4', cityId: 'chicago'),
          ],
        );
        List<RuleError> problems(List<String> stops) =>
            sim.quote(state, 'p1', stops, t0).problems;
        expect(problems(['denver']), contains(RuleError.notOwned));
        // Toronto is level 2: Small planes only.
        expect(problems(['toronto']), contains(RuleError.planeTooBig));
        expect(
          sim.quote(midwest(weather: [storm('nashville')]), 'p1', [
            'nashville',
          ], t0).problems,
          contains(RuleError.airportClosed),
        );
        expect(problems(['chicago']), contains(RuleError.sameCity));
        expect(problems([]), contains(RuleError.noStops));
        expect(
          sim.quote(midwest(), 'p1', ['miami'], t0).problems,
          contains(RuleError.outOfRange),
        );
      },
    );

    test('a plane cannot leave without fuel money', () {
      final state = midwest(money: sparrowFuel('chicago', 'toronto') - 1);
      expect(
        () => sim.depart(state, 'p1', ['toronto'], t0),
        refusedWith(RuleError.notEnoughMoney),
      );
    });

    test('a plane cannot take off from a closed airport', () {
      final state = midwest(weather: [storm('chicago')]);
      expect(
        () => sim.depart(state, 'p1', ['toronto'], t0),
        refusedWith(RuleError.airportClosed),
      );
    });

    test('a crew problem stops departure', () {
      final noPilot = Simulation(Rules(config, crew: const _NoPilot()));
      expect(
        () => noPilot.depart(midwest(), 'p1', ['toronto'], t0),
        refusedWith(RuleError.crewMissing),
      );
    });
  });

  group('a flight', () {
    test(
      'charges fuel at departure, flies in real time and pays on landing',
      () {
        var state = midwest(
          board: [
            job('a', 'chicago', 'toronto', payout: 250),
            cargo('c', 'chicago', 'minneapolis'),
          ],
        );
        state = sim.loadJob(state, 'p1', 'a', t0);
        state = sim.loadJob(state, 'p1', 'c', t0);
        state = sim.depart(state, 'p1', ['toronto'], t0);
        final fuel = sparrowFuel('chicago', 'toronto');
        expect(state.player.money, 10000 - fuel);
        expect(state.stats.fuelSpent, fuel);
        final plane = state.plane('p1')!;
        expect(plane.status, PlaneStatus.flying);
        expect(plane.leg!.arriveAt, t0.add(sparrowTime('chicago', 'toronto')));

        final arrive = plane.leg!.arriveAt;
        final before = runTo(
          sim,
          state,
          arrive.subtract(const Duration(seconds: 1)),
        );
        expect(before.plane('p1')!.status, PlaneStatus.flying);

        final (after, report) = sim.advance(state, arrive);
        final landed = after.plane('p1')!;
        expect(landed.status, PlaneStatus.parked);
        expect(landed.cityId, 'toronto');
        // The crate for Minneapolis stays aboard.
        expect(landed.load.map((j) => j.id), ['c']);
        expect(after.player.money, 10000 - fuel + 250);
        expect(after.player.xp, 25);
        expect(after.stats.jobsDelivered, 1);
        expect(after.stats.legsFlown, 1);
        expect(
          after.stats.kmFlown,
          closeTo(rules.distanceKm('chicago', 'toronto'), 1e-6),
        );
        expect(after.stats.busiestRoute, ('chicago', 'toronto'));
        expect(report.moneyEarned, 250);
        expect(report.landedPlaneIds, ['p1']);
      },
    );

    test('a full charter pays every passenger +25%', () {
      var state = midwest(
        board: [
          job('a', 'chicago', 'toronto', payout: 200),
          job('b', 'chicago', 'toronto', payout: 100),
        ],
      );
      state = sim.fillTo(state, 'p1', 'toronto', t0);
      expect(
        sim.loading.summary(state, state.plane('p1')!, t0).isCharter,
        isTrue,
      );
      expect(sim.quote(state, 'p1', ['toronto'], t0).expectedPayout, 250 + 125);
      state = sim.depart(state, 'p1', ['toronto'], t0);
      final after = runTo(sim, state, t0.add(const Duration(hours: 1)));
      expect(
        after.player.money,
        10000 - sparrowFuel('chicago', 'toronto') + 375,
      );
    });

    test('passengers split between cities get no charter bonus', () {
      var state = midwest(
        board: [
          job('a', 'chicago', 'toronto', payout: 200),
          job('b', 'chicago', 'minneapolis', payout: 100),
        ],
      );
      state = sim.loadJob(state, 'p1', 'a', t0);
      state = sim.loadJob(state, 'p1', 'b', t0);
      expect(sim.quote(state, 'p1', ['toronto'], t0).expectedPayout, 200);
    });

    test('a full hold pays every crate +15%, and both bonuses can stack', () {
      var state = midwest(
        board: [
          job('a', 'chicago', 'toronto', payout: 100),
          job('b', 'chicago', 'toronto', payout: 100),
          cargo('c', 'chicago', 'toronto', payout: 200),
        ],
      );
      state = sim.fillTo(state, 'p1', 'toronto', t0);
      final load = sim.loading.summary(state, state.plane('p1')!, t0);
      expect(load.isCharter && load.isFullHold, isTrue);
      expect(
        sim.quote(state, 'p1', ['toronto'], t0).expectedPayout,
        125 + 125 + 230,
      );
    });

    test('a multi-stop trip lands at each stop and flies on', () {
      var state = midwest(
        board: [
          job('a', 'chicago', 'minneapolis', payout: 120),
          job('b', 'chicago', 'toronto', payout: 300),
        ],
      );
      state = sim.loadJob(state, 'p1', 'a', t0);
      state = sim.loadJob(state, 'p1', 'b', t0);
      final quote = sim.quote(state, 'p1', ['minneapolis', 'toronto'], t0);
      expect(quote.legs.map((l) => l.toCityId), ['minneapolis', 'toronto']);
      expect(
        quote.fuel,
        sparrowFuel('chicago', 'minneapolis') +
            sparrowFuel('minneapolis', 'toronto'),
      );
      state = sim.depart(state, 'p1', ['minneapolis', 'toronto'], t0);
      expect(state.player.money, 10000 - quote.fuel);

      final firstStop = t0.add(sparrowTime('chicago', 'minneapolis'));
      final mid = runTo(sim, state, firstStop);
      final plane = mid.plane('p1')!;
      expect(plane.status, PlaneStatus.flying);
      expect(plane.leg!.fromCityId, 'minneapolis');
      expect(plane.leg!.toCityId, 'toronto');
      expect(plane.tripStops, 1);
      expect(plane.load.map((j) => j.id), ['b']);
      expect(mid.player.money, 10000 - quote.fuel + 120);

      final end = runTo(
        sim,
        state,
        firstStop.add(sparrowTime('minneapolis', 'toronto')),
      );
      expect(end.plane('p1')!.status, PlaneStatus.parked);
      expect(end.plane('p1')!.cityId, 'toronto');
      expect(end.player.money, 10000 - quote.fuel + 420);
      expect(end.stats.legsFlown, 2);
    });

    group('picking up at stops', () {
      GameState withMinneapolisBoard(GameState s, List<Job> board) =>
          s.updateAirport('minneapolis', (a) => a.copyWith(board: board));

      test('a plane picks up jobs for later stops when pickups are on', () {
        var state = withMinneapolisBoard(
          midwest(board: [job('a', 'chicago', 'minneapolis', payout: 120)]),
          [
            job('m1', 'minneapolis', 'toronto', payout: 200),
            job('m2', 'minneapolis', 'miami', payout: 900),
            job('m3', 'minneapolis', 'chicago', payout: 500),
          ],
        );
        state = sim.loadJob(state, 'p1', 'a', t0);
        final stops = ['minneapolis', 'toronto'];
        final quote = sim.quote(state, 'p1', stops, t0, pickUp: true);
        expect(quote.pickupsAt, [1, 0]);
        expect(quote.pickups, 1);
        expect(quote.pickupPayout, greaterThan(0));
        expect(
          quote.expectedPayout,
          sim.quote(state, 'p1', stops, t0).expectedPayout + quote.pickupPayout,
        );

        state = sim.depart(state, 'p1', stops, t0, pickUp: true);
        expect(state.plane('p1')!.pickUpAtStops, isTrue);
        final firstStop = t0.add(sparrowTime('chicago', 'minneapolis'));
        // Boards turn over while it flies; put the jobs back just before
        // it lands.
        final justBefore = firstStop.subtract(const Duration(seconds: 1));
        state = withMinneapolisBoard(runTo(sim, state, justBefore), [
          job('m1', 'minneapolis', 'toronto', payout: 200),
          job('m2', 'minneapolis', 'miami', payout: 900),
        ]);
        final mid = runTo(sim, state, firstStop);
        final plane = mid.plane('p1')!;
        expect(plane.status, PlaneStatus.flying);
        expect(plane.load.map((j) => j.id), ['m1']);
        expect(
          mid.airport('minneapolis')!.board.map((j) => j.id),
          isNot(contains('m1')),
        );

        final end = runTo(
          sim,
          mid,
          firstStop.add(sparrowTime('minneapolis', 'toronto')),
        );
        final parked = end.plane('p1')!;
        expect(parked.status, PlaneStatus.parked);
        expect(parked.load, isEmpty);
        expect(parked.pickUpAtStops, isFalse);
        expect(end.stats.jobsDelivered, 2);
      });

      test('without pickups, jobs at stops stay on the board', () {
        var state = withMinneapolisBoard(midwest(), [
          job('m1', 'minneapolis', 'toronto', payout: 200),
        ]);
        final stops = ['minneapolis', 'toronto'];
        expect(sim.quote(state, 'p1', stops, t0).pickups, 0);
        state = sim.depart(state, 'p1', stops, t0);
        final firstStop = t0.add(sparrowTime('chicago', 'minneapolis'));
        state = withMinneapolisBoard(
          runTo(sim, state, firstStop.subtract(const Duration(seconds: 1))),
          [job('m1', 'minneapolis', 'toronto', payout: 200)],
        );
        final mid = runTo(sim, state, firstStop);
        expect(mid.plane('p1')!.load, isEmpty);
      });

      test('pickups fill only the seats left free', () {
        final seats = PlaneStats.of(
          rules,
          midwest(),
          midwest().plane('p1')!,
        ).seats;
        final board = [
          for (var i = 0; i < seats + 2; i++)
            job('m$i', 'minneapolis', 'toronto', payout: 100 + i),
        ];
        var state = withMinneapolisBoard(midwest(), board);
        final stops = ['minneapolis', 'toronto'];
        expect(
          sim.quote(state, 'p1', stops, t0, pickUp: true).pickupsAt.first,
          seats,
        );
        state = sim.depart(state, 'p1', stops, t0, pickUp: true);
        final firstStop = t0.add(sparrowTime('chicago', 'minneapolis'));
        state = withMinneapolisBoard(
          runTo(sim, state, firstStop.subtract(const Duration(seconds: 1))),
          board,
        );
        final mid = runTo(sim, state, firstStop);
        final load = mid.plane('p1')!.load;
        expect(load, hasLength(seats));
        // Best-paying first: the two cheapest stay behind.
        expect(load.map((j) => j.id), isNot(contains('m0')));
        expect(load.map((j) => j.id), isNot(contains('m1')));
      });
    });

    test('planes that land wait; nothing re-dispatches them', () {
      var state = sim.depart(midwest(), 'p1', ['toronto'], t0);
      state = runTo(sim, state, t0.add(const Duration(days: 2)));
      expect(state.plane('p1')!.status, PlaneStatus.parked);
      expect(state.plane('p1')!.cityId, 'toronto');
      expect(state.stats.legsFlown, 1);
    });
  });

  group('layovers', () {
    test('a job dropped on a layover waits there, then pays its full fare on delivery', () {
      var state = midwest(board: [job('a', 'chicago', 'toronto', payout: 400)]);
      state = sim.loadJob(state, 'p1', 'a', t0, dropAtCityId: 'minneapolis');
      expect(sim.loading.layoversUsed(state, 'minneapolis'), 1);
      state = sim.depart(state, 'p1', ['minneapolis'], t0);
      final landed = t0.add(sparrowTime('chicago', 'minneapolis'));
      state = runTo(sim, state, landed);
      expect(state.plane('p1')!.load, isEmpty);
      final waiting = state
          .airport('minneapolis')!
          .board
          .singleWhere((j) => j.id == 'a');
      expect(waiting.connectingSince, landed);
      expect(waiting.bonusPct, 0);
      expect(sim.loading.layoversUsed(state, 'minneapolis'), 1);
      final money = state.player.money;

      // A board rotation does not take it away.
      state = runTo(sim, state, landed.add(const Duration(minutes: 6)));
      expect(
        state.airport('minneapolis')!.board.map((j) => j.id),
        contains('a'),
      );

      final now = landed.add(const Duration(minutes: 6));
      state = sim.loadJob(state, 'p1', 'a', now);
      expect(sim.loading.layoversUsed(state, 'minneapolis'), 0);
      state = sim.depart(state, 'p1', ['toronto'], now);
      state = runTo(sim, state, now.add(const Duration(hours: 1)));
      expect(
        state.player.money,
        money - sparrowFuel('minneapolis', 'toronto') + 400,
      );
    });

    test('an airport holds as many layovers as its slots, and the Layovers path adds more', () {
      final base = sim.loading.layoverSlots(midwest(), 'minneapolis');
      // All but one slot is taken by jobs already waiting there.
      var state =
          midwest(
            board: [
              job('a', 'chicago', 'toronto', payout: 100),
              job('b', 'chicago', 'toronto', payout: 100),
            ],
          ).updateAirport(
            'minneapolis',
            (a) => a.copyWith(
              board: [
                for (var i = 0; i < base - 1; i++)
                  job('w$i', 'nashville', 'toronto', connectingSince: t0),
              ],
            ),
          );
      state = sim.loadJob(state, 'p1', 'a', t0, dropAtCityId: 'minneapolis');
      expect(sim.loading.freeLayoverSlots(state, 'minneapolis'), 0);
      expect(
        () => sim.loadJob(state, 'p1', 'b', t0, dropAtCityId: 'minneapolis'),
        refusedWith(RuleError.layoverFull),
      );

      final upgraded = state.updateAirport(
        'minneapolis',
        (a) => a.copyWith(pathTiers: {'transfer': 1}),
      );
      expect(sim.loading.layoverSlots(upgraded, 'minneapolis'), base + 2);
      final loaded = sim.loadJob(
        upgraded,
        'p1',
        'b',
        t0,
        dropAtCityId: 'minneapolis',
      );
      expect(loaded.plane('p1')!.load, hasLength(2));
    });
  });

  group('special jobs on the way', () {
    test('a VIP who lands after the deadline pays nothing', () {
      var state = midwest(
        board: [
          job(
            'v',
            'chicago',
            'toronto',
            kind: JobKind.vip,
            payout: 900,
            deadline: t0.add(const Duration(minutes: 5)),
          ),
        ],
      );
      state = sim.loadJob(state, 'p1', 'v', t0);
      expect(sim.quote(state, 'p1', ['toronto'], t0).expectedPayout, 0);
      state = sim.depart(state, 'p1', ['toronto'], t0);
      final (after, report) = sim.advance(
        state,
        t0.add(const Duration(hours: 1)),
      );
      expect(after.player.money, 10000 - sparrowFuel('chicago', 'toronto'));
      expect(after.stats.jobsLate, 1);
      expect(report.jobsLate, 1);
    });

    test('rush jobs left behind leave the board when a plane departs', () {
      var state = midwest(
        board: [
          job('r', 'chicago', 'toronto', kind: JobKind.rush),
          job('n', 'chicago', 'toronto'),
        ],
      );
      state = sim.depart(state, 'p1', ['toronto'], t0);
      expect(state.airport('chicago')!.board.map((j) => j.id), ['n']);
    });
  });

  group('gates', () {
    test('a plane landing at a full airport holds until a gate opens', () {
      // Toronto is level 1 here: one gate, taken by p2.
      var state = midwest(
        torontoLevel: 1,
        planes: const [
          Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago'),
          Plane(id: 'p2', modelId: 'sparrow_s1', cityId: 'toronto'),
        ],
      );
      state = sim.depart(state, 'p1', ['toronto'], t0);
      final arrive = t0.add(sparrowTime('chicago', 'toronto'));
      state = runTo(sim, state, arrive.add(const Duration(minutes: 3)));
      final holding = state.plane('p1')!;
      expect(holding.status, PlaneStatus.holding);
      expect(holding.holdingSince, arrive);
      expect(sim.flights.freeGates(state, 'toronto'), 0);

      final later = arrive.add(const Duration(minutes: 3));
      state = sim.depart(state, 'p2', ['chicago'], later);
      expect(state.plane('p1')!.status, PlaneStatus.parked);
      expect(state.plane('p1')!.cityId, 'toronto');
    });
  });

  group('weather on arrival', () {
    test(
      'a thunderstorm diverts planes to the nearest owned airport, jobs aboard',
      () {
        var state = midwest(
          board: [job('a', 'chicago', 'toronto', payout: 250)],
        );
        state = sim.loadJob(state, 'p1', 'a', t0);
        state = sim.depart(state, 'p1', ['toronto'], t0);
        final arrive = t0.add(sparrowTime('chicago', 'toronto'));
        state = state.copyWith(
          weather: state.weather.copyWith(
            events: [
              storm(
                'toronto',
                from: arrive.subtract(const Duration(minutes: 1)),
              ),
            ],
          ),
        );
        final (diverted, report) = sim.advance(state, arrive);
        final plane = diverted.plane('p1')!;
        expect(plane.status, PlaneStatus.flying);
        expect(plane.leg!.diverted, isTrue);
        expect(plane.leg!.fromCityId, 'toronto');
        // Chicago is the nearest owned airport to Toronto.
        expect(plane.leg!.toCityId, 'chicago');
        expect(report.diversions.single.toCityId, 'chicago');

        final parked = runTo(
          sim,
          diverted,
          arrive.add(const Duration(hours: 1)),
        );
        expect(parked.plane('p1')!.cityId, 'chicago');
        expect(parked.plane('p1')!.load.single.id, 'a');
      },
    );

    test('with nowhere to divert, a plane holds until the storm clears', () {
      var state = airline(
        airports: const [
          AirportState(cityId: 'chicago', level: 2),
          AirportState(cityId: 'toronto'),
        ],
        planes: const [
          Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'toronto'),
        ],
      );
      state = sim.depart(state, 'p1', ['chicago'], t0);
      final arrive = t0.add(sparrowTime('chicago', 'toronto'));
      // Toronto is also closed, so there's nowhere else to go.
      state = state.copyWith(
        weather: state.weather.copyWith(
          events: [
            storm('chicago', from: arrive.subtract(const Duration(minutes: 1))),
            WeatherEvent(
              id: 'storm2',
              typeId: 'thunderstorm',
              regionId: 'north_america',
              cityId: 'toronto',
              forecastAt: t0,
              startsAt: arrive.subtract(const Duration(minutes: 1)),
              endsAt: arrive.add(const Duration(hours: 2)),
            ),
          ],
        ),
      );
      final holding = runTo(
        sim,
        state,
        arrive.add(const Duration(minutes: 10)),
      );
      expect(holding.plane('p1')!.status, PlaneStatus.holding);
      final clear = arrive.add(const Duration(minutes: 29));
      final landed = runTo(sim, state, clear);
      expect(landed.plane('p1')!.status, PlaneStatus.parked);
      expect(landed.plane('p1')!.cityId, 'chicago');
    });

    test('fog turns away captains below level 4', () {
      final fog = WeatherEvent(
        id: 'fog',
        typeId: 'fog',
        regionId: 'north_america',
        cityId: 'toronto',
        forecastAt: t0,
        startsAt: t0,
        endsAt: t0.add(const Duration(minutes: 30)),
      );
      final state = sim.depart(midwest(weather: [fog]), 'p1', ['toronto'], t0);
      final arrive = t0.add(sparrowTime('chicago', 'toronto'));
      final rookie = runTo(sim, state, arrive);
      expect(rookie.plane('p1')!.leg!.diverted, isTrue);

      for (final crew in const [
        TestCrew(captain: 4),
        TestCrew(fogLanding: true),
      ]) {
        final veteran = Simulation(Rules(config, crew: crew));
        final landed = runTo(veteran, state, arrive);
        expect(landed.plane('p1')!.status, PlaneStatus.parked);
        expect(landed.plane('p1')!.cityId, 'toronto');
      }
    });
  });
}

class _NoPilot extends NoCrew {
  const _NoPilot();

  @override
  String? departureProblem(GameState state, Plane plane) => 'needs a pilot';
}
