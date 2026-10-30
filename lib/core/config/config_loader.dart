import 'dart:convert';

import 'config_reader.dart';
import 'config_source.dart';
import 'game_config.dart';

/// Loads every config file listed in [GameConfig.files] and parses them into
/// a typed [GameConfig].
///
/// All failures (missing file, bad JSON, wrong shape) surface as a
/// [ConfigException] that names the file and field.
class ConfigLoader {
  ConfigLoader(this.source);

  final ConfigSource source;

  Future<GameConfig> load() async {
    final files = <String, ConfigReader>{};
    for (final name in GameConfig.files) {
      files[name] = await readFile(name);
    }
    return GameConfig.fromFiles(files);
  }

  /// Reads one file and checks it is a JSON object.
  Future<ConfigReader> readFile(String name) async {
    final String text;
    try {
      text = await source.read(name);
    } catch (e) {
      throw ConfigException('could not read config file "$name": $e');
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw ConfigException('$name.json is not valid JSON: ${e.message}');
    }
    if (json is! Map<String, dynamic>) {
      throw ConfigException('$name.json should hold a JSON object at the top');
    }
    return ConfigReader(json, name);
  }
}
