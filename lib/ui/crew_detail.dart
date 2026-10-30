import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'crew_format.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// One crew member: their skill tree (flight crew) or staff upgrades
/// (airport staff), their last flight's XP, and where they work.
class CrewDetail extends ConsumerStatefulWidget {
  const CrewDetail({required this.memberId, required this.onBack, super.key});

  final String memberId;
  final VoidCallback onBack;

  @override
  ConsumerState<CrewDetail> createState() => _CrewDetailState();
}

class _CrewDetailState extends ConsumerState<CrewDetail> {
  String? _node;

  bool _act(
    GameState Function(Simulation sim, GameState state, DateTime now) action,
  ) {
    final error = ref.read(gameSessionProvider.notifier).act(action);
    if (error != null) showToast(context, ruleErrorText(error));
    return error == null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final m = state.crew.member(widget.memberId);
    if (m == null) return const SizedBox.shrink();
    final role = config.crew.role(m.roleId);
    final id = m.id;
    return ColoredBox(
      color: Board.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 10),
            decoration: const BoxDecoration(
              color: Board.panel,
              border: Border(bottom: BorderSide(color: Board.line)),
            ),
            child: Row(
              children: [
                IconButton(
                  key: const Key('crew.back'),
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                  icon: const Icon(
                    Icons.chevron_left,
                    color: Board.ink,
                    size: 28,
                  ),
                ),
                CrewAvatar(name: m.name, veteran: m.isVeteran),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Board.flapStyle(size: 18),
                      ),
                      Text(
                        [
                          role.name,
                          if (role.isFlightCrew) 'Lv ${m.level}',
                          memberPlace(config, state, m),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Board.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (role.isFlightCrew) ...[
                  _XpBar(member: m),
                  const SizedBox(height: 12),
                  _Tree(
                    member: m,
                    selected: _node,
                    onSelect: (node) => setState(() => _node = node),
                    onLearn: (node) =>
                        _act((sim, s, now) => sim.learnSkill(s, id, node, now)),
                  ),
                  if (m.lastFlight != null) ...[
                    const SizedBox(height: 16),
                    _LastFlight(flight: m.lastFlight!),
                  ],
                ] else
                  _StaffPaths(
                    member: m,
                    onBuy: (path) => _act(
                      (sim, s, now) => sim.buyStaffTier(s, id, path, now),
                    ),
                  ),
                const SizedBox(height: 16),
                _Assignment(member: m, act: _act),
                const SizedBox(height: 16),
                _About(member: m, act: _act),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _XpBar extends ConsumerWidget {
  const _XpBar({required this.member});

  final CrewMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final crew = config.crew;
    final max = member.level >= crew.maxLevel;
    final need = crew.xpToNext(member.level);
    final points = ref.read(simulationProvider).crew.unspentPoints(member);
    final sig = member.signatureId == null
        ? null
        : crew.signature(member.signatureId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                max
                    ? 'Lv ${member.level}, top level'
                    : 'Lv ${member.level} to ${member.level + 1}',
                style: const TextStyle(fontSize: 13, color: Board.muted),
              ),
            ),
            if (!max)
              Text(
                '${formatCoins(member.xp)} / ${formatCoins(need)} XP',
                style: Board.flapStyle(size: 13, color: Board.ink),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: max ? 1 : member.xp / need,
            minHeight: 8,
            color: Board.amber,
            backgroundColor: Board.raised,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: points > 0 ? const Color(0xFF3A2E10) : Board.raised,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                points == 1 ? '1 POINT TO SPEND' : '$points POINTS TO SPEND',
                key: const Key('crew.points'),
                style: Board.flapStyle(
                  size: 11,
                  color: points > 0 ? Board.amber : Board.muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (sig != null)
              Expanded(
                child: Text(
                  'Signature: ${sig.name}',
                  style: const TextStyle(fontSize: 13, color: Board.muted),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The skill tree: three branches and the signature, top to bottom.
class _Tree extends ConsumerWidget {
  const _Tree({
    required this.member,
    required this.selected,
    required this.onSelect,
    required this.onLearn,
  });

  final CrewMember member;
  final String? selected;
  final void Function(String nodeId) onSelect;
  final void Function(String nodeId) onLearn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final desk = ref.read(simulationProvider).crew;
    final branches = config.crew.branchesFor(member.roleId, member.signatureId);
    final pick = selected == null ? null : config.crew.nodes[selected!];
    final problem = selected == null
        ? null
        : desk.learnProblem(member, selected!);
    final learned = selected != null && member.allNodes.contains(selected);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Board.flap,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Board.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in branches)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Text(
                          '${branchLabel(b).toUpperCase()} '
                          '${b.nodes.where((n) => member.allNodes.contains(n.id)).length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Board.flapStyle(
                            size: 10,
                            color: b.id == member.signatureId
                                ? Board.signature
                                : Board.amber,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final n in b.nodes)
                          _NodeTile(
                            node: n,
                            signature: b.id == member.signatureId,
                            learned: member.allNodes.contains(n.id),
                            open:
                                desk.learnProblem(member, n.id) == null ||
                                desk.learnProblem(member, n.id) ==
                                    RuleError.noSkillPoints,
                            selected: n.id == selected,
                            onTap: () => onSelect(n.id),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              _Legend(Board.amber, 'Learned', filled: true),
              _Legend(Board.amber, 'Open'),
              _Legend(Board.signature, 'Signature', filled: true),
              _Legend(Board.muted, 'Capstone'),
            ],
          ),
          if (pick != null) ...[
            const Divider(height: 20),
            Text(
              pick.$2.name ?? pick.$1.name,
              style: Board.flapStyle(size: 13),
            ),
            const SizedBox(height: 4),
            Text(
              pick.$2.text,
              key: const Key('crew.nodeText'),
              style: const TextStyle(fontSize: 14, color: Board.ink),
            ),
            const SizedBox(height: 10),
            if (learned)
              const Text('Learned.', style: TextStyle(color: Board.good))
            else
              AmberButton(
                key: const Key('crew.learn'),
                label: problem == null ? 'Learn' : ruleErrorText(problem),
                height: 44,
                onPressed: problem == null ? () => onLearn(selected!) : null,
              ),
          ],
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.signature,
    required this.learned,
    required this.open,
    required this.selected,
    required this.onTap,
  });

  final SkillNode node;
  final bool signature;
  final bool learned;
  final bool open;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = signature ? Board.signature : Board.amber;
    final fill = learned
        ? (signature ? Board.signatureChip : Board.amber)
        : node.capstone
        ? Board.flap
        : Board.panel;
    final ink = learned
        ? (signature ? Board.signature : Board.amberInk)
        : open
        ? accent
        : Board.muted;
    final border = selected
        ? Board.ink
        : open && !learned
        ? accent
        : node.capstone
        ? Board.muted
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: selected ? 2 : 1.5),
        ),
        child: InkWell(
          key: Key('crew.node.${node.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              nodeLabel(node),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.1,
                fontWeight: learned || node.capstone
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label, {this.filled = false});

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: filled ? color : null,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color, width: 1.5),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: Board.muted)),
    ],
  );
}

class _LastFlight extends ConsumerWidget {
  const _LastFlight({required this.flight});

  final CrewFlightXp flight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final world = config.world;
    final model = config.planes.model(flight.modelId);
    final cls = config.planes.planeClass(model.classId);
    String times(double v) =>
        '× ${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '')}';
    final rows = [
      (
        'Distance ${formatKm(flight.distanceKm)}',
        formatCoins((flight.distanceKm / config.crew.xp.kmPerXp).round()),
      ),
      ('${model.name} · ${cls.name}', times(flight.planeFactor)),
      (
        'Load ${flight.loadUsed} / ${flight.loadCapacity}',
        times(flight.loadFactor),
      ),
      if (flight.bonusPct.round() != 0)
        ('Flight bonuses', '+${flight.bonusPct.round()}%'),
    ];
    return BoardSection(
      title:
          'Last flight · ${world.city(flight.fromCityId).name} to '
          '${world.city(flight.toCityId).name}',
      child: Column(
        children: [
          for (final (label, value) in rows) _Line(label, value),
          _Line('XP earned', '+${flight.xp}', highlight: true),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Board.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: Board.flapStyle(
              size: 12,
              color: highlight ? Board.amber : Board.muted,
              weight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: Board.flapStyle(
            size: 13,
            color: highlight ? Board.amber : Board.ink,
          ),
        ),
      ],
    ),
  );
}

/// Airport staff: three paths of three tiers, bought with money.
class _StaffPaths extends ConsumerWidget {
  const _StaffPaths({required this.member, required this.onBuy});

  final CrewMember member;
  final void Function(String pathId) onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final desk = ref.read(simulationProvider).crew;
    final role = config.crew.role(member.roleId);
    return BoardSection(
      title: 'Upgrades',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              '${role.base.text}. Staff don\'t earn XP; their three paths '
              'are bought with coins, priced by the city they work in.',
              style: const TextStyle(fontSize: 13, color: Board.muted),
            ),
          ),
          for (final path in config.crew.staffPaths[member.roleId]!)
            Builder(
              builder: (context) {
                final tier = member.tier(path.id);
                final cost = desk.staffTierCost(state, member, path.id);
                final maxed = tier >= path.tiers.length;
                return Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Board.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  path.name.toUpperCase(),
                                  style: Board.flapStyle(size: 12),
                                ),
                                const SizedBox(width: 8),
                                for (var i = 0; i < path.tiers.length; i++)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i < tier
                                          ? Board.amber
                                          : Board.raised,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tier == 0
                                  ? 'Next: ${path.tiers.first.text}'
                                  : maxed
                                  ? path.tiers[tier - 1].text
                                  : '${path.tiers[tier - 1].text}. Next: ${path.tiers[tier].text}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Board.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AmberButton(
                        key: Key('crew.tier.${path.id}'),
                        label: maxed
                            ? 'Max'
                            : cost == null
                            ? 'Assign first'
                            : formatCoins(cost),
                        mono: true,
                        height: 36,
                        onPressed: cost == null || state.player.money < cost
                            ? null
                            : () => onBuy(path.id),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Where they work, and the places they could move to.
class _Assignment extends ConsumerWidget {
  const _Assignment({required this.member, required this.act});

  final CrewMember member;
  final bool Function(
    GameState Function(Simulation sim, GameState state, DateTime now) action,
  )
  act;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final desk = ref.read(simulationProvider).crew;
    final id = member.id;
    final flight = config.crew.role(member.roleId).isFlightCrew;
    final movable = desk.canMove(state, member);
    final options = <(String, String, VoidCallback)>[
      if (flight)
        for (final p in state.planes)
          if (p.id != member.planeId &&
              p.status == PlaneStatus.parked &&
              desk.hasSeatFor(state, p, member))
            (
              p.id,
              '${planeName(config, p)} · ${config.world.city(p.cityId).name}',
              () =>
                  act((sim, s, now) => sim.assignCrewToPlane(s, id, p.id, now)),
            ),
      if (!flight)
        for (final a in state.airports)
          if (a.cityId != member.cityId &&
              state.crew.atAirport(a.cityId).length <
                  desk.staffSlots(state, a.cityId))
            (
              a.cityId,
              config.world.city(a.cityId).name,
              () => act(
                (sim, s, now) => sim.assignCrewToAirport(s, id, a.cityId, now),
              ),
            ),
    ];
    return BoardSection(
      title: 'Works at',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              member.isAssigned
                  ? _capital(memberPlace(config, state, member))
                  : 'Not working anywhere yet.',
              key: const Key('crew.place'),
              style: const TextStyle(fontSize: 15, color: Board.ink),
            ),
            const SizedBox(height: 10),
            if (!movable)
              const Text(
                'Their plane is in the air. Move them once it lands.',
                style: TextStyle(fontSize: 13, color: Board.muted),
              )
            else ...[
              Text(
                options.isEmpty
                    ? flight
                          ? 'No parked plane has a free seat for them.'
                          : 'No airport has a free staff slot.'
                    : flight
                    ? 'Move to a parked plane:'
                    : 'Move to an airport:',
                style: const TextStyle(fontSize: 13, color: Board.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (key, label, onTap) in options)
                    BoardChip(
                      key: Key('crew.assign.$key'),
                      label: label,
                      selected: false,
                      onTap: onTap,
                    ),
                  if (member.isAssigned)
                    BoardChip(
                      key: const Key('crew.unassign'),
                      label: 'Take off duty',
                      selected: false,
                      dashed: true,
                      onTap: () =>
                          act((sim, s, now) => sim.unassignCrew(s, id, now)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _capital(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Bio, home city, autopilot and respec.
class _About extends ConsumerWidget {
  const _About({required this.member, required this.act});

  final CrewMember member;
  final bool Function(
    GameState Function(Simulation sim, GameState state, DateTime now) action,
  )
  act;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final desk = ref.read(simulationProvider).crew;
    final named = member.namedId == null
        ? null
        : config.crew.named.where((n) => n.id == member.namedId).firstOrNull;
    final flight = config.crew.role(member.roleId).isFlightCrew;
    final cost = desk.respecCost(member);
    final autopilot = member.allNodes.contains('autopilot');
    final id = member.id;
    return BoardSection(
      title: 'About',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (named != null) ...[
              Text(
                named.bio,
                style: const TextStyle(fontSize: 14, color: Board.ink),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'From ${config.world.city(member.homeCityId).name}. '
              '${member.isVeteran ? 'Veteran' : 'Hired'} for '
              '${formatCoins(member.hirePrice)}.',
              style: const TextStyle(fontSize: 13, color: Board.muted),
            ),
            if (member.signatureId != null) ...[
              const SizedBox(height: 4),
              Text(
                'Signature: ${signatureBlurb(config, member)}.',
                style: const TextStyle(fontSize: 13, color: Board.signature),
              ),
            ],
            if (autopilot) ...[
              const SizedBox(height: 4),
              const Text(
                'As captain they can fly Autopilot: choose a route, then '
                'tap Autopilot in the route picker.',
                style: TextStyle(fontSize: 13, color: Board.muted),
              ),
            ],
            if (flight) ...[
              const SizedBox(height: 12),
              AmberButton(
                key: const Key('crew.respec'),
                label: 'Reset skills · ${formatCoins(cost)}',
                outlined: member.nodes.isNotEmpty,
                height: 44,
                onPressed: member.nodes.isEmpty || state.player.money < cost
                    ? null
                    : () => act((sim, s, now) => sim.respecCrew(s, id, now)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
