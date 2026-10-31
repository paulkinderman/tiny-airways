import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/sounds.dart';
import '../core/state/game_state.dart';
import 'split_flap.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'ui_state.dart';

/// Sits over the whole app and adds the feel: sound cues for take-offs,
/// landings, level-ups and the departures board, and the split-flap
/// "promotion" banner when the airline earns a new title.
///
/// It only watches the game state; it never changes it.
class FeelLayer extends ConsumerStatefulWidget {
  const FeelLayer({required this.child, super.key});

  final Widget child;

  /// How long the promotion banner stays up.
  static const promotionTime = Duration(milliseconds: 4200);

  @override
  ConsumerState<FeelLayer> createState() => _FeelLayerState();
}

class Promotion {
  const Promotion({required this.from, required this.to, required this.level});

  final String from;
  final String to;
  final int level;
}

class _FeelLayerState extends ConsumerState<FeelLayer> {
  Promotion? _promotion;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _onState(GameState? before, GameState after) {
    if (before == null || identical(before, after)) return;
    final sounds = ref.read(soundsProvider);

    var departed = false;
    var landed = false;
    final was = {for (final p in before.planes) p.id: p};
    for (final p in after.planes) {
      final old = was[p.id];
      if (old == null) continue;
      if (old.status == PlaneStatus.parked && p.status != PlaneStatus.parked) {
        departed = true;
      } else if (old.status != PlaneStatus.parked &&
          p.status == PlaneStatus.parked) {
        landed = true;
      }
    }
    if (departed) sounds.play(Sfx.takeoff);
    if (landed) sounds.play(Sfx.coins);

    final from = before.player.level;
    final to = after.player.level;
    if (to <= from) return;
    final titles = ref.read(gameConfigProvider).progression;
    final oldTitle = titles.titleFor(from);
    final newTitle = titles.titleFor(to);
    if (oldTitle == newTitle) {
      sounds.play(Sfx.level);
      return;
    }
    sounds.play(Sfx.promotion);
    setState(
      () => _promotion = Promotion(from: oldTitle, to: newTitle, level: to),
    );
    _hide?.cancel();
    _hide = Timer(FeelLayer.promotionTime, _dismiss);
  }

  void _dismiss() {
    _hide?.cancel();
    if (mounted && _promotion != null) setState(() => _promotion = null);
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(gameSessionProvider, _onState)
      ..listen(uiProvider.select((ui) => ui.tab), (before, after) {
        if (after == HomeTab.fleet && before != after) {
          ref.read(soundsProvider).play(Sfx.flap);
        }
      });
    final top = MediaQuery.paddingOf(context).top + TopBar.height + 8;
    final promotion = _promotion;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 16,
          right: 16,
          top: top,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween(begin: const Offset(0, -0.4), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: promotion == null
                ? const SizedBox.shrink()
                : SizedBox(
                    key: ValueKey(promotion.to),
                    width: double.infinity,
                    child: PromotionBanner(
                      promotion: promotion,
                      onTap: _dismiss,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// "PROMOTED": the old title on a flap board, which then flips over to the
/// new one.
class PromotionBanner extends StatefulWidget {
  const PromotionBanner({required this.promotion, this.onTap, super.key});

  final Promotion promotion;
  final VoidCallback? onTap;

  /// How long the old title shows before the board flips.
  static const flipAfter = Duration(milliseconds: 450);

  @override
  State<PromotionBanner> createState() => _PromotionBannerState();
}

class _PromotionBannerState extends State<PromotionBanner> {
  late String _shown = widget.promotion.from;
  Timer? _flip;

  @override
  void initState() {
    super.initState();
    _flip = Timer(PromotionBanner.flipAfter, () {
      if (mounted) setState(() => _shown = widget.promotion.to);
    });
  }

  @override
  void dispose() {
    _flip?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.promotion;
    // Pad the board to the longer title so it doesn't jump in width.
    final width = p.from.length > p.to.length ? p.from.length : p.to.length;
    return Semantics(
      liveRegion: true,
      label: 'Promoted to ${p.to}, airline level ${p.level}',
      excludeSemantics: true,
      child: Material(
        key: const Key('promotion.banner'),
        color: Board.flap,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Board.amber, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PROMOTED · AIRLINE LV ${p.level}',
                  style: Board.flapStyle(
                    size: 11,
                    color: Board.muted,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Board.raised,
                        Board.raised,
                        Board.flap,
                        Board.flap,
                      ],
                      stops: [0, 0.5, 0.5, 1],
                    ),
                  ),
                  child: SplitFlapText(
                    _shown.toUpperCase().padRight(width),
                    maxFlips: 10,
                    flipTime: const Duration(milliseconds: 60),
                    stagger: const Duration(milliseconds: 45),
                    style: Board.flapStyle(size: 22, weight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
