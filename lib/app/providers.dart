import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/clock/clock.dart';
import '../core/config/game_config.dart';
import '../core/save/save_repository.dart';
import '../core/state/game_state.dart';

/// Services created once at startup by `bootstrap()` and injected with
/// `ProviderScope(overrides: ...)`. Tests override them the same way.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

final gameConfigProvider = Provider<GameConfig>(
  (ref) => throw UnimplementedError('gameConfigProvider must be overridden'),
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

/// The live game state. Every change goes through [GameSession.update], which
/// auto-saves, so the game is saved after every action.
final gameSessionProvider = NotifierProvider<GameSession, GameState>(
  GameSession.new,
);

class GameSession extends Notifier<GameState> {
  @override
  GameState build() => ref.read(initialGameStateProvider);

  /// Applies [change] to the state and saves the result.
  Future<void> update(GameState Function(GameState state) change) {
    state = change(state);
    return persist();
  }

  /// Saves the current state, stamping when the player was last here. Called
  /// after every action and when the app goes to the background.
  Future<void> persist() {
    state = state.copyWith(lastSeenAt: ref.read(clockProvider).now());
    return ref.read(saveRepositoryProvider).save(state);
  }
}
