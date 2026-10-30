import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_reader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';

void main() {
  group('shipped config', () {
    test('every file in assets/config loads', () async {
      final config = await ConfigLoader(DirectoryConfigSource('assets/config'))
          .load();

      expect(config.economy.startingMoney, 2500);
      expect(config.economy.passengerRatePerKm, 0.35);
      expect(config.economy.cargoRatePerKm, 0.45);
    });
  });

  group('broken config', () {
    Future<GameConfig> loadEconomy(Object json) =>
        ConfigLoader(MemoryConfigSource({'economy': jsonEncode(json)})).load();

    Map<String, dynamic> validEconomy() => jsonDecode(
      jsonEncode({
        'startingMoney': 2500,
        'startingPlaneModelId': 'sparrow_s1',
        'homeAirportStartLevel': 2,
        'freeNearbyAirports': 1,
        'rates': {'passengerPerKm': 0.35, 'cargoPerKm': 0.45},
        'airportPrice': {'smallCity': 1000, 'megaCity': 25000},
      }),
    ) as Map<String, dynamic>;

    test('a valid file loads', () async {
      final config = await loadEconomy(validEconomy());
      expect(config.economy.megaCityAirportPrice, 25000);
    });

    test('a missing file names the file', () {
      expect(
        ConfigLoader(MemoryConfigSource({})).load(),
        throwsConfig('"economy"'),
      );
    });

    test('invalid JSON names the file', () {
      expect(
        ConfigLoader(MemoryConfigSource({'economy': '{ nope'})).load(),
        throwsConfig('economy.json is not valid JSON'),
      );
    });

    test('a missing field names its full path', () {
      final json = validEconomy();
      (json['rates'] as Map<String, dynamic>).remove('cargoPerKm');
      expect(loadEconomy(json), throwsConfig('economy.rates.cargoPerKm'));
    });

    test('a field of the wrong type says what it got', () {
      final json = validEconomy()..['startingMoney'] = 'lots';
      expect(
        loadEconomy(json),
        throwsConfig('economy.startingMoney should be a whole number'),
      );
    });

    test('a fractional value where a whole number belongs is rejected', () {
      final json = validEconomy()..['startingMoney'] = 2500.5;
      expect(loadEconomy(json), throwsConfig('economy.startingMoney'));
    });

    test('a top level that is not an object is rejected', () {
      expect(loadEconomy([1, 2, 3]), throwsConfig('JSON object'));
    });
  });

  group('ConfigReader', () {
    test('children and lists report the index of a bad item', () {
      final reader = ConfigReader({
        'planes': [
          {'id': 'a'},
          7,
        ],
        'tags': ['x', 3],
      }, 'fleet');

      expect(
        () => reader.children('planes'),
        throwsConfig('fleet.planes[1] should be an object'),
      );
      expect(() => reader.list<String>('tags'), throwsConfig('fleet.tags[1]'));
    });

    test('integer accepts whole numbers written as 2.0', () {
      expect(ConfigReader({'n': 2.0}, 'f').integer('n'), 2);
    });
  });
}

Matcher throwsConfig(String messagePart) => throwsA(
  isA<ConfigException>().having(
    (e) => e.message,
    'message',
    contains(messagePart),
  ),
);
