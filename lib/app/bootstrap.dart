import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';

import '../core/clock/clock.dart';
import '../core/config/config_loader.dart';
import '../core/config/config_source.dart';
import '../core/save/cloud_sync.dart';
import '../core/save/save_repository.dart';
import '../core/save/save_storage.dart';
import '../core/state/game_state.dart';
import '../game/map/world_geometry.dart';
import 'icloud_save_store.dart';
import 'providers.dart';

/// Loads config and the save, and returns the provider overrides the app runs
/// with. Tests pass their own [clock], [configSource] and [saveStorage], and
/// a [cloud] to test syncing (the app uses iCloud on iOS).
Future<List<Override>> bootstrap({
  required ConfigSource configSource,
  Clock clock = const SystemClock(),
  SaveStorage? saveStorage,
  CloudSaveStore? cloud,
  TextStore? syncMarker,
}) async {
  final config = await ConfigLoader(configSource).load();
  final geometry = WorldGeometry.parse(await configSource.read('map/world'));

  final folder = saveStorage == null
      ? Directory('${(await getApplicationSupportDirectory()).path}/saves')
      : null;
  final local = saveStorage ?? FileSaveStorage(folder!);
  final cloudStore =
      cloud ??
      (saveStorage == null && Platform.isIOS ? const ICloudSaveStore() : null);

  CloudSync? sync;
  var storage = local;
  if (cloudStore != null) {
    sync = CloudSync(
      cloud: cloudStore,
      marker:
          syncMarker ??
          (folder != null
              ? FileTextStore(File('${folder.path}/sync.json'))
              : MemoryTextStore()),
      saves: SaveRepository(storage: local, clock: clock),
      clock: clock,
    );
    storage = CloudSyncedStorage(local, sync);
  }
  final saves = SaveRepository(storage: storage, clock: clock);
  final loaded = await saves.load();
  if (loaded.error != null) {
    debugPrint('Save problem (${loaded.status.name}): ${loaded.error}');
  }

  var state = loaded.state;
  SyncConflict? conflict;
  if (sync != null) {
    final localText = loaded.state == null ? null : saves.encode(loaded.state!);
    switch (await sync.check(
      loaded.status == SaveLoadStatus.loaded
          ? await local.readPrimary()
          : localText,
    )) {
      case UseCloud(:final cloud):
        // Copied as it is, so it matches the cloud's copy exactly.
        await local.write(cloud.text);
        await sync.adopted(cloud);
        state = cloud.state;
      case final SyncConflict c:
        conflict = c;
      case KeepLocal():
        break;
    }
  }

  if (state == null) {
    state = GameState.newGame(
      now: clock.now(),
      startingMoney: config.economy.startingMoney,
    );
    await saves.save(state);
  }

  return [
    clockProvider.overrideWithValue(clock),
    gameConfigProvider.overrideWithValue(config),
    worldGeometryProvider.overrideWithValue(geometry),
    saveRepositoryProvider.overrideWithValue(saves),
    initialGameStateProvider.overrideWithValue(state),
    cloudSyncProvider.overrideWithValue(sync),
    initialCloudConflictProvider.overrideWithValue(conflict),
  ];
}
