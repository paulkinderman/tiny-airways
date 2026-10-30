import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/save/save_migrations.dart';
import 'package:tiny_airways/core/save/save_repository.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/core/state/game_state.dart';

/// Guards the shipped migration chain. Every schema version ever released
/// keeps a fixture in `test/fixtures/saves/v<N>.json` that must still load.
void main() {
  test('every older save version has a migration to the next one', () {
    for (var v = 1; v < currentSaveVersion; v++) {
      expect(saveMigrations, contains(v), reason: 'missing migration $v');
    }
  });

  test('there is a fixture for every save version', () {
    for (var v = 1; v <= currentSaveVersion; v++) {
      expect(File('test/fixtures/saves/v$v.json').existsSync(), isTrue);
    }
  });

  test('every fixture loads in this build', () {
    final repo = SaveRepository(
      storage: MemorySaveStorage(),
      clock: FakeClock(),
    );
    for (var v = 1; v <= currentSaveVersion; v++) {
      final text = File('test/fixtures/saves/v$v.json').readAsStringSync();
      expect(() => repo.decode(text), returnsNormally, reason: 'v$v.json');
    }
  });

  test('the v1 fixture keeps its values', () {
    final repo = SaveRepository(
      storage: MemorySaveStorage(),
      clock: FakeClock(),
    );
    final state = repo.decode(
      File('test/fixtures/saves/v1.json').readAsStringSync(),
    );
    expect(state.player.money, 12500);
    expect(state.player.level, 4);
    expect(state.createdAt, DateTime.utc(2026, 10, 29, 9, 15));
  });

  test('a v1 airline comes back not started, keeping its money and level', () {
    final repo = SaveRepository(
      storage: MemorySaveStorage(),
      clock: FakeClock(),
    );
    final state = repo.decode(
      File('test/fixtures/saves/v1.json').readAsStringSync(),
    );
    expect(state.hasStarted, isFalse);
    expect(state.player.money, 12500);
    expect(state.player.level, 4);
    expect(state.airports, isEmpty);
    expect(state.planes, isEmpty);
    expect(state.simulatedTo, state.lastSeenAt);
  });

  test('the v2 fixture keeps its values', () {
    final repo = SaveRepository(
      storage: MemorySaveStorage(),
      clock: FakeClock(),
    );
    final state = repo.decode(
      File('test/fixtures/saves/v2.json').readAsStringSync(),
    );
    expect(state.homeCityId, 'chicago');
    expect(state.airports.map((a) => a.cityId), ['chicago', 'minneapolis']);
    expect(state.airport('chicago')!.board, hasLength(9));
    expect(state.planes.single.status, PlaneStatus.parked);
    expect(state.player.money, 2603);
    expect(state.stats.legsFlown, 1);
    expect(state.simulatedTo, DateTime.utc(2026, 10, 29, 10, 5));
  });
}
