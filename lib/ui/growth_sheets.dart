import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Runs a growth action and shows why it was refused, if it was. Returns
/// true when it happened.
bool actOrExplain(
  BuildContext context,
  WidgetRef ref,
  GameState Function(Simulation sim, GameState state, DateTime now) action,
) {
  final error = ref.read(gameSessionProvider.notifier).act(action);
  if (error != null) showToast(context, ruleErrorText(error));
  return error == null;
}

/// The label for a buy button: "Buy · 1,500", "Need 18,000", "Lv 20".
String priceLabel(RuleError? problem, int price, {String verb = 'Buy'}) =>
    switch (problem) {
      null => '$verb · ${formatCoins(price)}',
      RuleError.notEnoughMoney => 'Need ${formatCoins(price)}',
      _ => ruleErrorShort(problem),
    };

/// A few words for a disabled button.
String ruleErrorShort(RuleError error) => switch (error) {
  RuleError.hangarFull => 'Hangar full',
  RuleError.noGate => 'No gate',
  RuleError.maxLevel => 'Maxed',
  RuleError.noUpgradePoints => 'No points',
  RuleError.regionLocked => 'No license',
  RuleError.alreadyOwned => 'Owned',
  RuleError.levelTooLow => 'Locked',
  _ => 'Unavailable',
};

/// The colour of each upgrade path, used for its map badge and its row.
Color pathColor(String pathId) => switch (pathId) {
  'passenger' => Board.pax,
  'cargo' => Board.cargo,
  'gateway' => Board.good,
  _ => const Color(0xFFC59BFF),
};

/// Opens a sheet over the screen in the board style.
Future<void> showBoardSheet(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Board.ground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => FractionallySizedBox(heightFactor: 0.82, child: child),
    );

/// One row of a growth list: a title, a grey line under it and a button.
class GrowthRow extends StatelessWidget {
  const GrowthRow({
    required this.title,
    required this.subtitle,
    required this.button,
    this.leading,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? button;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Board.line)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Board.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Board.muted),
                ),
              ],
            ),
          ),
          if (button != null) ...[const SizedBox(width: 8), button!],
        ],
      ),
    ),
  );
}

/// The airport's four upgrade paths: points used, each path's bought and
/// next tier, buy and sell.
class PathsSheet extends ConsumerWidget {
  const PathsSheet({required this.cityId, super.key});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final growth = sim.growth;
    final config = sim.rules.config;
    final airport = state.airport(cityId);
    if (airport == null) return const SizedBox.shrink();
    final city = config.world.city(cityId);
    final points = growth.upgradePoints(airport);
    final used = growth.usedPoints(airport);
    final more = [
      for (final l in config.airports.levels)
        if (l.level > airport.level &&
            l.upgradePoints > config.airports.level(l.level - 1).upgradePoints)
          '+${l.upgradePoints - config.airports.level(l.level - 1).upgradePoints}'
              ' at Lv ${l.level}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Upgrades',
          subtitle: '${city.name} · mix any paths',
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              BoardSection(
                title: 'Upgrade points',
                trailing: FlapText(
                  '$used / $points used',
                  key: const Key('paths.points'),
                  size: 12,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    [
                      '${points - used} free '
                          '${points - used == 1 ? 'point' : 'points'} now',
                      ...more,
                    ].join(' · '),
                    style: const TextStyle(color: Board.muted, fontSize: 13),
                  ),
                ),
              ),
              for (final path in config.airports.paths) ...[
                const SizedBox(height: 12),
                _PathCard(airport: airport, pathId: path.id),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PathCard extends ConsumerWidget {
  const _PathCard({required this.airport, required this.pathId});

  final AirportState airport;
  final String pathId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final growth = sim.growth;
    final path = sim.rules.config.airports.paths.firstWhere(
      (p) => p.id == pathId,
    );
    final tier = airport.tier(pathId);
    final cost = growth.pathTierCost(airport, pathId);
    final problem = growth.buyTierProblem(state, airport.cityId, pathId);
    final refund = growth.pathTierRefund(airport, pathId);
    final color = pathColor(pathId);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Board.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  path.name.toUpperCase(),
                  style: Board.flapStyle(size: 14, color: color),
                ),
              ),
              for (var i = 0; i < path.tiers.length; i++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < tier ? color : Board.line,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < path.tiers.length; i++)
            if (i <= tier)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${i < tier ? 'Owned' : 'Next'}: ${path.tiers[i].text}',
                  style: TextStyle(
                    fontSize: 13,
                    color: i < tier ? Board.ink : Board.muted,
                  ),
                ),
              ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AmberButton(
                  key: Key('paths.buy.$pathId'),
                  mono: true,
                  height: 36,
                  label: cost == null
                      ? 'Maxed'
                      : problem == RuleError.noUpgradePoints
                      ? 'Tier ${tier + 1} · no free point'
                      : problem == RuleError.notEnoughMoney
                      ? 'Tier ${tier + 1} · need ${formatCoins(cost)}'
                      : 'Tier ${tier + 1} · ${formatCoins(cost)} + 1 pt',
                  onPressed: problem == null
                      ? () => actOrExplain(
                          context,
                          ref,
                          (sim, s, now) =>
                              sim.buyPathTier(s, airport.cityId, pathId, now),
                        )
                      : null,
                ),
              ),
              if (refund != null) ...[
                const SizedBox(width: 8),
                AmberButton(
                  key: Key('paths.sell.$pathId'),
                  label: 'Sell +${formatCoins(refund)}',
                  outlined: true,
                  height: 36,
                  onPressed: () => actOrExplain(
                    context,
                    ref,
                    (sim, s, now) =>
                        sim.sellPathTier(s, airport.cityId, pathId, now),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One plane's upgrades and name.
class PlaneUpgradeSheet extends ConsumerStatefulWidget {
  const PlaneUpgradeSheet({required this.planeId, super.key});

  final String planeId;

  @override
  ConsumerState<PlaneUpgradeSheet> createState() => _PlaneUpgradeSheetState();
}

class _PlaneUpgradeSheetState extends ConsumerState<PlaneUpgradeSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    final plane = ref.read(gameSessionProvider).plane(widget.planeId);
    _name = TextEditingController(text: plane?.nickname ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _rename() => actOrExplain(
    context,
    ref,
    (sim, s, now) => sim.renamePlane(s, widget.planeId, _name.text, now),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final plane = state.plane(widget.planeId);
    if (plane == null) return const SizedBox.shrink();
    final model = config.planes.model(plane.modelId);
    final stats = PlaneStats.of(sim.rules, state, plane);
    final up = config.planes.upgrades;
    final cargoOnly = model.seats == 0;
    final tracks = [
      (
        PlaneTrack.capacity,
        cargoOnly ? 'Cargo slots' : 'Seats',
        '+${up.capacityPerLevel} ${cargoOnly ? 'slot' : 'seat'} a level',
        cargoOnly ? '${stats.cargoSlots} slots' : '${stats.seats} seats',
      ),
      (
        PlaneTrack.speed,
        'Speed',
        '+${up.speedPctPerLevel.round()}% a level',
        '${stats.speedKmh.round()} km/h',
      ),
      (
        PlaneTrack.range,
        'Range',
        '+${up.rangePctPerLevel.round()}% a level',
        formatKm(stats.rangeKm),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: planeName(config, plane),
          subtitle:
              '${model.name} · ${flightNumber(plane)} · '
              '${config.world.city(plane.cityId).name}',
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              BoardSection(
                title: 'Name',
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('plane.name'),
                          controller: _name,
                          maxLength: Growth.maxNicknameLength,
                          style: const TextStyle(color: Board.ink),
                          decoration: InputDecoration(
                            hintText: model.name,
                            hintStyle: const TextStyle(color: Board.muted),
                            counterText: '',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _rename(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AmberButton(
                        key: const Key('plane.rename'),
                        label: 'Save',
                        height: 36,
                        onPressed: _rename,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              BoardSection(
                title: 'Upgrades',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (track, name, step, now) in tracks)
                      _trackRow(state, sim, plane, track, name, step, now),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _trackRow(
    GameState state,
    Simulation sim,
    Plane plane,
    PlaneTrack track,
    String name,
    String step,
    String now,
  ) {
    final growth = sim.growth;
    final level = growth.trackLevel(plane, track);
    final cost = growth.planeUpgradeCost(plane, track);
    final max = sim.rules.config.planes.upgrades.maxLevel;
    final RuleError? problem = cost == null
        ? RuleError.maxLevel
        : state.player.money < cost
        ? RuleError.notEnoughMoney
        : null;
    return GrowthRow(
      title: '$name · Lv $level of $max',
      subtitle: '$now now · $step',
      button: AmberButton(
        key: Key('plane.upgrade.${track.name}'),
        mono: true,
        height: 34,
        label: cost == null ? 'Maxed' : priceLabel(problem, cost, verb: 'Up'),
        onPressed: problem == null
            ? () => actOrExplain(
                context,
                ref,
                (sim, s, t) => sim.upgradePlane(s, plane.id, track, t),
              )
            : null,
      ),
    );
  }
}

/// Airline level, title, what the next levels unlock, and network stats.
class AirlineSheet extends ConsumerWidget {
  const AirlineSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final growth = sim.growth;
    final progression = sim.rules.config.progression;
    final player = state.player;
    final atMax = player.level >= progression.maxLevel;
    final stats = state.stats;
    final world = sim.rules.world;
    final busiest = stats.busiestRoute;
    final upcoming = <int>[];
    for (var l = player.level; upcoming.length < 3;) {
      final next = growth.nextUnlockLevel(l);
      if (next == null) break;
      upcoming.add(next);
      l = next;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Airline Lv ${player.level}',
          subtitle: growth.title(player.level),
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'XP',
                      value: atMax
                          ? 'Max'
                          : '${formatCoins(player.xp)} / '
                                '${formatCoins(progression.xpToNext(player.level))}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Hangar',
                      value:
                          '${state.planes.length} / ${growth.hangarSlots(state)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BoardSection(
                title: 'Coming up',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (upcoming.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Everything is unlocked.',
                          style: TextStyle(color: Board.muted),
                        ),
                      ),
                    for (final l in upcoming)
                      GrowthRow(
                        title: 'Level $l',
                        subtitle: growth.unlocksAt(l).join(' · '),
                        button: null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BoardSection(
                title: 'Network',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (label, value) in [
                      ('Money earned', formatCoins(stats.moneyEarned)),
                      ('Jobs delivered', formatCoins(stats.jobsDelivered)),
                      ('Kilometres flown', formatKm(stats.kmFlown)),
                      ('Airports owned', '${state.airports.length}'),
                      ('Planes', '${state.planes.length}'),
                      if (busiest != null)
                        (
                          'Busiest route',
                          '${world.city(busiest.$1).name} ⇄ '
                              '${world.city(busiest.$2).name}',
                        ),
                    ])
                      GrowthRow(title: value, subtitle: label, button: null),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when the airline reaches a new level: its title and what it
/// unlocked.
class LevelUpDialog extends ConsumerWidget {
  const LevelUpDialog({required this.from, required this.to, super.key});

  final int from;
  final int to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final growth = ref.read(simulationProvider).growth;
    final unlocked = [
      for (var l = from + 1; l <= to; l++) ...growth.unlocksAt(l),
    ];
    final newTitle = growth.title(to) != growth.title(from);
    return AlertDialog(
      backgroundColor: Board.panel,
      title: Column(
        children: [
          Text('LEVEL $to', style: Board.flapStyle(size: 26)),
          const SizedBox(height: 4),
          Text(
            newTitle ? 'Promoted to ${growth.title(to)}' : growth.title(to),
            style: const TextStyle(color: Board.muted, fontSize: 14),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unlocked.isEmpty)
            const Text(
              'Keep flying: more unlocks are on the way.',
              style: TextStyle(color: Board.ink),
            ),
          for (final u in unlocked.where((u) => !u.startsWith('Title:')))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.lock_open, color: Board.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(u, style: const TextStyle(color: Board.ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        AmberButton(
          key: const Key('levelUp.ok'),
          label: 'Nice',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
