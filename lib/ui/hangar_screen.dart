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

/// The Hangar tab: planes for sale, and the fleet's upgrades
/// and names.
class HangarScreen extends ConsumerWidget {
  const HangarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final pilots = sim.crew.pilotCount(state);
    final pilotSlots = sim.crew.pilotSlots(state);

    return ColoredBox(
      color: Board.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: 'Hangar',
            subtitle:
                '${state.planes.length} '
                '${state.planes.length == 1 ? 'plane' : 'planes'} · '
                '$pilots of $pilotSlots pilots',
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
                const SizedBox(height: 10),
                const Text(
                  'No limit on planes. Each one needs a pilot to fly, and '
                  'pilots are capped: spare planes wait parked.',
                  key: Key('hangar.pilotNote'),
                  style: TextStyle(fontSize: 13, color: Board.muted),
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
                          subtitle: _upgradeLine(config, p),
                          onTap: () => showBoardSheet(
                            context,
                            PlaneUpgradeSheet(planeId: p.id),
                          ),
                          button: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: Key('hangar.rename.${p.id}'),
                                tooltip: 'Rename',
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: Board.amber,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    showRenamePlaneDialog(context, ref, p.id),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Board.muted,
                              ),
                            ],
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

  static String _upgradeLine(GameConfig config, Plane p) {
    final max = config.planes.upgrades.maxLevel;
    final model = config.planes.model(p.modelId);
    final u = p.upgrades;
    final capacity = model.seats == 0
        ? 'Cargo ${u.capacity}/$max'
        : model.hasCargoTrack
        ? 'Seats ${u.capacity}/$max · Cargo ${u.cargo}/$max'
        : 'Seats ${u.capacity}/$max';
    return '$capacity · Speed ${u.speed}/$max · Range ${u.range}/$max';
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
    final owned = growth.ownedCount(state, model.id);
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
                  '${model.speedKmh} km/h'
                  '${owned > 0 ? ' · you own $owned' : ''}',
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
                    final plane = s.planes.last;
                    final city = sim.rules.world.city(plane.cityId);
                    showToast(
                      context,
                      plane.status == PlaneStatus.parked
                          ? '${model.name} ${flightNumber(plane)} is waiting '
                                'at ${city.name}.'
                          : '${model.name} ${flightNumber(plane)} is circling '
                                '${city.name} until a gate frees up.',
                      kind: ToastKind.done,
                    );
                  }
                }
              : null,
        ),
      ),
    );
  }
}
