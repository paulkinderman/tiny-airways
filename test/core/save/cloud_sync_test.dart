import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/save/cloud_sync.dart';
import 'package:tiny_airways/core/save/save_repository.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/core/state/game_state.dart';

/// One device: its own save, sync marker and clock, sharing [cloud].
class Device {
  Device(this.cloud, DateTime start) : clock = FakeClock(start) {
    sync = CloudSync(
      cloud: cloud,
      marker: marker,
      saves: SaveRepository(storage: local, clock: clock),
      clock: clock,
    );
    saves = SaveRepository(
      storage: CloudSyncedStorage(local, sync),
      clock: clock,
    );
  }

  final MemoryCloudSaveStore cloud;
  final FakeClock clock;
  final local = MemorySaveStorage();
  final marker = MemoryTextStore();
  late final CloudSync sync;
  late final SaveRepository saves;

  /// Launch: compare with the cloud and settle what can be settled.
  Future<SyncDecision> launch() async {
    final decision = await sync.check(local.primary);
    if (decision is UseCloud) {
      await local.write(decision.cloud.text);
      await sync.adopted(decision.cloud);
    }
    return decision;
  }

  GameState get state => saves.decode(local.primary!);

  /// Plays a little (earns [money]) and saves, as backgrounding does.
  Future<void> play(int money) async {
    clock.advance(const Duration(minutes: 5));
    final s = state;
    await saves.save(
      s.copyWith(player: s.player.copyWith(money: s.player.money + money)),
    );
    await sync.flush();
  }
}

GameState started(DateTime at, {int money = 1000}) => GameState(
  createdAt: at,
  lastSeenAt: at,
  player: PlayerState(money: money, xp: 0, level: 4),
  homeCityId: 'chicago',
  airports: const [AirportState(cityId: 'chicago')],
);

void main() {
  final t = DateTime.utc(2026, 10, 30, 12);

  test('a save played on one device loads on another', () async {
    final cloud = MemoryCloudSaveStore();
    final a = Device(cloud, t);
    expect(await a.launch(), isA<KeepLocal>());
    await a.saves.save(started(t));
    await a.sync.flush();
    expect(cloud.text, isNotNull);

    // A new install picks up the airline without asking.
    final b = Device(cloud, t.add(const Duration(hours: 1)));
    final decision = await b.launch();
    expect(decision, isA<UseCloud>());
    expect(b.state.homeCityId, 'chicago');

    // B plays; A comes back and takes B's progress.
    await b.play(500);
    final back = await a.launch();
    expect(back, isA<UseCloud>());
    await a.local.write((back as UseCloud).cloud.text);
    expect(a.state.player.money, 1500);
  });

  test('an unchanged cloud keeps the local save, which goes up', () async {
    final cloud = MemoryCloudSaveStore();
    final a = Device(cloud, t);
    await a.launch();
    await a.saves.save(started(t));
    await a.sync.flush();
    await a.play(100);
    expect(await a.launch(), isA<KeepLocal>());
    expect(
      SaveRepository(
        storage: MemorySaveStorage(),
        clock: a.clock,
      ).decode(cloud.text!).player.money,
      1100,
    );
  });

  test('two devices that both played get the picker', () async {
    final cloud = MemoryCloudSaveStore();
    final a = Device(cloud, t);
    await a.launch();
    await a.saves.save(started(t));
    await a.sync.flush();
    final b = Device(cloud, t.add(const Duration(minutes: 1)));
    await b.launch();

    await b.play(500);
    // A played offline meanwhile, so its save never went up.
    cloud.available = false;
    await a.play(200);
    cloud.available = true;

    final decision = await a.launch();
    expect(decision, isA<SyncConflict>());
    final conflict = decision as SyncConflict;
    expect(conflict.local.summary.money, 1200);
    expect(conflict.cloud.summary.money, 1500);

    final kept = await a.sync.choose(conflict, keepLocal: true);
    expect(kept.player.money, 1200);
    // The kept airline replaces the other one on B's next launch.
    final onB = await b.launch();
    expect(onB, isA<UseCloud>());
    expect((onB as UseCloud).cloud.state.player.money, 1200);
  });

  test('a fresh install never overwrites the cloud before checking', () async {
    final cloud = MemoryCloudSaveStore();
    final a = Device(cloud, t);
    await a.launch();
    await a.saves.save(started(t));
    await a.sync.flush();
    final before = cloud.text;

    final b = Device(cloud, t);
    // Saving a new game before the launch check sends nothing.
    await b.saves.save(GameState.newGame(now: t, startingMoney: 2500));
    await b.sync.flush();
    expect(cloud.text, before);
  });

  test('a cloud save from a newer build pauses syncing', () async {
    final cloud = MemoryCloudSaveStore(
      text: jsonEncode({
        'version': 999,
        'savedAt': t.toIso8601String(),
        'state': <String, dynamic>{},
      }),
    );
    final a = Device(cloud, t);
    expect(await a.launch(), isA<KeepLocal>());
    expect(a.sync.isBlocked, isTrue);
    await a.saves.save(started(t));
    await a.sync.flush();
    expect((jsonDecode(cloud.text!) as Map)['version'], 999);
  });

  test('pushes are spaced out while playing', () async {
    final cloud = MemoryCloudSaveStore();
    final a = Device(cloud, t);
    await a.launch();
    await a.saves.save(started(t));
    await a.saves.save(started(t, money: 5));
    await a.saves.save(started(t, money: 6));
    expect(cloud.writes, 1);
    await a.sync.flush();
    expect(cloud.writes, 2);
  });

  test('with no iCloud account the game just saves locally', () async {
    final cloud = MemoryCloudSaveStore(available: false);
    final a = Device(cloud, t);
    expect(await a.launch(), isA<KeepLocal>());
    await a.saves.save(started(t));
    await a.sync.flush();
    expect(a.local.primary, isNotNull);
    expect(cloud.writes, 0);
  });
}
