import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';

import '../core/clock/clock.dart';
import '../core/config/config_loader.dart';
import '../core/config/config_source.dart';
import '../core/save/save_repository.dart';
import '../core/save/save_storage.dart';
import '../core/state/game_state.dart';
import '../game/map/world_geometry.dart';
import 'providers.dart';

/// Loads config and the save, and returns the provider overrides the app runs
/// with. Tests pass their own [clock], [configSource] and [saveStorage].
Future<List<Override>> bootstrap({
  required ConfigSource configSource,
  Clock clock = const SystemClock(),
  SaveStorage? saveStorage,
}) async {
  final config = await ConfigLoader(configSource).load();
  final geometry = WorldGeometry.parse(await configSource.read('map/world'));

  final storage =
      saveStorage ??
      FileSaveStorage(
        Directory('${(await getApplicationSupportDirectory()).path}/saves'),
      );
  final saves = SaveRepository(storage: storage, clock: clock);
  final loaded = await saves.load();
  if (loaded.error != null) {
    debugPrint('Save problem (${loaded.status.name}): ${loaded.error}');
  }

  final state =
      loaded.state ??
      GameState.newGame(
        now: clock.now(),
        startingMoney: config.economy.startingMoney,
      );
  if (loaded.state == null) {
    await saves.save(state);
  }

  return [
    clockProvider.overrideWithValue(clock),
    gameConfigProvider.overrideWithValue(config),
    worldGeometryProvider.overrideWithValue(geometry),
    saveRepositoryProvider.overrideWithValue(saves),
    initialGameStateProvider.overrideWithValue(state),
  ];
}
