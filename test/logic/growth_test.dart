import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

void main() {
  late GameConfig config;
  late Simulation sim;
  late Growth growth;

  setUpAll(() async {
    config = await testConfig();
    sim = Simulation(Rules(config));
    growth = Growth(sim.rules);
  });

  // Chicago (size 4, level 2 home) and Toronto (size 4, level 1).
  GameState base({int money = 100000, int level = 1, List<Plane>? planes}) =>
      airline(
        airports: const [
          AirportState(cityId: 'chicago', level: 2),
          AirportState(cityId: 'toronto'),
        ],
        planes:
            planes ??
            const [Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago')],
        money: money,
        level: level,
      );

  Matcher refused(RuleError error) =>
      throwsA(isA<RuleException>().having((e) => e.error, 'error', error));

  group('hangar', () {
    test('buying a plane charges its price and parks it at home', () {
      final state = growth.buyPlane(base(), 'hauler_h2');
      expect(state.player.money, 100000 - 3000);
      final plane = state.plane('p1000')!;
      expect(plane.modelId, 'hauler_h2');
      expect(plane.cityId, 'chicago');
      expect(plane.status, PlaneStatus.parked);
      expect(state.nextId, 1001);
    });

    test('a plane unlocks at its own level and its class level', () {
      expect(
        () => growth.buyPlane(base(), 'kestrel_k3'),
        refused(RuleError.levelTooLow),
      );
      expect(
        growth.buyPlane(base(level: 3), 'kestrel_k3').planes,
        hasLength(2),
      );
      final pelican = config.planes.model('pelican_p4');
      final albatross = config.planes.model('albatross_l6');
      expect(growth.unlockLevel(pelican), 5);
      expect(growth.unlockLevel(albatross), 20);
      expect(growth.isUnlocked(base(level: 4), pelican), isFalse);
    });

    test('special planes are not for sale', () {
      expect(
        () => growth.buyPlane(base(level: 60), 'cloud_nine'),
        refused(RuleError.notForSale),
      );
    });

    test('the fleet has no size cap', () {
      var state = base(money: 1000000);
      for (var i = 0; i < 9; i++) {
        state = growth.buyPlane(state, 'sparrow_s1');
      }
      expect(state.planes, hasLength(10));
    });

    test('a new plane goes to the nearest airport with a gate that fits', () {
      // Chicago (level 2) has 2 gates; fill both.
      final full = base(
        planes: const [
          Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago'),
          Plane(id: 'p2', modelId: 'sparrow_s1', cityId: 'chicago'),
        ],
      );
      expect(
        growth.buyPlane(full, 'sparrow_s1').plane('p1000')!.cityId,
        'toronto',
      );

      // A Medium plane needs a level 3 airport.
      expect(
        () => growth.buyPlane(base(level: 5), 'pelican_p4'),
        refused(RuleError.noGate),
      );
      final big = base(level: 5)
          .updateAirport('toronto', (a) => a.copyWith(level: 3));
      expect(
        growth.buyPlane(big, 'pelican_p4').plane('p1000')!.cityId,
        'toronto',
      );
    });

    test('the same model can be bought again and again', () {
      var state = base(level: 5);
      state = growth.buyPlane(state, 'sparrow_s1');
      state = growth.buyPlane(state, 'sparrow_s1');
      state = growth.buyPlane(state, 'sparrow_s1');
      expect(
        state.planes.where((p) => p.modelId == 'sparrow_s1'),
        hasLength(4),
      );
      expect(growth.ownedCount(state, 'sparrow_s1'), 4);
      expect({for (final p in state.planes) p.id}, hasLength(4));
    });

    test('with every gate taken, a new plane circles home until one frees '
        'up', () {
      final full = base(
        planes: const [
          Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago'),
          Plane(id: 'p2', modelId: 'sparrow_s1', cityId: 'chicago'),
          Plane(id: 'p3', modelId: 'sparrow_s1', cityId: 'toronto'),
        ],
        level: 5,
      );
      final model = config.planes.model('sparrow_s1');
      expect(growth.buyPlaneProblem(full, model), isNull);
      expect(growth.deliveryWaitsForGate(full, model), isTrue);
      final bought = growth.buyPlane(full, 'sparrow_s1', full.simulatedTo);
      final plane = bought.plane('p1000')!;
      expect(plane.status, PlaneStatus.holding);
      expect(plane.cityId, 'chicago');
      expect(plane.leg!.isDelivery, isTrue);

      // Still full: it keeps circling.
      final still = sim.flights.landHolding(
        bought,
        null,
        full.simulatedTo,
        SimReport(),
      );
      expect(still.plane('p1000')!.status, PlaneStatus.holding);

      // A gate frees up at Chicago: it pulls in without counting a leg.
      final freed = bought.copyWith(
        planes: [
          for (final p in bought.planes)
            if (p.id != 'p2') p,
        ],
      );
      final landed = sim.flights.landHolding(
        freed,
        'chicago',
        full.simulatedTo,
        SimReport(),
      );
      final parked = landed.plane('p1000')!;
      expect(parked.status, PlaneStatus.parked);
      expect(parked.cityId, 'chicago');
      expect(parked.leg, isNull);
      expect(landed.stats.legsFlown, freed.stats.legsFlown);
      expect(landed.player.money, freed.player.money);

      // It survives a save round trip while circling.
      expect(
        GameState.fromJson(bought.toJson()).plane('p1000')!.leg!.isDelivery,
        isTrue,
      );
    });

    test('money never goes negative', () {
      expect(
        () => growth.buyPlane(base(money: 2999), 'hauler_h2'),
        refused(RuleError.notEnoughMoney),
      );
    });
  });

  group('plane upgrades', () {
    test('each level costs more and stops at 3', () {
      var state = base();
      final costs = <int>[];
      for (var i = 0; i < 3; i++) {
        costs.add(
          growth.planeUpgradeCost(state.plane('p1')!, PlaneTrack.speed)!,
        );
        state = growth.upgradePlane(state, 'p1', PlaneTrack.speed);
      }
      expect(costs, [300, 600, 1200]);
      expect(state.player.money, 100000 - 2100);
      expect(state.plane('p1')!.upgrades.speed, 3);
      expect(
        () => growth.upgradePlane(state, 'p1', PlaneTrack.speed),
        refused(RuleError.maxLevel),
      );
    });

    test('upgrades change the plane\'s stats', () {
      var state = growth.upgradePlane(base(), 'p1', PlaneTrack.capacity);
      state = growth.upgradePlane(state, 'p1', PlaneTrack.range);
      final stats = PlaneStats.of(sim.rules, state, state.plane('p1')!);
      expect(stats.seats, 3);
      expect(stats.rangeKm, closeTo(1200 * 1.15, 0.01));
    });

    test('mixed planes upgrade cargo slots apart from seats', () {
      var state = growth.upgradePlane(base(), 'p1', PlaneTrack.cargo);
      expect(state.player.money, 100000 - 300);
      state = growth.upgradePlane(state, 'p1', PlaneTrack.cargo);
      final plane = state.plane('p1')!;
      expect(plane.upgrades.cargo, 2);
      expect(plane.upgrades.capacity, 0);
      final stats = PlaneStats.of(sim.rules, state, plane);
      expect(stats.seats, 2);
      expect(stats.cargoSlots, 1 + 2);
    });

    test('only planes with seats and a hold have a cargo track', () {
      final state = base(
        planes: const [
          Plane(id: 'p1', modelId: 'hauler_h2', cityId: 'chicago'),
          Plane(id: 'p2', modelId: 'firefly_fx1', cityId: 'chicago'),
        ],
      );
      for (final p in state.planes) {
        expect(growth.hasTrack(p, PlaneTrack.cargo), isFalse);
        expect(growth.planeUpgradeCost(p, PlaneTrack.cargo), isNull);
        expect(
          () => growth.upgradePlane(state, p.id, PlaneTrack.cargo),
          refused(RuleError.noCargoTrack),
        );
      }
    });

    test('renaming sets a nickname; an empty name clears it', () {
      var state = growth.renamePlane(base(), 'p1', '  Blue Jay ');
      expect(state.plane('p1')!.nickname, 'Blue Jay');
      state = growth.renamePlane(state, 'p1', '');
      expect(state.plane('p1')!.nickname, isNull);
    });
  });

  group('region licenses', () {
    test('the home region and owned airports\' regions are licensed', () {
      final state = base().copyWith(
        airports: [
          ...base().airports,
          const AirportState(cityId: 'london'),
        ],
      );
      expect(growth.licensedRegions(state), {'north_america', 'europe'});
      // The free airport didn't use up a license.
      expect(growth.nextLicense(state)!.airlineLevel, 5);
    });

    test('licenses unlock at airline levels and cost money, in order', () {
      expect(
        () => growth.buyLicense(base(level: 4), 'europe'),
        refused(RuleError.levelTooLow),
      );
      var state = growth.buyLicense(base(level: 5), 'europe');
      expect(state.player.money, 100000 - 20000);
      expect(growth.isLicensed(state, 'europe'), isTrue);
      expect(
        () => growth.buyLicense(state, 'europe'),
        refused(RuleError.alreadyOwned),
      );
      // The second license waits for level 12.
      expect(
        () => growth.buyLicense(state, 'asia'),
        refused(RuleError.levelTooLow),
      );
      state = state.copyWith(player: state.player.copyWith(level: 12));
      state = growth.buyLicense(state, 'asia');
      expect(state.player.licenses, ['europe', 'asia']);
      expect(state.player.money, 100000 - 80000);
    });

    test('the last license runs out', () {
      var state = base(money: 10000000, level: 60);
      for (final r in [
        'europe',
        'asia',
        'africa',
        'oceania',
        'south_america',
        'antarctica',
      ]) {
        state = growth.buyLicense(state, r);
      }
      expect(growth.nextLicense(state), isNull);
      expect(growth.licensedRegions(state), hasLength(7));
    });
  });

  group('airport shop', () {
    test('price grows with city size and airports owned', () {
      // Minneapolis is size 3: 3,000 x (1 + 0.1 x 2).
      expect(growth.airportPrice(base(), 'minneapolis'), 3600);
      expect(growth.airportPrice(base(), 'new_york'), 30000);
    });

    test(
      'buying an airport charges, adds a level 1 airport and fills its board',
      () {
        final state = sim.buyAirport(base(), 'minneapolis', t0);
        expect(state.player.money, 100000 - 3600);
        final airport = state.airport('minneapolis')!;
        expect(airport.level, 1);
        expect(airport.board, isNotEmpty);
        final size = sim.boards.boardSize(state, airport);
        expect(airport.board, hasLength(size.passenger + size.cargo));
      },
    );

    test('a city in an unlicensed region is refused', () {
      expect(
        () => growth.buyAirport(base(), 'london', t0),
        refused(RuleError.regionLocked),
      );
      final licensed = growth.buyLicense(base(level: 5), 'europe');
      expect(
        growth.buyAirport(licensed, 'london', t0).ownsAirport('london'),
        isTrue,
      );
    });

    test('an owned airport can\'t be bought again', () {
      expect(
        () => growth.buyAirport(base(), 'toronto', t0),
        refused(RuleError.alreadyOwned),
      );
    });
  });

  group('airport levels', () {
    test('upgrading charges the size-scaled cost and grows the board', () {
      final before = base();
      final state = growth.upgradeAirport(before, 'toronto', t0);
      // Level 2 costs 2,000 at a size 3 city; Toronto is size 4 (x1.5).
      expect(state.player.money, 100000 - 3000);
      expect(state.airport('toronto')!.level, 2);
      expect(
        state.airport('toronto')!.board.length,
        config.airports.level(2).jobBoardSize,
      );
    });

    test('airline level caps airport level', () {
      var state = growth.upgradeAirport(base(), 'chicago', t0);
      expect(state.airport('chicago')!.level, 3);
      expect(
        () => growth.upgradeAirport(state, 'chicago', t0),
        refused(RuleError.levelTooLow),
      );
      state = state.copyWith(player: state.player.copyWith(level: 10));
      state = growth.upgradeAirport(state, 'chicago', t0);
      expect(state.airport('chicago')!.level, 4);
      expect(
        () => growth.upgradeAirport(state, 'chicago', t0),
        refused(RuleError.levelTooLow),
      );
      state = state.copyWith(
        player: state.player.copyWith(level: 20, money: 1000000),
      );
      state = growth.upgradeAirport(state, 'chicago', t0);
      expect(
        () => growth.upgradeAirport(state, 'chicago', t0),
        refused(RuleError.maxLevel),
      );
    });

    test('a new gate lands a plane holding for one', () {
      final holding = base(
        planes: [
          const Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'toronto'),
          Plane(
            id: 'p2',
            modelId: 'sparrow_s1',
            cityId: 'toronto',
            status: PlaneStatus.holding,
            holdingSince: t0,
            leg: FlightLeg(
              fromCityId: 'chicago',
              toCityId: 'toronto',
              departAt: t0.subtract(const Duration(minutes: 5)),
              arriveAt: t0,
              distanceKm: 700,
            ),
          ),
        ],
      );
      final state = growth.upgradeAirport(holding, 'toronto', t0);
      expect(state.plane('p2')!.status, PlaneStatus.parked);
    });
  });

  group('upgrade paths', () {
    test('tiers cost only size-scaled money, in order', () {
      var state = base();
      final chicago = state.airport('chicago')!;
      expect(growth.pathTierCost(chicago, 'cargo'), 7500);
      state = growth.buyPathTier(state, 'chicago', 'cargo', t0);
      state = growth.buyPathTier(state, 'chicago', 'cargo', t0);
      expect(state.airport('chicago')!.tier('cargo'), 2);
      expect(state.player.money, 100000 - 7500 - 22500);
      // No point cap: a third path tier is fine with the coins for it.
      state = growth.buyPathTier(state, 'chicago', 'passenger', t0);
      expect(growth.tiersBought(state.airport('chicago')!), 3);
      expect(state.player.money, 100000 - 7500 - 22500 - 7500);
    });

    test('a tier is refused without the coins for it', () {
      final state = base(money: 1000);
      expect(
        growth.buyTierProblem(state, 'chicago', 'cargo'),
        RuleError.notEnoughMoney,
      );
      expect(
        () => growth.buyPathTier(state, 'chicago', 'cargo', t0),
        refused(RuleError.notEnoughMoney),
      );
    });

    test('a board-slot tier fills the extra slots now', () {
      var state = base(money: 1000000)
          .updateAirport('chicago', (a) => a.copyWith(level: 3));
      state = sim.boards.fill(state, 'chicago', t0);
      final before = state.airport('chicago')!.board.length;
      state = growth.buyPathTier(state, 'chicago', 'cargo', t0);
      state = growth.buyPathTier(state, 'chicago', 'cargo', t0);
      expect(state.airport('chicago')!.board.length, before + 3);
    });

    test('selling the top tier refunds half', () {
      var state = growth.buyPathTier(base(), 'chicago', 'gateway', t0);
      state = growth.buyPathTier(state, 'chicago', 'gateway', t0);
      final money = state.player.money;
      state = growth.sellPathTier(state, 'chicago', 'gateway');
      expect(state.player.money, money + 11250);
      expect(state.airport('chicago')!.tier('gateway'), 1);
      expect(growth.tiersBought(state.airport('chicago')!), 1);
      state = growth.sellPathTier(state, 'chicago', 'gateway');
      expect(state.airport('chicago')!.pathTiers, isEmpty);
      expect(
        () => growth.sellPathTier(state, 'chicago', 'gateway'),
        refused(RuleError.nothingToSell),
      );
    });

    test('the top path is the one with most tiers', () {
      const a = AirportState(
        cityId: 'chicago',
        pathTiers: {'cargo': 1, 'transfer': 2},
      );
      expect(growth.topPath(a), 'transfer');
      expect(growth.topPath(const AirportState(cityId: 'chicago')), isNull);
    });
  });

  group('airline levels', () {
    test('every unlock in the progression table is listed at its level', () {
      expect(
        growth.unlocksAt(3),
        containsAll([
          'Challenge board',
          'Puffin PF2',
          'Kestrel K3',
          'Title: Kite Runner',
        ]),
      );
      expect(
        growth.unlocksAt(5),
        containsAll([
          'Medium planes',
          'Second region license',
          'Pilots +1',
          'Pelican P4',
        ]),
      );
      expect(
        growth.unlocksAt(7),
        contains('Special jobs (VIP, Fragile, Rush)'),
      );
      expect(
        growth.unlocksAt(10),
        containsAll(['Airport level 4', 'Pilots +2', 'Part crates']),
      );
      expect(growth.unlocksAt(12), contains('Third region license'));
      expect(
        growth.unlocksAt(15),
        containsAll(['Fourth region license', 'Pilots +2']),
      );
      expect(
        growth.unlocksAt(20),
        containsAll(['Large planes', 'Airport level 5', 'Albatross L6']),
      );
      expect(
        growth.unlocksAt(30),
        containsAll(['Fifth region license', 'Special liveries']),
      );
      expect(growth.unlocksAt(2), isEmpty);
      expect(growth.nextUnlockLevel(1), 3);
    });

    test('titles follow the table', () {
      expect(growth.title(1), 'Paper Plane');
      expect(growth.title(9), 'Winging It');
      expect(growth.title(45), 'Sky Baron');
    });

    test('delivering jobs levels the airline up', () {
      final state = Economy(sim.rules).grantXp(base(), 100);
      expect(state.player.level, 2);
    });
  });

  group('saving', () {
    test('region and pilot licenses round-trip', () {
      var state = growth.buyLicense(base(level: 5), 'europe');
      state = sim.crew.buyPilotLicense(state);
      final back = GameState.fromJson(state.toJson());
      expect(back.player.licenses, ['europe']);
      expect(back.player.pilotLicenses, 1);
      expect(back, state);
    });

    test('a save from before growth reads as no licenses or expansions', () {
      final player = PlayerState.fromJson({'money': 5, 'xp': 1, 'level': 3});
      expect(player.licenses, isEmpty);
      expect(player.pilotLicenses, 0);
    });
  });

  test('actions through the simulation run the world first', () {
    final later = t0.add(const Duration(minutes: 6));
    final state = sim.buyPlane(base(), 'sparrow_s1', later);
    expect(state.simulatedTo, later);
  });
}
