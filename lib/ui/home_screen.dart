import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../game/tiny_airways_game.dart';
import '../game/world_map_view.dart';
import 'theme.dart';

/// The map is home; every other screen will be a sheet or panel over it.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Room the top bar takes over the map, below the safe area.
  static const _topBarHeight = 72.0;

  late final TinyAirwaysGame _game = TinyAirwaysGame(
    worldData: ref.read(gameConfigProvider).world,
    geometry: ref.read(worldGeometryProvider),
    clock: ref.read(clockProvider),
  );

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: WorldMapView(
              game: _game,
              insets: EdgeInsets.only(top: padding.top + _topBarHeight),
            ),
          ),
          const SafeArea(child: TopBar()),
        ],
      ),
    );
  }
}

/// Money and airline level, always visible.
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(gameSessionProvider.select((s) => s.player));
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: TinyColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Tiny Airways',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                color: TinyColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Lv ${player.level}',
            key: const Key('topBar.level'),
            style: text.bodyMedium?.copyWith(color: TinyColors.ink),
          ),
          const SizedBox(width: 12),
          Text(
            '${formatCoins(player.money)} coins',
            key: const Key('topBar.money'),
            style: text.bodyMedium?.copyWith(
              color: TinyColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 12500 -> "12,500".
String formatCoins(int coins) {
  final digits = coins.abs().toString();
  final buffer = StringBuffer(coins < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
