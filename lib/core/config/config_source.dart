import 'dart:io';

/// Where config JSON files come from.
///
/// The app reads them from the asset bundle (see `AssetConfigSource` in
/// `lib/app`), tests read them from disk or from memory. Keeping this
/// interface free of Flutter imports lets the loader live in the pure logic
/// layer.
abstract interface class ConfigSource {
  /// Returns the raw text of the config file called [name] (without the
  /// `.json` extension), or throws if it does not exist.
  Future<String> read(String name);
}

/// Reads `<directory>/<name>.json` from the file system. Used by tests and
/// tools that run outside Flutter.
class DirectoryConfigSource implements ConfigSource {
  DirectoryConfigSource(this.directory);

  final String directory;

  @override
  Future<String> read(String name) =>
      File('$directory/$name.json').readAsString();
}

/// Serves config text from a map. Handy for tests of broken or edge-case
/// configs.
class MemoryConfigSource implements ConfigSource {
  MemoryConfigSource(this.files);

  final Map<String, String> files;

  @override
  Future<String> read(String name) async {
    final text = files[name];
    if (text == null) {
      throw FileSystemException('No config file called "$name"');
    }
    return text;
  }
}
