import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import 'format.dart';
import 'split_flap.dart';
import 'theme.dart';

/// Money, airline level and title, and the planes waiting to be dispatched,
/// always in view. Tapping the waiting count jumps to the next idle plane.
class TopBar extends ConsumerWidget {
  const TopBar({this.onWaitingTap, this.onLevelTap, super.key});

  static const height = 64.0;

  final VoidCallback? onWaitingTap;

  /// Opens the airline's level, unlocks and network stats.
  final VoidCallback? onLevelTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(gameSessionProvider.select((s) => s.player));
    final waiting = ref.watch(
      gameSessionProvider.select(
        (s) => s.planes.where((p) => p.status == PlaneStatus.parked).length,
      ),
    );
    final progression = ref.watch(gameConfigProvider).progression;
    final atMax = player.level >= progression.maxLevel;
    final progress = atMax
        ? 1.0
        : (player.xp / progression.xpToNext(player.level)).clamp(0.0, 1.0);

    // On the smallest phones the waiting button shows just the count.
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Board.ground,
      child: Row(
        children: [
          // Big balances shrink to fit rather than push the bar off screen.
          Flexible(
            child: Container(
              key: const Key('topBar.money'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Board.panel,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _CoinIcon(),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatCoins(player.money),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Board.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              key: const Key('topBar.airline'),
              behavior: HitTestBehavior.opaque,
              onTap: onLevelTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Airline Lv ${player.level}',
                    key: const Key('topBar.level'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Board.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: Board.line,
                      color: Board.amber,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // The airline's title flips over when it changes.
                  SplitFlapText(
                    progression.titleFor(player.level).toUpperCase(),
                    key: const Key('topBar.title'),
                    style: Board.flapStyle(size: 10, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            label: '$waiting waiting. Jump to the next idle plane.',
            excludeSemantics: true,
            child: Material(
              color: waiting > 0 ? Board.amber : Board.panel,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('topBar.waiting'),
                onTap: waiting > 0 ? onWaitingTap : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.send_rounded,
                        size: 16,
                        color: waiting > 0 ? Board.amberInk : Board.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        compact ? '$waiting' : '$waiting waiting',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: waiting > 0 ? Board.amberInk : Board.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinIcon extends StatelessWidget {
  const _CoinIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: const BoxDecoration(color: Board.amber, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const Text(
      '\$',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Board.amberInk,
        height: 1,
      ),
    ),
  );
}
