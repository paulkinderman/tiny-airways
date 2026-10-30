import 'dart:async';
import 'dart:convert';

import '../clock/clock.dart';
import '../state/game_state.dart';
import 'save_migrations.dart';
import 'save_storage.dart';

/// Thrown when a save can't be turned into a [GameState].
class SaveException implements Exception {
  SaveException(this.message);

  final String message;

  @override
  String toString() => 'SaveException: $message';
}

enum SaveLoadStatus {
  /// No save exists: start a new game.
  none,

  /// The current save loaded.
  loaded,

  /// The current save was unreadable, so the backup loaded instead.
  recoveredFromBackup,

  /// Neither save could be read. They have been moved aside (not deleted)
  /// and a new game should start.
  unreadable,
}

class SaveLoadResult {
  const SaveLoadResult(this.status, [this.state, this.error]);

  final SaveLoadStatus status;
  final GameState? state;

  /// Why the primary save (or both saves) failed to load, if they did.
  final Object? error;
}

/// Loads and saves the game as one versioned JSON document:
///
/// ```json
/// {"version": 1, "savedAt": "2026-10-30T20:00:00.000Z", "state": {...}}
/// ```
///
/// Older saves are upgraded through [migrations] on load. Saves are written
/// one at a time in the order [save] is called.
class SaveRepository {
  SaveRepository({
    required this.storage,
    required this.clock,
    this.version = currentSaveVersion,
    this.migrations = saveMigrations,
  });

  final SaveStorage storage;
  final Clock clock;
  final int version;
  final Map<int, SaveMigration> migrations;

  Future<void> _lastWrite = Future.value();

  Future<SaveLoadResult> load() async {
    final primary = await storage.readPrimary();
    final backup = await storage.readBackup();
    if (primary == null && backup == null) {
      return const SaveLoadResult(SaveLoadStatus.none);
    }

    Object? primaryError;
    if (primary != null) {
      try {
        return SaveLoadResult(SaveLoadStatus.loaded, decode(primary));
      } catch (e) {
        primaryError = e;
      }
    }
    if (backup != null) {
      try {
        return SaveLoadResult(
          SaveLoadStatus.recoveredFromBackup,
          decode(backup),
          primaryError,
        );
      } catch (_) {
        // Fall through: neither save is usable.
      }
    }
    await storage.quarantine();
    return SaveLoadResult(SaveLoadStatus.unreadable, null, primaryError);
  }

  /// Writes [state], stamping it with the current time.
  Future<void> save(GameState state) {
    final text = encode(state);
    return _lastWrite = _lastWrite
        .catchError((_) {})
        .then((_) => storage.write(text));
  }

  String encode(GameState state) => jsonEncode({
    'version': version,
    'savedAt': clock.now().toIso8601String(),
    'state': state.toJson(),
  });

  GameState decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw SaveException('save is not valid JSON: ${e.message}');
    }
    if (json is! Map<String, dynamic>) {
      throw SaveException('save is not a JSON object');
    }
    final fileVersion = json['version'];
    final rawState = json['state'];
    if (fileVersion is! int || rawState is! Map<String, dynamic>) {
      throw SaveException('save is missing its version or state');
    }
    var state = rawState;
    if (fileVersion > version) {
      throw SaveException(
        'save is version $fileVersion but this build only reads up to '
        '$version',
      );
    }
    for (var v = fileVersion; v < version; v++) {
      final migrate = migrations[v];
      if (migrate == null) {
        throw SaveException('no migration from save version $v to ${v + 1}');
      }
      state = migrate(state);
    }
    try {
      return GameState.fromJson(state);
    } catch (e) {
      throw SaveException('save state has the wrong shape: $e');
    }
  }
}
