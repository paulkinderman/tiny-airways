import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';

import 'config_test_helpers.dart';

void main() {
  late GameConfig config;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
  });

  group('world', () {
    test('about 150 cities across the 7 continents', () {
      final world = config.world;
      expect(world.regions.map((r) => r.id), [
        'north_america',
        'south_america',
        'europe',
        'africa',
        'asia',
        'oceania',
        'antarctica',
      ]);
      expect(world.cities, hasLength(152));
      expect(world.citiesIn('north_america'), hasLength(32));
      expect(world.citiesIn('europe'), hasLength(34));
      expect(world.citiesIn('antarctica'), hasLength(6));
    });

    test('Antarctica is the hard-mode start with research stations', () {
      final antarctica = config.world.region('antarctica');
      expect(antarctica.hardMode, isTrue);
      expect(antarctica.outboundPayMultiplier, greaterThan(1));
      expect(
        config.world.citiesIn('antarctica').every((c) => c.size == 1),
        isTrue,
      );
    });

    test('every size class is used', () {
      expect(config.world.cities.map((c) => c.size).toSet(), {1, 2, 3, 4, 5});
    });

    test('great-circle distances match known routes', () {
      final w = config.world;
      double km(String a, String b) =>
          WorldData.distanceKm(w.city(a), w.city(b));
      expect(km('chicago', 'toronto'), closeTo(700, 20));
      expect(km('new_york', 'london'), closeTo(5570, 40));
      expect(km('sydney', 'melbourne'), closeTo(713, 15));
      expect(km('tokyo', 'tokyo'), 0);
    });

    test('mockup home cities have a neighbour in starter-plane range', () {
      final sparrow = config.planes.model(config.economy.startingPlaneModelId);
      for (final id in [
        'chicago',
        'denver',
        'atlanta',
        'london',
        'esperanza_base',
      ]) {
        final city = config.world.city(id);
        expect(
          config.world.neighboursWithin(city, sparrow.rangeKm.toDouble()),
          isNotEmpty,
          reason: id,
        );
      }
    });

    test('most cities can be a home city with the starting plane', () {
      final range = config.planes
          .model(config.economy.startingPlaneModelId)
          .rangeKm
          .toDouble();
      final startable = config.world.cities
          .where((c) => config.world.neighboursWithin(c, range).isNotEmpty)
          .length;
      expect(startable / config.world.cities.length, greaterThan(0.8));
    });
  });

  group('planes', () {
    test('the 12 hangar planes and 3 special planes', () {
      expect(config.planes.models, hasLength(12));
      expect(config.planes.specialModels.map((m) => m.id), [
        'barnstormer',
        'mach_one',
        'cloud_nine',
      ]);
      final sparrow = config.planes.model('sparrow_s1');
      expect(sparrow.price, 3200);
      expect(sparrow.unlockLevel, 1);
      expect(config.planes.model('goose_g10').classId, 'large');
      expect(config.planes.model('cloud_nine').fuelPerKm, 0);
      expect(config.planes.model('cloud_nine').ignoresJetStream, isTrue);
    });

    test('each class has a cargo-only option', () {
      for (final cls in PlaneClass.ids) {
        final models = config.planes.models.where((m) => m.classId == cls);
        expect(models.any((m) => m.seats == 0), isTrue, reason: cls);
      }
    });

    test('fuel is about 15% of a full plane\'s pay', () {
      final e = config.economy;
      for (final m in config.planes.models) {
        final pay =
            m.seats * e.passengerRatePerKm + m.cargoSlots * e.cargoRatePerKm;
        expect(m.fuelPerKm / pay, closeTo(0.15, 0.01), reason: m.id);
      }
    });

    test('hangar expansions get pricier', () {
      final hangar = config.planes.hangar;
      expect(hangar.startingSlots, 3);
      expect(hangar.expansionPrice(0), 10000);
      expect(hangar.expansionPrice(1), 15000);
    });
  });

  group('airports', () {
    test('purchase prices match the airport shop mockup', () {
      final a = config.airports;
      expect(a.purchasePrice(citySize: 4, airportsOwned: 5), 9000);
      expect(a.purchasePrice(citySize: 3, airportsOwned: 5), 4500);
      expect(a.purchasePrice(citySize: 5, airportsOwned: 5), 37500);
      expect(a.purchasePrice(citySize: 1, airportsOwned: 0), 1000);
    });

    test('levels follow the design doc table', () {
      final a = config.airports;
      expect(a.maxLevel, 5);
      expect(a.levels.map((l) => l.gates), [1, 2, 3, 5, 8]);
      expect(a.levels.map((l) => l.jobBoardSize), [6, 9, 12, 16, 22]);
      expect(a.levels.map((l) => l.upgradePoints), [1, 2, 3, 4, 6]);
      expect(a.levels.map((l) => l.staffSlots), [1, 1, 2, 2, 3]);
      expect(a.level(3).maxPlaneClass, 'medium');
    });

    test('four upgrade paths of three tiers', () {
      expect(config.airports.paths.map((p) => p.id), [
        'passenger',
        'cargo',
        'gateway',
        'transfer',
      ]);
      expect(config.airports.scaledCost(5000, 3), 5000);
      expect(config.airports.scaledCost(5000, 5), 12500);
    });
  });

  group('progression', () {
    test('titles and unlocks follow the design doc', () {
      final p = config.progression;
      expect(p.titleFor(1), 'Paper Plane');
      expect(p.titleFor(9), 'Winging It');
      expect(p.titleFor(55), 'Sky Baron');
      expect(p.maxAirportLevelAt(1), 3);
      expect(p.maxAirportLevelAt(10), 4);
      expect(p.maxAirportLevelAt(25), 5);
      expect(p.isUnlocked('challenges', 2), isFalse);
      expect(p.isUnlocked('challenges', 3), isTrue);
      expect(p.hangarBonusAt(15), 4);
      expect(p.planeClassUnlockLevel['large'], 20);
    });

    test('the XP bar grows every level', () {
      final p = config.progression;
      for (var level = 1; level < p.maxLevel; level++) {
        expect(p.xpToNext(level + 1), greaterThan(p.xpToNext(level)));
      }
    });
  });

  group('crew', () {
    test('six roles, four of them flight crew with three-branch trees', () {
      final crew = config.crew;
      expect(crew.roles, hasLength(6));
      expect(crew.skillTrees.keys, [
        'pilot',
        'navigator',
        'flight_attendant',
        'loadmaster',
      ]);
      expect(crew.staffPaths.keys, ['airport_manager', 'station_agent']);
    });

    test('19 nodes per crew member: 3 branches of 5 plus a signature of 4', () {
      final branches = config.crew.skillTrees['pilot']!;
      final nodes =
          branches.fold(0, (n, b) => n + b.nodes.length) +
          config.crew.signatures.first.nodes.length;
      expect(nodes, 19);
    });

    test('the pilot Fuel saver branch ends in Autopilot', () {
      final fuel = config.crew.skillTrees['pilot']!.firstWhere(
        (b) => b.id == 'fuel_saver',
      );
      expect(fuel.capstone.name, 'Autopilot');
      expect(fuel.capstone.value, 70);
    });

    test('seven signatures with unique node ids', () {
      expect(config.crew.signatures, hasLength(7));
      final ids = [
        for (final tree in config.crew.skillTrees.values)
          for (final b in tree)
            for (final n in b.nodes) n.id,
        for (final s in config.crew.signatures)
          for (final n in s.nodes) n.id,
      ];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('crew XP and hiring prices match the doc examples', () {
      final crew = config.crew;
      expect(crew.xpToNext(1), 100);
      expect(crew.hiring.rookiePrice(0), 2000);
      expect(crew.hiring.rookiePrice(2), 3125);
      expect(crew.hiring.veteranPrice(8), 120000);
    });
  });

  group('rivals', () {
    test('about 24 rivals, every continent has some', () {
      final rivals = config.rivals.roster;
      expect(rivals, hasLength(24));
      for (final region in config.world.regions) {
        expect(
          rivals.where((r) => r.regionId == region.id),
          isNotEmpty,
          reason: region.id,
        );
      }
    });
  });

  group('flights', () {
    test('a starter leg takes minutes, not hours', () {
      final duration = config.flights.realDuration(900, 280);
      expect(duration.inMinutes, inInclusiveRange(5, 15));
    });
  });

  group('cross-file checks', () {
    test('an unknown starting plane is rejected', () {
      expect(
        loadEdited('config/economy', (j) => j['startingPlaneModelId'] = 'nope'),
        throwsConfig('startingPlaneModelId "nope" is not a plane'),
      );
    });

    test('a city in an unknown region is rejected', () {
      expect(
        loadEdited('data/cities', (j) {
          item(j['cities'], 0)['regionId'] = 'atlantis';
        }),
        throwsConfig('"atlantis" is not a region'),
      );
    });

    test('duplicate city ids are rejected', () {
      expect(
        loadEdited('data/cities', (j) {
          final cities = j['cities'] as List;
          cities.add(Map.of(cities.first as Map));
        }),
        throwsConfig('"new_york" more than once'),
      );
    });

    test('a city size outside 1 to 5 names the city', () {
      expect(
        loadEdited('data/cities', (j) {
          item(j['cities'], 3)['size'] = 6;
        }),
        throwsConfig('data/cities.cities[3].size should be 1 to 5'),
      );
    });

    test('a rival hub outside its region is rejected', () {
      expect(
        loadEdited('data/rivals', (j) {
          item(j['rivals'], 0)['hubCityId'] = 'paris';
        }),
        throwsConfig('hub outside its region'),
      );
    });

    test('a rival with an unknown tier is rejected', () {
      expect(
        loadEdited('data/rivals', (j) {
          item(j['rivals'], 0)['tier'] = 'blimp';
        }),
        throwsConfig('data/rivals.rivals[0].tier'),
      );
    });

    test('a skill branch with a missing node is rejected', () {
      expect(
        loadEdited('config/crew', (j) {
          final pilot = (j['skillTrees'] as Map)['pilot'] as List;
          (item(pilot, 0)['nodes'] as List).removeAt(2);
        }),
        throwsConfig('crew.skillTrees.pilot[0].nodes should have 5 nodes'),
      );
    });

    test('a plane unlocking before its class is rejected', () {
      expect(
        loadEdited('config/planes', (j) {
          final models = j['models'] as List;
          item(models, models.length - 1)['unlockLevel'] = 2;
        }),
        throwsConfig('goose_g10 unlocks before its class'),
      );
    });

    test('an unsorted title list is rejected', () {
      expect(
        loadEdited('config/progression', (j) {
          (j['titles'] as List).add({'fromLevel': 2, 'title': 'Oops'});
        }),
        throwsConfig('progression.titles should be sorted'),
      );
    });
  });
}

Map<String, dynamic> item(Object? list, int index) =>
    (list! as List)[index] as Map<String, dynamic>;
