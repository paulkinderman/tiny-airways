import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/save/save_repository.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

void main() {
  late GameConfig config;
  late Rules rules;
  late Simulation sim;

  setUpAll(() async {
    config = await testConfig();
    rules = Rules(config);
    sim = Simulation(rules);
  });

  GameState fresh() => GameState.newGame(now: t0, startingMoney: 2500);

  group('starting an airline', () {
    test(
      'sets up the home airport, a free neighbour, a Sparrow and full boards',
      () {
        final state = sim.startAirline(fresh(), 'chicago', t0);
        expect(state.hasStarted, isTrue);
        expect(state.homeCityId, 'chicago');
        expect(state.player.money, 2500);
        expect(state.airports, hasLength(2));
        final home = state.airport('chicago')!;
        expect(home.level, 2);
        final free = state.airports[1];
        expect(free.level, 1);
        // The nearest city at least the minimum job distance away.
        expect(free.cityId, 'minneapolis');
        expect(state.planes.single.modelId, 'sparrow_s1');
        expect(state.planes.single.cityId, 'chicago');
        expect(home.board, hasLength(9));
        expect(free.board, hasLength(6));
        expect(home.board.every((j) => j.destCityId == free.cityId), isTrue);
        expect(state.weather.nextEventAt.keys, ['north_america']);
        expect(
          () => sim.startAirline(state, 'toronto', t0),
          throwsA(isA<RuleException>()),
        );
      },
    );

    test('the free airport is always reachable by the starting plane', () {
      for (final city in config.world.cities) {
        final state = sim.startAirline(fresh(), city.id, t0);
        final other = state.airports[1].cityId;
        if (rules.distanceKm(city.id, other) <= 1200) continue;
        // Only remote places with nothing in range (such as the South Pole)
        // fall back to the nearest city in their region.
        expect(
          config.world.cities.where(
            (c) =>
                c.id != city.id &&
                rules.distanceKm(city.id, c.id) <= 1200 &&
                rules.distanceKm(city.id, c.id) >= config.jobs.minJobDistanceKm,
          ),
          isEmpty,
          reason: city.id,
        );
      }
    });

    test('the same start replays identically', () {
      final a = sim.startAirline(fresh(), 'paris', t0);
      final b = sim.startAirline(fresh(), 'paris', t0);
      expect(a, b);
      final later = t0.add(const Duration(hours: 5));
      expect(runTo(sim, a, later), runTo(sim, b, later));
    });
  });

  group('offline catch-up', () {
    GameState twoPlanes() => airline(
      airports: [
        AirportState(
          cityId: 'chicago',
          level: 3,
          board: [
            job('a', 'chicago', 'toronto', payout: 200),
            job('b', 'chicago', 'minneapolis', payout: 150),
          ],
        ),
        const AirportState(cityId: 'toronto', level: 2),
        const AirportState(cityId: 'minneapolis', level: 2),
      ],
      planes: const [
        Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago'),
        Plane(id: 'p2', modelId: 'sparrow_s1', cityId: 'chicago'),
      ],
    );

    test('resolves every landing while away and reports them', () {
      var state = twoPlanes();
      state = sim.loadJob(state, 'p1', 'a', t0);
      state = sim.loadJob(state, 'p2', 'b', t0);
      state = sim.depart(state, 'p1', ['toronto'], t0);
      state = sim.depart(state, 'p2', ['minneapolis'], t0);
      final money = state.player.money;

      final (after, report) = sim.advance(
        state,
        t0.add(const Duration(hours: 8)),
      );
      expect(after.player.money, money + 350);
      expect(report.moneyEarned, 350);
      expect(report.jobsDelivered, 2);
      // Minneapolis is closer, so p2 lands first.
      expect(report.landedPlaneIds, ['p2', 'p1']);
      expect(after.planes.every((p) => p.status == PlaneStatus.parked), isTrue);
      expect(after.simulatedTo, t0.add(const Duration(hours: 8)));
    });

    test('weather keeps happening while away', () {
      final state = sim.startAirline(fresh(), 'chicago', t0);
      final (after, report) = sim.advance(
        state,
        t0.add(const Duration(hours: 6)),
      );
      // One event every 30 to 60 minutes.
      expect(report.newWeatherIds.length, inInclusiveRange(5, 12));
      expect(
        after.weather.nextEventAt['north_america']!.isAfter(
          t0.add(const Duration(hours: 6)),
        ),
        isTrue,
      );
    });

    test('a clock set backwards holds everything until it catches up', () {
      var state = sim.depart(twoPlanes(), 'p1', ['toronto'], t0);
      state = runTo(sim, state, t0.add(const Duration(minutes: 2)));
      final (back, report) = sim.advance(
        state,
        t0.subtract(const Duration(hours: 1)),
      );
      expect(back, state);
      expect(report.isEmpty, isTrue);
      // Actions taken while the clock is behind happen at the last known time.
      final departed = sim.depart(state, 'p2', ['minneapolis'], t0);
      expect(
        departed.plane('p2')!.leg!.departAt,
        t0.add(const Duration(minutes: 2)),
      );
    });

    test('a big jump forward is fine', () {
      final state = sim.startAirline(fresh(), 'chicago', t0);
      final after = runTo(sim, state, t0.add(const Duration(days: 30)));
      expect(after.simulatedTo, t0.add(const Duration(days: 30)));
      expect(after.airport('chicago')!.board, hasLength(9));
    });

    test('a running game survives a save and reload', () async {
      var state = sim.startAirline(fresh(), 'chicago', t0);
      final first = state.airport('chicago')!.board.first;
      state = sim.loadJob(state, 'p${1}', first.id, t0);
      state = sim.depart(state, state.planes.single.id, [first.destCityId], t0);
      state = runTo(sim, state, t0.add(const Duration(minutes: 1)));

      final repo = SaveRepository(
        storage: MemorySaveStorage(),
        clock: FakeClock(t0),
      );
      await repo.save(state);
      final loaded = (await repo.load()).state!;
      expect(loaded, state);
      final later = t0.add(const Duration(hours: 3));
      expect(runTo(sim, loaded, later), runTo(sim, state, later));
    });
  });

  group('weather', () {
    test('each continent with an airport gets an event every 30 to 60 minutes, forecast 10 minutes ahead', () {
      var state = sim.startAirline(fresh(), 'chicago', t0);
      final firstStart = state.weather.nextEventAt['north_america']!;
      expect(
        firstStart.difference(t0).inMinutes,
        inInclusiveRange(
          config.weather.minIntervalMinutes,
          config.weather.maxIntervalMinutes,
        ),
      );
      state = runTo(
        sim,
        state,
        firstStart.subtract(const Duration(minutes: 11)),
      );
      expect(state.weather.events, isEmpty);
      state = runTo(
        sim,
        state,
        firstStart.subtract(const Duration(minutes: 10)),
      );
      final event = state.weather.events.single;
      expect(event.startsAt, firstStart);
      expect(
        event.forecastAt,
        firstStart.subtract(const Duration(minutes: 10)),
      );
      expect(event.regionId, 'north_america');
      final kind = config.weather.events.firstWhere(
        (e) => e.id == event.typeId,
      );
      expect(
        event.endsAt.difference(event.startsAt).inMinutes,
        inInclusiveRange(kind.minMinutes, kind.maxMinutes),
      );
      if (kind.area == 'band') {
        expect(event.bandLat, isNotNull);
      } else {
        expect(['chicago', 'minneapolis'], contains(event.cityId));
      }
    });

    test('events are removed once they are over', () {
      var state = sim.startAirline(fresh(), 'chicago', t0);
      state = runTo(sim, state, t0.add(const Duration(hours: 12)));
      final weather = WeatherRules(rules);
      for (final e in state.weather.events) {
        expect(weather.finishedAt(e).isAfter(state.simulatedTo), isTrue);
      }
    });

    test('when a thunderstorm clears, the board refills with jobs paying +50% for 15 minutes', () {
      final clears = t0.add(const Duration(minutes: 7));
      final state = airline(
        airports: const [
          AirportState(cityId: 'chicago', level: 2),
          AirportState(cityId: 'toronto'),
        ],
        weather: [
          WeatherEvent(
            id: 'storm',
            typeId: 'thunderstorm',
            regionId: 'north_america',
            cityId: 'chicago',
            forecastAt: t0,
            startsAt: t0,
            endsAt: clears,
          ),
        ],
      );
      final after = runTo(sim, state, clears);
      final board = after.airport('chicago')!.board;
      expect(board, hasLength(9));
      final km = rules.distanceKm('chicago', 'toronto');
      final pax = board.firstWhere((j) => j.type == JobType.passenger);
      expect(pax.createdAt, clears);
      expect(pax.payout, (0.35 * km * 1.5).round());

      // After the rush window, new jobs pay normally again.
      final calm = runTo(sim, after, clears.add(const Duration(minutes: 20)));
      final later = calm
          .airport('chicago')!
          .board
          .firstWhere((j) => j.type == JobType.passenger);
      expect(later.payout, (0.35 * km).round());
    });

    test('jobs appearing in fog, snow or heat pay their weather bonus', () {
      WeatherEvent event(String type) => WeatherEvent(
        id: type,
        typeId: type,
        regionId: 'north_america',
        cityId: 'chicago',
        forecastAt: t0,
        startsAt: t0,
        endsAt: t0.add(const Duration(hours: 1)),
      );
      final weather = WeatherRules(rules);
      GameState with_(String type) => airline(
        airports: const [
          AirportState(cityId: 'chicago'),
          AirportState(cityId: 'toronto'),
        ],
        weather: [event(type)],
      );
      expect(
        weather.jobPayPct(with_('fog'), 'chicago', JobType.passenger, t0),
        25,
      );
      expect(
        weather.jobPayPct(with_('snowstorm'), 'chicago', JobType.passenger, t0),
        25,
      );
      // Snowstorms cover a cluster of nearby cities.
      expect(
        weather.jobPayPct(with_('snowstorm'), 'minneapolis', JobType.cargo, t0),
        25,
      );
      expect(
        weather.jobPayPct(with_('snowstorm'), 'miami', JobType.cargo, t0),
        0,
      );
      expect(
        weather.jobPayPct(with_('heat_wave'), 'chicago', JobType.cargo, t0),
        20,
      );
      expect(
        weather.jobPayPct(with_('heat_wave'), 'chicago', JobType.passenger, t0),
        0,
      );
      expect(weather.isClosed(with_('thunderstorm'), 'chicago', t0), isTrue);
      expect(weather.isClosed(with_('thunderstorm'), 'toronto', t0), isFalse);
    });
  });
}
