import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // Save whenever the app leaves the foreground.
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(gameSessionProvider.notifier).persist(),
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
    home: const HomeScreen(),
  );
}
