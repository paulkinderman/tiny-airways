import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/clock/clock.dart';
import '../core/config/game_config.dart';
import '../core/save/cloud_sync.dart';
import '../core/save/save_repository.dart';
import '../core/state/game_state.dart';
import '../game/map/world_geometry.dart';
import '../logic/simulation.dart';

/// Services created once at startup by `bootstrap()` and injected with
/// `ProviderScope(overrides: ...)`. Tests override them the same way.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

final gameConfigProvider = Provider<GameConfig>(
  (ref) => throw UnimplementedError('gameConfigProvider must be overridden'),
);

/// The world map's land, from `assets/map/world.json`.
final worldGeometryProvider = Provider<WorldGeometry>(
  (ref) => throw UnimplementedError('worldGeometryProvider must be overridden'),
);

final saveRepositoryProvider = Provider<SaveRepository>(
  (ref) =>
      throw UnimplementedError('saveRepositoryProvider must be overridden'),
);

/// The state loaded (or created) at startup.
final initialGameStateProvider = Provider<GameState>(
  (ref) =>
      throw UnimplementedError('initialGameStateProvider must be overridden'),
);

/// The game rules, with the crew's bonuses plugged in.
final simulationProvider = Provider<Simulation>((ref) {
  final config = ref.watch(gameConfigProvider);
  return Simulation(
    Rules(config, crew: GameCrew(config)),
    utcOffset: ref.watch(utcOffsetProvider),
  );
});

/// The device's time zone, so daily challenges roll at local midnight.
final utcOffsetProvider = Provider<Duration>(
  (ref) => DateTime.now().timeZoneOffset,
);

/// iCloud save sync, or null where there is none (tests, Android for now).
final cloudSyncProvider = Provider<CloudSync?>((ref) => null);

/// A disagreement between this device's airline and the cloud's, waiting
/// for the player to pick one. While it is set the app shows the picker.
final cloudConflictProvider =
    NotifierProvider<CloudConflictNotifier, SyncConflict?>(
      CloudConflictNotifier.new,
    );

/// Bootstrap's conflict, if launching found one.
final initialCloudConflictProvider = Provider<SyncConflict?>((ref) => null);

class CloudConflictNotifier extends Notifier<SyncConflict?> {
  @override
  SyncConflict? build() => ref.read(initialCloudConflictProvider);

  void show(SyncConflict conflict) => state = conflict;

  /// Keeps one airline, sends it up, and closes the picker.
  Future<void> choose({required bool keepLocal}) async {
    final conflict = state;
    final sync = ref.read(cloudSyncProvider);
    if (conflict == null || sync == null) return;
    final kept = await sync.choose(conflict, keepLocal: keepLocal);
    if (!keepLocal) {
      await ref.read(gameSessionProvider.notifier).update((_) => kept);
    }
    state = null;
  }
}

/// What happened while the player was away, set by [GameSession.tick] when
/// it catches up a gap of [GameSession.welcomeBackAfter] or more. The home
/// screen shows it and clears it.
final welcomeBackProvider = NotifierProvider<WelcomeBackNotifier, WelcomeBack?>(
  WelcomeBackNotifier.new,
);

class WelcomeBack {
  const WelcomeBack({required this.away, required this.report});

  final Duration away;
  final SimReport report;
}

class WelcomeBackNotifier extends Notifier<WelcomeBack?> {
  @override
  WelcomeBack? build() => null;

  void show(WelcomeBack summary) => state = summary;
  void dismiss() => state = null;
}

/// The live game state. Every change goes through [GameSession.update], which
/// auto-saves, so the game is saved after every action.
final gameSessionProvider = NotifierProvider<GameSession, GameState>(
  GameSession.new,
);

class GameSession extends Notifier<GameState> {
  /// A gap this long between ticks (the app was closed or in the
  /// background) gets a welcome-back summary.
  static const welcomeBackAfter = Duration(minutes: 1);

  @override
  GameState build() => ref.read(initialGameStateProvider);

  // States are immutable, so a new object always means a change; comparing
  // them field by field every tick would be wasted work.
  @override
  bool updateShouldNotify(GameState previous, GameState next) =>
      !identical(previous, next);

  Simulation get _sim => ref.read(simulationProvider);

  /// Runs the world up to now: landings, weather and board rotations. The
  /// home screen calls it every second; it saves only when something
  /// happened. After a long gap it posts a welcome-back summary.
  SimReport tick() {
    final before = state;
    final now = ref.read(clockProvider).now();
    final (next, report) = _sim.advance(before, now);
    if (identical(next, before)) return report;
    state = next;
    final away = now.difference(before.simulatedTo);
    if (before.hasStarted && away >= welcomeBackAfter && !report.isEmpty) {
      ref
          .read(welcomeBackProvider.notifier)
          .show(WelcomeBack(away: away, report: report));
    }
    if (!report.isEmpty ||
        next.boardRotation != before.boardRotation ||
        next.weather.events.length != before.weather.events.length) {
      persist();
    }
    return report;
  }

  /// Runs a player action through the rules at the current time and saves
  /// the result. Returns why the rules refused it, or null if it happened.
  RuleError? act(
    GameState Function(Simulation sim, GameState state, DateTime now) action,
  ) {
    try {
      final next = action(_sim, state, ref.read(clockProvider).now());
      update((_) => next);
      return null;
    } on RuleException catch (e) {
      return e.error;
    }
  }

  /// Applies [change] to the state and saves the result.
  Future<void> update(GameState Function(GameState state) change) {
    state = change(state);
    return persist();
  }

  /// Checks the cloud copy (on returning to the foreground): switches to it
  /// if another device played since, or asks the player if both did.
  Future<void> syncWithCloud() async {
    final sync = ref.read(cloudSyncProvider);
    if (sync == null) return;
    final decision = await sync.check(null);
    switch (decision) {
      case UseCloud(:final cloud):
        await sync.adopted(cloud);
        await update((_) => cloud.state);
      case SyncConflict():
        ref.read(cloudConflictProvider.notifier).show(decision);
      case KeepLocal():
        break;
    }
  }

  /// Saves now and sends the save to the cloud (when the app goes to the
  /// background).
  Future<void> persistAndUpload() async {
    await persist();
    await ref.read(cloudSyncProvider)?.flush();
  }

  /// Saves the current state, stamping when the player was last here. Called
  /// after every action and when the app goes to the background.
  Future<void> persist() {
    state = state.copyWith(lastSeenAt: ref.read(clockProvider).now());
    return ref.read(saveRepositoryProvider).save(state);
  }
}
