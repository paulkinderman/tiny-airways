import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_reader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

void main() {
  late GameConfig config;
  late Rules rules;
  late Simulation sim;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    rules = Rules(config);
    sim = Simulation(rules);
  });

  /// Rolls [count] events in a row for North America and returns the state.
  GameState rollMany(int count) {
    final weather = WeatherRules(rules);
    var state = sim.startAirline(
      GameState.newGame(now: t0, startingMoney: 2500),
      'chicago',
      t0,
    );
    for (var i = 0; i < count; i++) {
      state = weather.roll(
        state,
        'north_america',
        weather.rollTime(state, 'north_america'),
      );
    }
    return state;
  }

  group('airport closures are rare', () {
    test('thunderstorms are the only weather that closes an airport', () {
      expect(
        config.weather.events.where((e) => e.closesAirport).map((e) => e.id),
        ['thunderstorm'],
      );
    });

    test('at most about 1 in 8 weather events is a closure', () {
      expect(config.weather.closureShare, lessThanOrEqualTo(1 / 8));
      expect(config.weather.closureShare, greaterThan(0));
    });

    test('a continent sees a closure about every 8 hours or more', () {
      expect(
        config.weather.averageMinutesBetweenClosures,
        greaterThanOrEqualTo(8 * 60),
      );
    });

    test('a closure lasts at most 25 minutes', () {
      final storm = config.weather.events.firstWhere(
        (e) => e.id == 'thunderstorm',
      );
      expect(storm.maxMinutes, lessThanOrEqualTo(25));
    });

    test('rolled events follow the weights', () {
      const count = 3000;
      final events = rollMany(count).weather.events;
      expect(events, hasLength(count));
      final closures = events.where((e) => e.typeId == 'thunderstorm').length;
      final share = closures / count;
      expect(
        share,
        closeTo(config.weather.closureShare, 0.03),
        reason: '$closures closures in $count events',
      );
      // Every kind still turns up.
      expect(
        events.map((e) => e.typeId).toSet(),
        config.weather.events.map((e) => e.id).toSet(),
      );
    });

    test('an owned airport is closed well under 2% of the time', () {
      final state = rollMany(3000);
      final events = state.weather.events;
      final span = events.last.endsAt.difference(events.first.startsAt);
      var closedMinutes = 0;
      for (final e in events) {
        if (e.typeId == 'thunderstorm' && e.cityId == 'chicago') {
          closedMinutes += e.endsAt.difference(e.startsAt).inMinutes;
        }
      }
      expect(closedMinutes / span.inMinutes, lessThan(0.02));
    });
  });

  group('weather event weights', () {
    Map<String, dynamic> event([Map<String, dynamic> extra = const {}]) => {
      'id': 'rain',
      'name': 'Rain',
      'area': 'airport',
      'minMinutes': 10,
      'maxMinutes': 20,
      'effects': <String, dynamic>{},
      ...extra,
    };

    test('default to 1', () {
      final e = WeatherEventConfig.fromConfig(ConfigReader(event(), 'w'));
      expect(e.weight, 1);
    });

    test('are read from the config', () {
      final e = WeatherEventConfig.fromConfig(
        ConfigReader(event({'weight': 2.5}), 'w'),
      );
      expect(e.weight, 2.5);
    });

    test('must be above 0', () {
      expect(
        () => WeatherEventConfig.fromConfig(
          ConfigReader(event({'weight': 0}), 'w'),
        ),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
