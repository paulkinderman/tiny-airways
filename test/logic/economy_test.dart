import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/rng.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

void main() {
  late GameConfig config;
  late Rules rules;
  late Economy economy;

  setUpAll(() async {
    config = await shippedConfig();
    rules = Rules(config);
    economy = Economy(rules);
  });

  GameState base({int money = 1000, List<WeatherEvent> weather = const []}) =>
      airline(
        airports: const [
          AirportState(cityId: 'chicago', level: 2),
          AirportState(cityId: 'toronto'),
        ],
        planes: const [
          Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago'),
        ],
        money: money,
        weather: weather,
      );

  group('money', () {
    test('spending more than the player has is refused', () {
      final state = base(money: 500);
      expect(
        () => economy.spend(state, 501),
        throwsA(
          isA<RuleException>().having(
            (e) => e.error,
            'error',
            RuleError.notEnoughMoney,
          ),
        ),
      );
      expect(economy.spend(state, 500).player.money, 0);
    });

    test('earning adds money, network stats and airline XP', () {
      final state = economy.earn(base(money: 0), 400);
      expect(state.player.money, 400);
      expect(state.stats.moneyEarned, 400);
      expect(state.player.xp, 40); // 10% of payout
    });

    test('airline XP levels up, carrying the remainder over', () {
      // Level 1 to 2 needs 100 x 1^1.6 = 100; level 2 to 3 needs 303.
      final state = economy.grantXp(base(), 150);
      expect(state.player.level, 2);
      expect(state.player.xp, 50);
      final twice = economy.grantXp(base(), 100 + 303 + 7);
      expect(twice.player.level, 3);
      expect(twice.player.xp, 7);
    });
  });

  group('fuel', () {
    test('costs fuel burn x km', () {
      final state = base();
      final km = rules.distanceKm('chicago', 'toronto');
      expect(
        economy.fuelCost(state, state.plane('p1')!, 'chicago', 'toronto', t0),
        (0.17 * km).round(),
      );
    });

    test('Gateway tier 1 makes departures 25% cheaper', () {
      final state = base().updateAirport(
        'chicago',
        (a) => a.copyWith(pathTiers: {'gateway': 1}),
      );
      final km = rules.distanceKm('chicago', 'toronto');
      expect(
        economy.fuelCost(state, state.plane('p1')!, 'chicago', 'toronto', t0),
        (0.17 * km * 0.75).round(),
      );
    });

    test('a snowstorm makes departures 25% dearer', () {
      final state = base(
        weather: [
          WeatherEvent(
            id: 'w1',
            typeId: 'snowstorm',
            regionId: 'north_america',
            cityId: 'chicago',
            forecastAt: t0,
            startsAt: t0,
            endsAt: t0.add(const Duration(minutes: 45)),
          ),
        ],
      );
      final km = rules.distanceKm('chicago', 'toronto');
      expect(
        economy.fuelCost(state, state.plane('p1')!, 'chicago', 'toronto', t0),
        (0.17 * km * 1.25).round(),
      );
    });

    test('the jet stream saves 20% flying with it and costs 20% against', () {
      final stream = WeatherEvent(
        id: 'w1',
        typeId: 'jet_stream',
        regionId: 'north_america',
        bandLat: 42,
        eastbound: true,
        forecastAt: t0,
        startsAt: t0,
        endsAt: t0.add(const Duration(hours: 2)),
      );
      final state = base(weather: [stream]);
      final plane = state.plane('p1')!;
      final km = rules.distanceKm('chicago', 'toronto');
      // Chicago to Toronto flies east.
      expect(
        economy.fuelCost(state, plane, 'chicago', 'toronto', t0),
        (0.17 * km * 0.8).round(),
      );
      expect(
        economy.fuelCost(state, plane, 'toronto', 'chicago', t0),
        (0.17 * km * 1.2).round(),
      );
      // The airship ignores it, and burns nothing anyway.
      const airship = Plane(id: 'p2', modelId: 'cloud_nine', cityId: 'chicago');
      expect(economy.fuelCost(state, airship, 'chicago', 'toronto', t0), 0);
      // Outside the band there is no effect.
      expect(
        economy.fuelCost(state, plane, 'chicago', 'houston', t0),
        (0.17 * rules.distanceKm('chicago', 'houston')).round(),
      );
    });
  });

  group('plane stats', () {
    test('upgrades add capacity, speed and range', () {
      const plane = Plane(
        id: 'p1',
        modelId: 'pelican_p4',
        cityId: 'chicago',
        upgrades: PlaneUpgrades(capacity: 2, speed: 1, range: 3),
      );
      final stats = PlaneStats.of(rules, base(), plane);
      expect(stats.seats, 6 + 2);
      expect(stats.cargoSlots, 4);
      expect(stats.speedKmh, closeTo(420 * 1.1, 1e-9));
      expect(stats.rangeKm, closeTo(3600 * 1.45, 1e-9));
    });

    test('cargo-only planes get the capacity upgrade as slots', () {
      const plane = Plane(
        id: 'p1',
        modelId: 'hauler_h2',
        cityId: 'chicago',
        upgrades: PlaneUpgrades(capacity: 1),
      );
      final stats = PlaneStats.of(rules, base(), plane);
      expect(stats.seats, 0);
      expect(stats.cargoSlots, 5);
    });

    test('Gateway tier 2 adds 15% range for legs leaving there', () {
      final state = base().updateAirport(
        'chicago',
        (a) => a.copyWith(pathTiers: {'gateway': 2}),
      );
      final stats = PlaneStats.of(rules, state, state.plane('p1')!);
      expect(
        stats.rangeFrom(rules, state.airport('chicago')),
        closeTo(1200 * 1.15, 1e-9),
      );
      expect(stats.rangeFrom(rules, state.airport('toronto')), 1200);
    });
  });

  group('random numbers', () {
    test('the same seed replays the same sequence', () {
      final a = GameRng(7);
      final b = GameRng(7);
      expect(
        List.generate(20, (_) => a.nextUint32()),
        List.generate(20, (_) => b.nextUint32()),
      );
    });

    test('stays in range and carries its state', () {
      final rng = GameRng(123);
      for (var i = 0; i < 1000; i++) {
        final v = rng.between(3, 6);
        expect(v, inInclusiveRange(3, 6));
        expect(rng.nextDouble(), inInclusiveRange(0, 1));
      }
      final resumed = GameRng(rng.state);
      expect(resumed.nextUint32(), rng.nextUint32());
    });

    test('weighted picks follow the weights', () {
      final rng = GameRng(1);
      final counts = {'a': 0, 'b': 0, 'c': 0};
      for (var i = 0; i < 4000; i++) {
        final pick = rng.weighted([
          'a',
          'b',
          'c',
        ], (k) => {'a': 1.0, 'b': 3.0, 'c': 0.0}[k]!);
        counts[pick!] = counts[pick]! + 1;
      }
      expect(counts['c'], 0);
      expect(counts['b']! / counts['a']!, closeTo(3, 0.4));
      expect(rng.weighted(['x'], (_) => 0), isNull);
    });
  });
}
