import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/asset_config_source.dart';
import 'app/bootstrap.dart';
import 'app/sounds.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final overrides = await bootstrap(configSource: AssetConfigSource());
  final sounds = await AudioSounds.load();
  runApp(
    ProviderScope(
      overrides: [...overrides, soundsProvider.overrideWithValue(sounds)],
      child: const TinyAirwaysApp(),
    ),
  );
}
