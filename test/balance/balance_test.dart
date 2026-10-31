import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'bot.dart';

/// Package 9's balance check: a bot plays 30 in-game days on the shipped
/// numbers (three 30-minute sessions a day) and the design doc's balance
/// targets are checked against what it saw. The full report prints with
/// the test; docs/balance.md explains the targets and the tuning.
void main() {
  late GameConfig config;
  late BotReport r;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    final sim = Simulation(Rules(config, crew: GameCrew(config)));
    r = BalanceBot(sim).play(days: 30);
    // ignore: avoid_print
    print(describe(r, config));
  });

  test('the first new plane is affordable within about 10 minutes', () {
    expect(r.firstPlaneAffordableAt, lessThanOrEqualTo(minutes(15)));
  });

  test('an airport upgrade is affordable in the first session', () {
    final sim = Simulation(Rules(config, crew: GameCrew(config)));
    final t = DateTime.utc(2026, 11, 2, 8);
    final start = sim.startAirline(
      GameState.newGame(now: t, startingMoney: config.economy.startingMoney),
      'chicago',
      t,
    );
    final growth = sim.growth;
    final cheapest = start.airports
        .map(growth.airportUpgradeCost)
        .whereType<int>()
        .reduce(min);
    final firstSession = r.incomePerHour(1) / 2;
    expect(cheapest, lessThan(config.economy.startingMoney + firstSession));
  });

  test('planes earn their price back in about 20 to 40 flights', () {
    final flown = r.planes.where((p) => p.flights >= 20).toList();
    expect(flown.length, greaterThanOrEqualTo(5));
    for (final p in flown) {
      // Large planes rarely fly full, so they take longer.
      final large = config.planes.model(p.modelId).classId == 'large';
      expect(
        p.paybackFlights,
        inInclusiveRange(10, large ? 130 : 60),
        reason: p.modelId,
      );
    }
    final median = (flown.map((p) => p.paybackFlights).toList()
      ..sort())[flown.length ~/ 2];
    expect(median, inInclusiveRange(15, 45));
  });

  test('money never goes negative', () {
    expect(r.lowestMoney, greaterThanOrEqualTo(0));
    expect(r.errors, 0);
  });

  test('the airline grows at a steady pace', () {
    expect(r.levelReachedAt[10]!.inHours, inInclusiveRange(5, 20));
    expect(r.finalState.player.level, inInclusiveRange(25, 50));
    expect(r.incomePerHour(1), inInclusiveRange(1000, 4000));
    expect(r.finalState.planes.length, greaterThanOrEqualTo(8));
  });

  test('a level 8 veteran becomes the better deal around level 8 to 10', () {
    // Growing a rookie to level 8 takes about 15 hours of flying.
    final veteran = config.crew.hiring.veteranPrice(8);
    double hoursToSave(int level) => veteran / max(r.incomePerHour(level), 1);
    expect(hoursToSave(5), greaterThan(15));
    expect(
      [
        for (final l in [9, 10, 11]) hoursToSave(l),
      ].reduce(min),
      lessThan(15),
    );
  });

  test('rivals win and lose cities, but the player leads most of theirs', () {
    final (:lead, :changes) = rivalry(r);
    expect(lead, inInclusiveRange(0.7, 0.97));
    expect(changes, greaterThanOrEqualTo(10));
  });
}

Duration minutes(int n) => Duration(minutes: n);

/// The share of city-hours with a leader that the player led, and how many
/// times a city's leader changed.
({double lead, int changes}) rivalry(BotReport r) {
  var samples = 0, mine = 0, changes = 0;
  for (final leaders in r.leaders.values) {
    for (var i = 0; i < leaders.length; i++) {
      if (leaders[i] == null) continue;
      samples++;
      if (leaders[i] == playerAirlineId) mine++;
      if (i > 0 && leaders[i - 1] != null && leaders[i - 1] != leaders[i]) {
        changes++;
      }
    }
  }
  return (lead: mine / max(samples, 1), changes: changes);
}

String describe(BotReport r, GameConfig config) {
  final s = r.finalState;
  final b = StringBuffer()
    ..writeln(
      'Bot: ${r.played.inHours}h of play over 30 days in '
      '${r.wallTime.inSeconds}s, ${r.departures} departures',
    )
    ..writeln(
      'First plane affordable at ${r.firstPlaneAffordableAt?.inMinutes} min; '
      'ended at level ${s.player.level} with ${s.planes.length} planes, '
      '${s.airports.length} airports and ${s.player.money} coins',
    );
  final (:lead, :changes) = rivalry(r);
  b.writeln(
    'The player led ${(lead * 100).round()}% of city-hours; '
    '$changes lead changes',
  );
  for (final l in r.levelReachedAt.keys.toList()..sort()) {
    final at = r.levelReachedAt[l]!.inMinutes / 60;
    b.writeln(
      '  Lv $l at ${at.toStringAsFixed(1)}h of play, '
      '${r.incomePerHour(l)} coins/h',
    );
  }
  for (final p in r.planes) {
    b.writeln(
      '  ${p.modelId} (${p.price}): ${p.flights} flights, pays back in '
      '${p.paybackFlights.toStringAsFixed(1)}',
    );
  }
  return b.toString();
}
