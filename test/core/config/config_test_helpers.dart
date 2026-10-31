import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_reader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';

/// The shipped JSON files keyed by path under `assets/`, without `.json`
/// (`config/economy`, `data/cities`, ...).
Map<String, String> shippedFiles() => {
  for (final file in Directory('assets').listSync(recursive: true))
    if (file is File && file.path.endsWith('.json'))
      file.path.substring('assets/'.length, file.path.length - '.json'.length):
          file.readAsStringSync(),
};

/// Loads the shipped files after letting [edit] change one of them.
Future<GameConfig> loadEdited(
  String path,
  void Function(Map<String, dynamic> json) edit,
) {
  final files = shippedFiles();
  final json = jsonDecode(files[path]!) as Map<String, dynamic>;
  edit(json);
  files[path] = jsonEncode(json);
  return ConfigLoader(MemoryConfigSource(files)).load();
}

Matcher throwsConfig(String messagePart) => throwsA(
  isA<ConfigException>().having(
    (e) => e.message,
    'message',
    contains(messagePart),
  ),
);
