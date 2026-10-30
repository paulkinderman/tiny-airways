import 'dart:convert';
import 'dart:io';

import '../clock/clock.dart';
import '../state/game_state.dart';
import 'save_repository.dart';
import 'save_storage.dart';

/// Where the cloud copy of the save lives: iCloud on iOS (see
/// `lib/app/icloud_save_store.dart`), Google Play saved games later on
/// Android. It holds one save document, the same text as `save.json`.
abstract interface class CloudSaveStore {
  /// Whether the player is signed in to the cloud service.
  Future<bool> isAvailable();

  /// The cloud copy, or null if there is none.
  Future<String?> read();

  Future<void> write(String text);
}

/// A cloud in memory, for tests (two devices can share one).
class MemoryCloudSaveStore implements CloudSaveStore {
  MemoryCloudSaveStore({this.text, this.available = true});

  String? text;
  bool available;
  int writes = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> read() async => available ? text : null;

  @override
  Future<void> write(String text) async {
    if (!available) return;
    this.text = text;
    writes++;
  }
}

/// A small text file kept next to the save. Holds the sync marker.
abstract interface class TextStore {
  Future<String?> read();
  Future<void> write(String text);
}

class MemoryTextStore implements TextStore {
  MemoryTextStore([this.text]);

  String? text;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String text) async => this.text = text;
}

class FileTextStore implements TextStore {
  FileTextStore(this.file);

  final File file;

  @override
  Future<String?> read() async =>
      await file.exists() ? file.readAsString() : null;

  @override
  Future<void> write(String text) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(text, flush: true);
  }
}

/// The side-by-side summary the conflict picker shows for each airline.
class SaveSummary {
  const SaveSummary({
    required this.savedAt,
    required this.money,
    required this.level,
    required this.planes,
    required this.airports,
    required this.homeCityId,
  });

  factory SaveSummary.of(GameState state, DateTime savedAt) => SaveSummary(
    savedAt: savedAt,
    money: state.player.money,
    level: state.player.level,
    planes: state.planes.length,
    airports: state.airports.length,
    homeCityId: state.homeCityId,
  );

  final DateTime savedAt;
  final int money;
  final int level;
  final int planes;
  final int airports;
  final String? homeCityId;
}

/// One readable save document.
class SyncedSave {
  const SyncedSave({
    required this.text,
    required this.state,
    required this.savedAt,
  });

  final String text;
  final GameState state;
  final DateTime savedAt;

  SaveSummary get summary => SaveSummary.of(state, savedAt);
}

/// What to do after comparing this device's save with the cloud copy.
sealed class SyncDecision {
  const SyncDecision();
}

/// Keep playing the local save; it goes up to the cloud as it saves.
class KeepLocal extends SyncDecision {
  const KeepLocal();
}

/// The cloud copy is newer and this device hasn't played since it last
/// synced: switch to it without asking.
class UseCloud extends SyncDecision {
  const UseCloud(this.cloud);
  final SyncedSave cloud;
}

/// Both this device and another one played since they last agreed. The
/// player picks which airline to keep.
class SyncConflict extends SyncDecision {
  const SyncConflict({required this.local, required this.cloud});
  final SyncedSave local;
  final SyncedSave cloud;
}

/// Keeps the save in step with the cloud copy.
///
/// It remembers (in a marker next to the save) the `savedAt` of the last
/// save document this device and the cloud agreed on. On launch and when the
/// app comes back to the foreground, [check] compares:
///
/// - cloud unchanged since then: this device's save wins and goes up;
/// - cloud changed, but this device hasn't saved since: take the cloud copy;
/// - both changed: a [SyncConflict] for the player to settle with [choose].
///
/// A cloud copy from a newer build is never overwritten: syncing pauses
/// until this build is updated.
class CloudSync {
  CloudSync({
    required this.cloud,
    required this.marker,
    required this.saves,
    required this.clock,
    this.pushEvery = const Duration(seconds: 30),
  });

  final CloudSaveStore cloud;
  final TextStore marker;
  final SaveRepository saves;
  final Clock clock;

  /// Saves go up at most this often while playing; [flush] sends the latest
  /// at once (when the app goes to the background).
  final Duration pushEvery;

  String? _pending;
  String? _latest;
  DateTime? _lastPush;
  bool _blocked = false;

  /// Nothing goes up until a [check] has read the cloud (or the player has
  /// settled a conflict), so a fresh install can't overwrite an airline.
  bool _ready = false;
  bool _cloudRead = false;
  Future<void> _lastWrite = Future.value();

  /// True when the cloud copy came from a newer build, so nothing is sent.
  bool get isBlocked => _blocked;

  /// The latest save document written on this device.
  String? get latestLocal => _latest;

  static DateTime? savedAtOf(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      return DateTime.tryParse(json['savedAt'] as String? ?? '')?.toUtc();
    } on FormatException {
      return null;
    }
  }

  SyncedSave? _parse(String? text) {
    if (text == null) return null;
    final savedAt = savedAtOf(text);
    if (savedAt == null) return null;
    return SyncedSave(text: text, state: saves.decode(text), savedAt: savedAt);
  }

  Future<({DateTime? local, DateTime? cloud})> _readMarker() async {
    try {
      final text = await marker.read();
      if (text == null) return (local: null, cloud: null);
      final json = jsonDecode(text) as Map<String, dynamic>;
      DateTime? at(String key) =>
          DateTime.tryParse(json[key] as String? ?? '')?.toUtc();
      return (local: at('localSavedAt'), cloud: at('cloudSavedAt'));
    } catch (_) {
      return (local: null, cloud: null);
    }
  }

  Future<void> _writeMarker(DateTime local, DateTime cloud) => marker.write(
    jsonEncode({
      'localSavedAt': local.toIso8601String(),
      'cloudSavedAt': cloud.toIso8601String(),
    }),
  );

  /// Compares [localText] (this device's latest save document, or null for
  /// none) with the cloud copy. Never throws: with no cloud, or a cloud
  /// that can't be read, the local save carries on.
  Future<SyncDecision> check(String? localText) async {
    _cloudRead = false;
    final decision = await _decide(localText ?? _latest);
    if (decision is KeepLocal && _cloudRead) _ready = true;
    return decision;
  }

  Future<SyncDecision> _decide(String? localText) async {
    final String? cloudText;
    try {
      if (!await cloud.isAvailable()) return const KeepLocal();
      cloudText = await cloud.read();
    } catch (_) {
      return const KeepLocal();
    }
    _cloudRead = true;
    if (cloudText == null) {
      _blocked = false;
      return const KeepLocal();
    }
    final SyncedSave? remote;
    try {
      remote = _parse(cloudText);
    } on SaveException {
      // Most likely saved by a newer build on another device.
      _blocked = true;
      return const KeepLocal();
    }
    _blocked = false;
    if (remote == null) return const KeepLocal();

    final mark = await _readMarker();
    if (mark.cloud == remote.savedAt) return const KeepLocal();

    final SyncedSave? local;
    try {
      local = _parse(localText);
    } on SaveException {
      return UseCloud(remote);
    }
    if (local == null || !local.state.hasStarted) {
      return remote.state.hasStarted ? UseCloud(remote) : const KeepLocal();
    }
    if (!remote.state.hasStarted) return const KeepLocal();
    if (mark.local != null && mark.local == local.savedAt) {
      return UseCloud(remote);
    }
    if (local.state == remote.state) {
      await _writeMarker(local.savedAt, remote.savedAt);
      return const KeepLocal();
    }
    return SyncConflict(local: local, cloud: remote);
  }

  /// Records that this device now plays [cloud] (after [UseCloud], or the
  /// player picking the cloud airline).
  Future<void> adopted(SyncedSave cloud) async {
    _pending = null;
    _ready = true;
    await _writeMarker(cloud.savedAt, cloud.savedAt);
  }

  /// Settles a conflict: [keepLocal] sends this device's airline up now;
  /// otherwise the cloud airline is adopted. Returns the airline to play.
  Future<GameState> choose(SyncConflict conflict, {required bool keepLocal}) {
    if (!keepLocal) {
      return adopted(conflict.cloud).then((_) => conflict.cloud.state);
    }
    _pending = conflict.local.text;
    _ready = true;
    return flush().then((_) => conflict.local.state);
  }

  /// Called with every save document written locally. Sends it up if the
  /// last push was long enough ago; otherwise it waits for the next one or
  /// [flush].
  Future<void> saved(String text) {
    _pending = text;
    _latest = text;
    final last = _lastPush;
    if (last != null && clock.now().difference(last) < pushEvery) {
      return Future.value();
    }
    return flush();
  }

  /// Sends the latest local save up now.
  Future<void> flush() {
    final text = _pending;
    if (text == null || _blocked || !_ready) return _lastWrite;
    _pending = null;
    _lastPush = clock.now();
    return _lastWrite = _lastWrite.catchError((_) {}).then((_) async {
      final savedAt = savedAtOf(text);
      if (savedAt == null) return;
      try {
        if (!await cloud.isAvailable()) return;
        await cloud.write(text);
        await _writeMarker(savedAt, savedAt);
      } catch (_) {
        // Offline or signed out: the next save tries again.
        _pending ??= text;
      }
    });
  }
}

/// A [SaveStorage] that also hands every save to [CloudSync], so the cloud
/// copy follows the local one.
class CloudSyncedStorage implements SaveStorage {
  CloudSyncedStorage(this.local, this.sync);

  final SaveStorage local;
  final CloudSync sync;

  @override
  Future<String?> readPrimary() => local.readPrimary();

  @override
  Future<String?> readBackup() => local.readBackup();

  @override
  Future<void> write(String text) async {
    await local.write(text);
    await sync.saved(text);
  }

  @override
  Future<void> quarantine() => local.quarantine();
}
