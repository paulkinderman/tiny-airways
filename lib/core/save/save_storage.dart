import 'dart:io';

/// Where the save document's text is kept.
///
/// There is one save slot. Each write keeps the previous save as a backup, so
/// a write cut short (the app killed mid-save) never loses the airline.
abstract interface class SaveStorage {
  /// The current save, or null if there is none.
  Future<String?> readPrimary();

  /// The save before the current one, or null if there is none.
  Future<String?> readBackup();

  /// Replaces the current save with [text]; the old one becomes the backup.
  Future<void> write(String text);

  /// Moves unreadable saves out of the way (without deleting them) so a new
  /// game can start without overwriting them.
  Future<void> quarantine();
}

/// Keeps saves in memory. For tests.
class MemorySaveStorage implements SaveStorage {
  MemorySaveStorage({this.primary, this.backup});

  String? primary;
  String? backup;
  final List<String> quarantined = [];

  @override
  Future<String?> readPrimary() async => primary;

  @override
  Future<String?> readBackup() async => backup;

  @override
  Future<void> write(String text) async {
    backup = primary;
    primary = text;
  }

  @override
  Future<void> quarantine() async {
    quarantined.addAll([?primary, ?backup]);
    primary = null;
    backup = null;
  }
}

/// Keeps `save.json` and `save.backup.json` in [directory].
///
/// Writes go to a temporary file first and are then renamed into place, so
/// `save.json` is always either the old or the new save, never half of one.
class FileSaveStorage implements SaveStorage {
  FileSaveStorage(this.directory);

  final Directory directory;

  File get _primary => File('${directory.path}/save.json');
  File get _backup => File('${directory.path}/save.backup.json');
  File get _temp => File('${directory.path}/save.json.tmp');

  @override
  Future<String?> readPrimary() => _readIfExists(_primary);

  @override
  Future<String?> readBackup() => _readIfExists(_backup);

  Future<String?> _readIfExists(File file) async =>
      await file.exists() ? file.readAsString() : null;

  @override
  Future<void> write(String text) async {
    await directory.create(recursive: true);
    await _temp.writeAsString(text, flush: true);
    if (await _primary.exists()) {
      await _primary.rename(_backup.path);
    }
    await _temp.rename(_primary.path);
  }

  @override
  Future<void> quarantine() async {
    for (final file in [_primary, _backup]) {
      if (!await file.exists()) continue;
      final name = file.uri.pathSegments.last.replaceAll('.json', '');
      var n = 1;
      while (await File(_unreadablePath(name, n)).exists()) {
        n++;
      }
      await file.rename(_unreadablePath(name, n));
    }
  }

  String _unreadablePath(String name, int n) =>
      '${directory.path}/$name.unreadable-$n.json';
}
