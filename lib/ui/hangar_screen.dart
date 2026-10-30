import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'growth_sheets.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Hangar tab: planes for sale, hangar space, and the fleet's upgrades
/// and names.
class HangarScreen extends ConsumerWidget {
  const HangarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final growth = sim.growth;
    final config = sim.rules.config;
    final slots = growth.hangarSlots(state);
    final expansion = growth.hangarExpansionPrice(state);
    final canExpand = state.player.money >= expansion;

    return ColoredBox(
      color: Board.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: 'Hangar',
            subtitle: '${state.planes.length} of $slots slots used',
          ),
          Expanded(
            child: ListView(
              key: const Key('hangar.list'),
              padding: const EdgeInsets.all(16),
              children: [
                BoardSection(
                  title: 'For sale',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final m in config.planes.models) _ModelRow(model: m),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AmberButton(
                  key: const Key('hangar.expand'),
                  outlined: canExpand,
                  label: canExpand
                      ? 'Expand hangar +1 slot · ${formatCoins(expansion)}'
                      : 'Expand hangar · need ${formatCoins(expansion)}',
                  onPressed: canExpand
                      ? () => actOrExplain(
                          context,
                          ref,
                          (sim, s, now) => sim.buyHangarExpansion(s, now),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                BoardSection(
                  title: 'Your planes',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in state.planes)
                        GrowthRow(
                          key: Key('hangar.plane.${p.id}'),
                          title: '${flightNumber(p)} · ${planeName(config, p)}',
                          subtitle: _upgradeLine(config, p.upgrades),
                          onTap: () => showBoardSheet(
                            context,
                            PlaneUpgradeSheet(planeId: p.id),
                          ),
                          button: const Icon(
                            Icons.chevron_right,
                            color: Board.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _upgradeLine(GameConfig config, PlaneUpgrades u) {
    final max = config.planes.upgrades.maxLevel;
    return 'Capacity ${u.capacity}/$max · Speed ${u.speed}/$max · '
        'Range ${u.range}/$max';
  }
}

class _ModelRow extends ConsumerWidget {
  const _ModelRow({required this.model});

  final PlaneModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final growth = sim.growth;
    final cls = sim.rules.config.planes.planeClass(model.classId).name;
    final problem = growth.buyPlaneProblem(state, model);
    final locked = problem == RuleError.levelTooLow;
    final kind = model.seats == 0
        ? ' · cargo only'
        : model.cargoSlots == 0
        ? ' · passengers only'
        : '';
    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: GrowthRow(
        key: Key('hangar.model.${model.id}'),
        leading: Icon(
          Icons.flight,
          color: locked ? Board.muted : Board.amber,
          size: 22,
        ),
        title: '${model.name} · $cls$kind',
        subtitle: locked
            ? 'Unlocks at airline Lv ${growth.unlockLevel(model)}'
            : '${model.seats} seats · ${model.cargoSlots} cargo · '
                  '${formatKm(model.rangeKm.toDouble())} · '
                  '${model.speedKmh} km/h',
        button: AmberButton(
          key: Key('hangar.buy.${model.id}'),
          mono: true,
          height: 34,
          label: locked
              ? 'Lv ${growth.unlockLevel(model)}'
              : priceLabel(problem, model.price!),
          onPressed: problem == null
              ? () {
                  if (actOrExplain(
                    context,
                    ref,
                    (sim, s, now) => sim.buyPlane(s, model.id, now),
                  )) {
                    final s = ref.read(gameSessionProvider);
                    final city = sim.rules.world.city(s.planes.last.cityId);
                    showToast(
                      context,
                      '${model.name} is waiting at ${city.name}.',
                    );
                  }
                }
              : null,
        ),
      ),
    );
  }
}
