import 'dart:convert';

import 'config_reader.dart';
import 'config_source.dart';
import 'game_config.dart';

/// Loads every file listed in [GameConfig.files] (from `config/`) and
/// [GameConfig.dataFiles] (from `data/`) and parses them into a typed
/// [GameConfig].
///
/// All failures (missing file, bad JSON, wrong shape) surface as a
/// [ConfigException] that names the file and field.
class ConfigLoader {
  ConfigLoader(this.source);

  final ConfigSource source;

  Future<GameConfig> load() async {
    final files = <String, ConfigReader>{};
    for (final name in GameConfig.files) {
      files[name] = await readFile('config', name);
    }
    final data = <String, ConfigReader>{};
    for (final name in GameConfig.dataFiles) {
      data[name] = await readFile('data', name);
    }
    return GameConfig.fromFiles(files, data);
  }

  /// Reads `<folder>/<name>.json` and checks it is a JSON object. Error
  /// paths start with [name], or `data/<name>` for data files.
  Future<ConfigReader> readFile(String folder, String name) async {
    final label = folder == 'config' ? name : '$folder/$name';
    final String text;
    try {
      text = await source.read('$folder/$name');
    } catch (e) {
      throw ConfigException('could not read config file "$folder/$name": $e');
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw ConfigException('$label.json is not valid JSON: ${e.message}');
    }
    if (json is! Map<String, dynamic>) {
      throw ConfigException('$label.json should hold a JSON object at the top');
    }
    return ConfigReader(json, label);
  }
}
