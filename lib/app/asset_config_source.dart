import 'package:flutter/services.dart';

import '../core/config/config_source.dart';

/// Reads config files bundled under `assets/config/`.
class AssetConfigSource implements ConfigSource {
  AssetConfigSource([AssetBundle? bundle]) : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;

  @override
  Future<String> read(String name) =>
      bundle.loadString('assets/config/$name.json', cache: false);
}
