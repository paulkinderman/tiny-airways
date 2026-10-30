import 'package:flutter/services.dart';

import '../core/config/config_source.dart';

/// Reads config and data files bundled under `assets/`.
class AssetConfigSource implements ConfigSource {
  AssetConfigSource([AssetBundle? bundle]) : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;

  @override
  Future<String> read(String name) =>
      bundle.loadString('assets/$name.json', cache: false);
}
