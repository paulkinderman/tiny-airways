import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/save/save_repository.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/core/state/game_state.dart';

void main() {
  final clock = FakeClock(DateTime.utc(2026, 10, 30, 20));

  GameState sampleState() => GameState(
    createdAt: DateTime.utc(2026, 10, 29, 9, 15),
    lastSeenAt: DateTime.utc(2026, 10, 30, 19, 59),
    player: const PlayerState(money: 12500, xp: 340, level: 4),
  );

  group('round trip', () {
    test('in memory', () async {
      final repo = SaveRepository(storage: MemorySaveStorage(), clock: clock);
      await repo.save(sampleState());

      final result = await repo.load();
      expect(result.status, SaveLoadStatus.loaded);
      expect(result.state, sampleState());
    });

    test('on disk', () async {
      final dir = await Directory.systemTemp.createTemp('tiny_airways_save');
      addTearDown(() => dir.delete(recursive: true));

      final repo = SaveRepository(storage: FileSaveStorage(dir), clock: clock);
      await repo.save(sampleState());
      final loaded = await SaveRepository(
        storage: FileSaveStorage(dir),
        clock: clock,
      ).load();

      expect(loaded.state, sampleState());
      expect(File('${dir.path}/save.json.tmp').existsSync(), isFalse);
    });

    test('the document records its version and when it was saved', () async {
      final storage = MemorySaveStorage();
      await SaveRepository(storage: storage, clock: clock).save(sampleState());

      final json = jsonDecode(storage.primary!) as Map<String, dynamic>;
      expect(json['version'], 1);
      expect(json['savedAt'], '2026-10-30T20:00:00.000Z');
      expect(json['state'], sampleState().toJson());
    });

    test('writes land in the order they were made', () async {
      final storage = MemorySaveStorage();
      final repo = SaveRepository(storage: storage, clock: clock);
      final base = sampleState();
      await Future.wait([
        for (var money = 1; money <= 5; money++)
          repo.save(base.copyWith(player: base.player.copyWith(money: money))),
      ]);

      expect((await repo.load()).state!.player.money, 5);
      expect(repo.decode(storage.backup!).player.money, 4);
    });
  });

  group('loading', () {
    test('no save means a new game', () async {
      final result = await SaveRepository(
        storage: MemorySaveStorage(),
        clock: clock,
      ).load();
      expect(result.status, SaveLoadStatus.none);
      expect(result.state, isNull);
    });

    test('a corrupt save falls back to the backup', () async {
      final storage = MemorySaveStorage();
      final repo = SaveRepository(storage: storage, clock: clock);
      await repo.save(sampleState());
      await storage.write('{"version": 1, "state": {"truncat');

      final result = await repo.load();
      expect(result.status, SaveLoadStatus.recoveredFromBackup);
      expect(result.state, sampleState());
      expect(result.error, isA<SaveException>());
    });

    test('a file cut short on disk falls back to the backup', () async {
      final dir = await Directory.systemTemp.createTemp('tiny_airways_save');
      addTearDown(() => dir.delete(recursive: true));
      final repo = SaveRepository(storage: FileSaveStorage(dir), clock: clock);
      await repo.save(sampleState());
      await repo.save(
        sampleState().copyWith(
          player: const PlayerState(money: 1, xp: 0, level: 1),
        ),
      );
      final primary = File('${dir.path}/save.json');
      final text = await primary.readAsString();
      await primary.writeAsString(text.substring(0, text.length ~/ 2));

      final result = await repo.load();
      expect(result.status, SaveLoadStatus.recoveredFromBackup);
      expect(result.state, sampleState());
    });

    test('when nothing is readable the saves are kept aside', () async {
      final dir = await Directory.systemTemp.createTemp('tiny_airways_save');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/save.json').writeAsString('garbage');
      await File('${dir.path}/save.backup.json').writeAsString('more garbage');

      final repo = SaveRepository(storage: FileSaveStorage(dir), clock: clock);
      final result = await repo.load();

      expect(result.status, SaveLoadStatus.unreadable);
      final names = dir.listSync().map((f) => f.uri.pathSegments.last).toList();
      expect(names, hasLength(2));
      expect(names.every((n) => n.contains('.unreadable-')), isTrue);
      // A new game can now save without touching the old files.
      await repo.save(sampleState());
      expect((await repo.load()).status, SaveLoadStatus.loaded);
    });

    test('a save from a newer build is refused, not overwritten', () async {
      final storage = MemorySaveStorage(
        primary: jsonEncode({
          'version': 99,
          'savedAt': '2026-10-30T20:00:00.000Z',
          'state': sampleState().toJson(),
        }),
      );
      final result = await SaveRepository(
        storage: storage,
        clock: clock,
      ).load();

      expect(result.status, SaveLoadStatus.unreadable);
      expect((result.error! as SaveException).message, contains('version 99'));
      expect(storage.quarantined, hasLength(1));
    });
  });

  group('migrations', () {
    // A pretend schema change: version 1 stored `player.coins`, version 2
    // calls it `player.money`, and version 3 adds `player.xp`.
    final legacy = jsonEncode({
      'version': 1,
      'savedAt': '2026-10-30T20:00:00.000Z',
      'state': {
        'createdAt': '2026-10-29T09:15:00.000Z',
        'lastSeenAt': '2026-10-30T19:59:00.000Z',
        'player': {'coins': 12500, 'level': 4},
      },
    });

    Map<String, dynamic> renameCoins(Map<String, dynamic> state) {
      final player = Map<String, dynamic>.of(
        state['player'] as Map<String, dynamic>,
      );
      player['money'] = player.remove('coins');
      return {...state, 'player': player};
    }

    Map<String, dynamic> addXp(Map<String, dynamic> state) => {
      ...state,
      'player': {...state['player'] as Map<String, dynamic>, 'xp': 340},
    };

    test('run in order from the save version up to the current one', () {
      final repo = SaveRepository(
        storage: MemorySaveStorage(),
        clock: clock,
        version: 3,
        migrations: {1: renameCoins, 2: addXp},
      );
      expect(repo.decode(legacy), sampleState());
    });

    test('a gap in the migration chain is an error', () {
      final repo = SaveRepository(
        storage: MemorySaveStorage(),
        clock: clock,
        version: 3,
        migrations: {1: renameCoins},
      );
      expect(
        () => repo.decode(legacy),
        throwsA(
          isA<SaveException>().having(
            (e) => e.message,
            'message',
            contains('no migration from save version 2'),
          ),
        ),
      );
    });

    test('saves are written at the current version', () async {
      final storage = MemorySaveStorage(primary: legacy);
      final repo = SaveRepository(
        storage: storage,
        clock: clock,
        version: 3,
        migrations: {1: renameCoins, 2: addXp},
      );
      await repo.save((await repo.load()).state!);
      expect((jsonDecode(storage.primary!) as Map)['version'], 3);
    });
  });
}
