import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/cloud_conflict_screen.dart';
import '../ui/home_screen.dart';
import '../ui/theme.dart';
import 'providers.dart';

class TinyAirwaysApp extends ConsumerStatefulWidget {
  const TinyAirwaysApp({super.key});

  @override
  ConsumerState<TinyAirwaysApp> createState() => _TinyAirwaysAppState();
}

class _TinyAirwaysAppState extends ConsumerState<TinyAirwaysApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Save (and send the save to iCloud) whenever the app leaves the
    // foreground; on return, pick up anything another device played.
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(gameSessionProvider.notifier).persistAndUpload(),
      onResume: () => ref.read(gameSessionProvider.notifier).syncWithCloud(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tiny Airways',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: ref.watch(cloudConflictProvider) == null
        ? const HomeScreen()
        : const CloudConflictScreen(),
  );
}
