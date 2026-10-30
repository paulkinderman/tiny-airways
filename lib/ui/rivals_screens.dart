import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'map_scene_builder.dart';
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// The rival screens from the mockups: city rivalry, the hub terminal and
/// its tree, the season leaderboard, a rival's airline card, the contract
/// tracker on the top bar and the difficulty picker.

String airlineName(GameConfig config, String airlineId) =>
    airlineId == playerAirlineId ? 'You' : config.rivals.rival(airlineId).name;

Color airlineColor(GameConfig config, String airlineId) =>
    airlineId == playerAirlineId
    ? playerFlagColor
    : liveryColor(config.rivals.rival(airlineId).color);

String tierName(GameConfig config, String tierId) =>
    config.rivals.tiers.firstWhere((t) => t.id == tierId).name;

String _pct(double fraction) => '${(fraction * 100).round()}%';

String _days(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  return formatCountdown(d);
}

void _toastError(BuildContext context, RuleError? error) {
  if (error != null) showToast(context, ruleErrorText(error));
}

/// One line on the airport panel and city card: who leads the city, and the
/// way into the rivalry screen.
class CityShareLine extends ConsumerWidget {
  const CityShareLine({required this.cityId, super.key});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final rivals = sim.rivals;
    final String text;
    Color color = Board.muted;
    if (!rivals.shareOn(state)) {
      final level = config.progression.featureUnlockLevel['cityShare'];
      text = 'City share and leader perks unlock at Lv $level';
    } else {
      final share = state.rivals.share(cityId);
      final leader = rivals.leaderOf(state, cityId);
      final mine = _pct(share.fraction(playerAirlineId));
      if (leader == null) {
        text = 'Nobody leads yet · deliver here to take it';
      } else if (leader == playerAirlineId) {
        text = 'You lead · $mine share';
        color = Board.good;
      } else {
        text =
            '${airlineName(config, leader)} leads · '
            '${_pct(share.fraction(leader))} · you $mine';
        color = airlineColor(config, leader);
      }
    }
    return Material(
      color: Board.panel,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('rivalry.open.$cityId'),
        onTap: () => ref.read(uiProvider.notifier).open(RivalryPanel(cityId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.flag_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Board.ink),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Board.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Atlanta rivalry": the city's share meter, the road to a hub, leader
/// perks and the live contract.
class RivalryScreen extends ConsumerWidget {
  const RivalryScreen({required this.cityId, super.key});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final rivals = sim.rivals;
    final city = config.world.city(cityId);
    final ui = ref.read(uiProvider.notifier);
    final share = state.rivals.share(cityId);
    final on = rivals.shareOn(state);
    final leader = rivals.leaderOf(state, cityId);
    final holder = rivals.rivalTerminalAt(state, cityId);
    final terminal = state.rivals.terminal(cityId);

    final rows = [
      for (final id in share.points.keys)
        (id: id, fraction: share.fraction(id)),
    ]..sort((a, b) => b.fraction.compareTo(a.fraction));
    if (!rows.any((r) => r.id == playerAirlineId)) {
      rows.add((id: playerAirlineId, fraction: 0));
    }

    String subtitle() {
      if (!on) {
        return 'City share unlocks at Lv ${_unlock(config, 'cityShare')}';
      }
      final parts = <String>[
        if (terminal != null)
          'Your terminal'
        else if (rivals.isHub(state, cityId, state.simulatedTo))
          'Your hub',
        if (holder != null) '${airlineName(config, holder)} terminal',
      ];
      if (leader != null && leader != playerAirlineId) {
        parts.add('${airlineName(config, leader)} leads');
      } else if (leader == playerAirlineId) {
        final chaser = rows.where((r) => r.id != playerAirlineId).firstOrNull;
        if (chaser != null && chaser.fraction > 0) {
          parts.add('${airlineName(config, chaser.id)} is pushing in');
        }
      }
      return parts.isEmpty ? city.name : parts.join(' · ');
    }

    return TickBuilder(
      builder: (context, now) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: '${city.name} rivalry',
            subtitle: subtitle(),
            onBack: () => ui.open(
              state.ownsAirport(cityId)
                  ? AirportPanel(cityId)
                  : CityPanel(cityId),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                BoardSection(
                  title: 'City share',
                  trailing: leader == playerAirlineId
                      ? const FlapText('You lead', size: 11, color: Board.good)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        if (!on)
                          Text(
                            'Rivals fly here already. From airline level '
                            '${_unlock(config, 'cityShare')}, every job you '
                            'deliver adds share, and the airline with the '
                            'most leads the city.',
                            style: const TextStyle(color: Board.muted),
                          )
                        else
                          for (final r in rows.take(5))
                            _ShareBar(
                              label: airlineName(config, r.id),
                              fraction: r.fraction,
                              color: airlineColor(config, r.id),
                              bold: r.id == playerAirlineId,
                            ),
                      ],
                    ),
                  ),
                ),
                if (on) ...[
                  const SizedBox(height: 12),
                  _RoadToHub(cityId: cityId, now: now),
                  const SizedBox(height: 12),
                  _LeaderPerks(cityId: cityId),
                ],
                if (state.rivals.liveContract case final c?) ...[
                  const SizedBox(height: 12),
                  ContractCard(contract: c, now: now),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AmberButton(
                        key: const Key('rivalry.terminal'),
                        label: 'Terminal',
                        mono: true,
                        outlined: true,
                        onPressed: () => ui.open(TerminalPanel(cityId)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AmberButton(
                        key: const Key('rivalry.season'),
                        label: 'Season',
                        mono: true,
                        outlined: true,
                        onPressed: () => ui.open(
                          LeaderboardPanel(
                            regionId: city.regionId,
                            fromCityId: cityId,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _unlock(GameConfig config, String feature) =>
    config.progression.featureUnlockLevel[feature] ?? 1;

class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.label,
    required this.fraction,
    required this.color,
    this.bold = false,
  });

  final String label;
  final double fraction;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: Board.ink,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(_pct(fraction), style: Board.flapStyle(size: 13)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: Board.line,
            color: color,
          ),
        ),
      ],
    ),
  );
}

/// Hub progress, or the takeover clock on a rival's terminal.
class _RoadToHub extends ConsumerWidget {
  const _RoadToHub({required this.cityId, required this.now});

  final String cityId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final rivals = sim.rivals;
    final hub = config.rivals.hub;
    final days = hub['daysHeld']!.round();
    final need = hub['minSharePct']!.round();
    final mine = state.rivals.share(cityId).fraction(playerAirlineId);
    final holder = rivals.rivalTerminalAt(state, cityId);
    final String title;
    final String text;
    if (state.rivals.terminal(cityId) != null) {
      title = 'Your terminal';
      text =
          'It is yours for good. If a rival leads here, leader perks pause '
          'but the terminal tree keeps working.';
    } else if (holder != null) {
      final name = airlineName(config, holder);
      final takeover = rivals.takeoverIn(state, cityId, now);
      final need = config.rivals.terminal['takeoverDaysLeading']!.round();
      title = '$name terminal';
      text = takeover == null
          ? 'Lead $name\'s city for $need days in a row and its terminal '
                'goes up for lease at half price.'
          : 'You lead. Hold on ${_days(takeover)} more to take the '
                'terminal.';
    } else if (rivals.isForLease(state, cityId)) {
      title = 'Terminal for lease';
      text =
          'You took this terminal over. Lease it for '
          '${formatCoins(rivals.terminalCost(state, cityId))}.';
    } else if (rivals.isHub(state, cityId, now)) {
      title = 'Hub';
      text =
          'You hold $need% here: +1 job board slot, and you can build a '
          'terminal.';
    } else {
      final left = rivals.hubIn(state, cityId, now);
      title = 'Road to hub';
      text = left == null
          ? '${_pct(mine)} of $need%. Hold $need% for $days days to unlock '
                'a terminal here.'
          : 'Holding $need%. ${_days(left)} to go.';
    }
    return BoardSection(
      title: title,
      trailing: holder == null && state.rivals.terminal(cityId) == null
          ? FlapText('$need% for $days days', size: 10, color: Board.muted)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: const TextStyle(color: Board.ink)),
      ),
    );
  }
}

class _LeaderPerks extends ConsumerWidget {
  const _LeaderPerks({required this.cityId});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final leader = sim.rivals.leaderOf(state, cityId);
    final mine = leader == playerAirlineId;
    final perks = config.rivals.leader;
    final flag = leader == null
        ? 'Nobody'
        : mine
        ? 'Yours'
        : airlineName(config, leader);
    return BoardSection(
      title: 'Leader perks',
      trailing: FlapText(
        mine ? 'Active' : 'Paused',
        size: 10,
        color: mine ? Board.good : Board.muted,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Pay here',
                value: '+${perks['payPct']!.round()}%',
                valueColor: mine ? Board.amber : Board.muted,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: StatTile(
                label: 'New jobs',
                value: '${perks['firstLookSeconds']!.round()}s early',
                valueColor: mine ? Board.amber : Board.muted,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: StatTile(
                label: 'City flag',
                value: flag,
                valueColor: leader == null
                    ? Board.muted
                    : airlineColor(config, leader),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "First airline to deliver 15 jobs to Lima wins 50,000", with the race.
class ContractCard extends ConsumerWidget {
  const ContractCard({required this.contract, required this.now, super.key});

  final Contract contract;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.read(gameConfigProvider);
    final city = config.world.city(contract.cityId);
    final racers = [playerAirlineId, ...contract.rivalIds];
    return BoardSection(
      title: 'Contract · ${city.name}',
      trailing: FlapText(
        formatCountdown(contract.endsAt.difference(now)),
        size: 11,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'First airline to deliver ${contract.jobsToWin} jobs to '
                    '${city.name} wins',
                    style: const TextStyle(color: Board.ink),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatCoins(contract.prize),
                  style: Board.flapStyle(size: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final id in racers)
              _ShareBar(
                label:
                    '${airlineName(config, id)}  '
                    '${contract.score(id)} / ${contract.jobsToWin}',
                fraction: contract.score(id) / contract.jobsToWin,
                color: airlineColor(config, id),
                bold: id == playerAirlineId,
              ),
          ],
        ),
      ),
    );
  }
}

/// The contract tracker on the top bar: your score against the best
/// rival's. Tapping it opens the contract city's rivalry screen.
class ContractChip extends ConsumerWidget {
  const ContractChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contract = ref.watch(
      gameSessionProvider.select((s) => s.rivals.liveContract),
    );
    if (contract == null) return const SizedBox.shrink();
    var best = 0;
    for (final id in contract.rivalIds) {
      if (contract.score(id) > best) best = contract.score(id);
    }
    final mine = contract.score(playerAirlineId);
    // Shrinks rather than crowding the top bar on small phones.
    return Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Semantics(
            button: true,
            label:
                'Contract race: you $mine, best rival $best, of '
                '${contract.jobsToWin}.',
            excludeSemantics: true,
            child: Material(
              color: Board.panel,
              shape: const StadiumBorder(side: BorderSide(color: Board.amber)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('topBar.contract'),
                onTap: () => ref
                    .read(uiProvider.notifier)
                    .open(RivalryPanel(contract.cityId)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        size: 15,
                        color: Board.amber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$mine–$best',
                        style: Board.flapStyle(
                          size: 12,
                          color: mine >= best ? Board.good : Board.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The player's terminal in a city: build or lease it, then spend terminal
/// points down its three branches.
class TerminalScreen extends ConsumerWidget {
  const TerminalScreen({required this.cityId, super.key});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final rivals = sim.rivals;
    final city = config.world.city(cityId);
    final terminal = state.rivals.terminal(cityId);
    final session = ref.read(gameSessionProvider.notifier);
    final rules = config.rivals.terminal;

    final body = <Widget>[];
    if (terminal == null) {
      final problem = rivals.terminalProblem(state, cityId, state.simulatedTo);
      final lease = rivals.isForLease(state, cityId);
      final limit = rivals.terminalLimit(state);
      body.addAll([
        BoardSection(
          title: lease ? 'Lease this terminal' : 'Build a terminal',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lease
                      ? 'You took this terminal from its rival. Lease it at '
                            'half the build cost, with a fresh tree.'
                      : 'Hold ${config.rivals.hub['minSharePct']!.round()}% '
                            'share here for '
                            '${config.rivals.hub['daysHeld']!.round()} days to '
                            'make it a hub, then build. A terminal is yours '
                            'for good.',
                  style: const TextStyle(color: Board.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  limit == 0
                      ? 'Terminals unlock at airline Lv '
                            '${rules['firstAirlineLevel']!.round()}.'
                      : 'Terminals held: ${state.rivals.terminals.length} of '
                            '$limit',
                  style: const TextStyle(color: Board.muted, fontSize: 13),
                ),
                if (problem != null && problem != RuleError.notEnoughMoney)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      ruleErrorText(problem),
                      style: const TextStyle(color: Board.bad, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 12),
                AmberButton(
                  key: const Key('terminal.build'),
                  label:
                      '${lease ? 'Lease' : 'Build'} · '
                      '${formatCoins(rivals.terminalCost(state, cityId))}',
                  mono: true,
                  onPressed: problem == null
                      ? () => _toastError(
                          context,
                          session.act(
                            (sim, s, now) => sim.buildTerminal(s, cityId, now),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ]);
    } else {
      final per = rules['jobsPerPoint']!.round();
      final earned = rivals.pointsEarned(terminal);
      final max = rules['maxPoints']!.round();
      final toSpend = rivals.pointsToSpend(terminal);
      body.addAll([
        BoardSection(
          title: 'Next terminal point',
          trailing: FlapText(
            earned >= max ? 'All earned' : '${terminal.jobs % per} / $per jobs',
            size: 11,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$toSpend point${toSpend == 1 ? '' : 's'} to spend',
                    style: Board.flapStyle(
                      size: 14,
                      color: toSpend > 0 ? Board.amber : Board.muted,
                    ),
                  ),
                ),
                Text(
                  '$earned of $max earned',
                  style: const TextStyle(color: Board.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in config.rivals.terminalBranches) ...[
              if (b != config.rivals.terminalBranches.first)
                const SizedBox(width: 6),
              Expanded(
                child: _Branch(
                  name: b.name,
                  nodes: b.nodes,
                  learned: terminal.learned(b.id),
                  canLearn: toSpend > 0,
                  onLearn: () => _toastError(
                    context,
                    session.act(
                      (sim, s, now) =>
                          sim.learnTerminalNode(s, cityId, b.id, now),
                    ),
                  ),
                  keyPrefix: 'terminal.${b.id}',
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        BoardSection(
          title: 'Terminal holder bonus',
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Share',
                    value:
                        '× ${config.rivals.share['terminalShareMultiplier']}',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: StatTile(
                    label: 'Decay',
                    value:
                        '× ${config.rivals.share['terminalDecayMultiplier']}',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: StatTile(
                    label: 'Held',
                    value:
                        '${state.rivals.terminals.length} / '
                        '${rivals.terminalLimit(state)}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: '${city.name} terminal',
          subtitle: terminal == null
              ? citySizeLabel(city.size)
              : 'Built ${formatClock(terminal.builtAt)} · yours for good',
          onBack: () =>
              ref.read(uiProvider.notifier).open(RivalryPanel(cityId)),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: body),
        ),
      ],
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({
    required this.name,
    required this.nodes,
    required this.learned,
    required this.canLearn,
    required this.onLearn,
    required this.keyPrefix,
  });

  final String name;
  final List<Effect> nodes;
  final int learned;
  final bool canLearn;
  final VoidCallback onLearn;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${name.toUpperCase()} $learned',
        textAlign: TextAlign.center,
        style: Board.flapStyle(size: 11),
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < nodes.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _Node(
            key: Key('$keyPrefix.$i'),
            text: nodes[i].text.split(':').first,
            learned: i < learned,
            open: i == learned && canLearn,
            capstone: i == nodes.length - 1,
            onTap: i == learned && canLearn ? onLearn : null,
          ),
        ),
    ],
  );
}

class _Node extends StatelessWidget {
  const _Node({
    required this.text,
    required this.learned,
    required this.open,
    required this.capstone,
    this.onTap,
    super.key,
  });

  final String text;
  final bool learned;
  final bool open;
  final bool capstone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: learned ? Board.amber : Board.panel,
    borderRadius: BorderRadius.circular(10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: open
                ? Board.amber
                : capstone
                ? Board.cargo
                : Board.line,
            width: open ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: capstone ? FontWeight.w700 : FontWeight.w500,
            color: learned ? Board.amberInk : Board.ink,
          ),
        ),
      ),
    ),
  );
}

/// The continent leaderboard: cities led and contracts won this season,
/// trophies, and the difficulty setting.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({required this.panel, super.key});

  final LeaderboardPanel panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final rivals = sim.rivals;
    final ui = ref.read(uiProvider.notifier);
    final home = state.homeCityId == null
        ? config.world.regions.first.id
        : config.world.city(state.homeCityId!).regionId;
    final regions = rivals.activeRegions(state).toList()..sort();
    final regionId = panel.regionId ?? home;
    final region = config.world.region(regionId);
    final on = rivals.leaderboardOn(state);
    final rows = rivals.standings(state, regionId);
    final me = rows.indexWhere((r) => r.isPlayer);
    final ahead = me > 0 ? rows[me - 1] : null;
    final trophies = [
      for (final h in state.rivals.season.history)
        if (h.regionId == regionId) h,
    ];

    return TickBuilder(
      builder: (context, now) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: 'Season leaderboard',
            subtitle: 'Cities led and contracts won',
            onBack: () => panel.fromCityId == null
                ? ui.close()
                : ui.open(RivalryPanel(panel.fromCityId!)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (regions.length > 1) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in regions)
                        BoardChip(
                          key: Key('leaderboard.region.$r'),
                          label: config.world.region(r).name,
                          selected: r == regionId,
                          onTap: () => ui.open(
                            LeaderboardPanel(
                              regionId: r,
                              fromCityId: panel.fromCityId,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                BoardSection(
                  title:
                      'Season ${state.rivals.season.number} · ${region.name}',
                  trailing: rivals.seasonEndsAt(state) == null
                      ? null
                      : FlapText(
                          _days(rivals.seasonEndsAt(state)!.difference(now)),
                          size: 11,
                        ),
                  child: !on
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'The season leaderboard opens at airline Lv '
                            '${_unlock(config, 'leaderboard')}. Rivals are '
                            'already racing for cities.',
                            style: const TextStyle(color: Board.muted),
                          ),
                        )
                      : Column(
                          children: [
                            const _StandingRow.header(),
                            for (var i = 0; i < rows.length; i++)
                              _StandingRow(
                                key: Key(
                                  'leaderboard.row.${rows[i].airlineId}',
                                ),
                                rank: i + 1,
                                standing: rows[i],
                                name: airlineName(config, rows[i].airlineId),
                                badge: rows[i].isPlayer
                                    ? 'You'
                                    : tierName(
                                        config,
                                        rivals.tierOf(
                                          state,
                                          config.rivals.rival(
                                            rows[i].airlineId,
                                          ),
                                        ),
                                      ),
                                title: rows[i].isPlayer
                                    ? config.progression.titleFor(
                                        state.player.level,
                                      )
                                    : rivals.titleOf(
                                        state,
                                        config.rivals.rival(rows[i].airlineId),
                                      ),
                                color: airlineColor(config, rows[i].airlineId),
                              ),
                          ],
                        ),
                ),
                if (on && ahead != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Pass ${airlineName(config, ahead.airlineId)}: '
                    '${ahead.citiesLed - rows[me].citiesLed} '
                    '${ahead.citiesLed - rows[me].citiesLed == 1 ? 'city' : 'cities'} '
                    'behind. Finish above a rival for a trophy and their '
                    'season livery.',
                    style: const TextStyle(color: Board.muted, fontSize: 13),
                  ),
                ],
                if (trophies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  BoardSection(
                    title: 'Trophies',
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final h in trophies)
                            for (final r in h.trophyRivalIds)
                              FlapText(
                                'S${h.number} ✓ ${airlineName(config, r)} · '
                                '${config.rivals.difficulty(h.difficulty).name}',
                                size: 10,
                                color: Board.good,
                              ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const DifficultyPicker(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.standing,
    required this.name,
    required this.badge,
    required this.title,
    required this.color,
    super.key,
  });

  const _StandingRow.header()
    : rank = 0,
      standing = null,
      name = 'Airline',
      badge = '',
      title = '',
      color = Board.muted;

  final int rank;
  final Standing? standing;
  final String name;
  final String badge;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = standing;
    final head = Board.flapStyle(
      size: 10,
      color: Board.muted,
      weight: FontWeight.w500,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: s?.isPlayer ?? false ? Board.raised : null,
        border: Border(
          top: const BorderSide(color: Board.line),
          left: BorderSide(
            color: s?.isPlayer ?? false ? Board.amber : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              s == null ? '#' : '$rank',
              style: s == null ? head : Board.flapStyle(size: 14),
            ),
          ),
          if (s != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: s == null
                ? Text('AIRLINE', style: head)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Board.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${badge.toUpperCase()} · $title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Board.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              s == null ? 'CITIES' : '${s.citiesLed}',
              textAlign: TextAlign.right,
              style: s == null ? head : Board.flapStyle(size: 14),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              s == null ? 'WINS' : '${s.wins}',
              textAlign: TextAlign.right,
              style: s == null ? head : Board.flapStyle(size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blimp Mode, Cruising Altitude or Dogfight. With [onPick] it only reports
/// the choice (the start screen); otherwise it changes the live setting.
class DifficultyPicker extends ConsumerWidget {
  const DifficultyPicker({this.selected, this.onPick, super.key});

  final String? selected;
  final void Function(String id)? onPick;

  static const _feel = {
    'blimp_mode': 'Floaty and relaxed',
    'cruising_altitude': 'The intended balance',
    'dogfight': 'Ruthless',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final live = ref.watch(
      gameSessionProvider.select((s) => s.rivals.difficulty),
    );
    final current = selected ?? live;
    final pick =
        onPick ??
        (String id) => ref
            .read(gameSessionProvider.notifier)
            .act((sim, s, now) => sim.setDifficulty(s, id, now));
    return BoardSection(
      title: 'Rival difficulty',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final d in config.rivals.difficulties)
              InkWell(
                key: Key('difficulty.${d.id}'),
                onTap: () => pick(d.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        d.id == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: d.id == current ? Board.amber : Board.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          d.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: d.id == current ? Board.amber : Board.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${_feel[current] ?? ''}. Change it any time; each season '
              'shows the setting it ended on.',
              style: const TextStyle(color: Board.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rival plane's airline card: hub, fleet, cities led and mood.
class RivalCard extends ConsumerWidget {
  const RivalCard({required this.rivalId, super.key});

  final String rivalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final rivals = sim.rivals;
    final r = config.rivals.rival(rivalId);
    final ui = ref.read(uiProvider.notifier);
    final personality = config.rivals.personality(r.personality);
    final hub = config.world.city(r.hubCityId);
    final heated = rivals.isHeated(state, r);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      decoration: BoxDecoration(
        color: Board.flap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: liveryColor(r.color), width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(
              Icons.airplanemode_active,
              color: liveryColor(r.color),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Text(r.name.toUpperCase(), style: Board.flapStyle(size: 16)),
                const SizedBox(height: 4),
                for (final line in [
                  '${personality.name} · ${tierName(config, rivals.tierOf(state, r))} · '
                      '${rivals.titleOf(state, r)}',
                  'Hub ${hub.name} · ${rivals.fleetSize(state, r)} planes',
                  if (rivals.shareOn(state))
                    'Leads ${rivals.citiesLed(state, r.id, r.regionId)} '
                        '${config.world.region(r.regionId).name} cities',
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: const TextStyle(fontSize: 14, color: Board.ink),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: FlapText(
                        heated ? 'Heated' : 'Friendly rivalry',
                        size: 11,
                        color: heated ? Board.bad : Board.good,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      key: const Key('rivalCard.hub'),
                      onPressed: () => ui.open(RivalryPanel(r.hubCityId)),
                      child: const Text(
                        'Hub rivalry',
                        style: TextStyle(color: Board.amber),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('card.close'),
            tooltip: 'Close',
            onPressed: ui.close,
            icon: const Icon(Icons.close, color: Board.muted),
          ),
        ],
      ),
    );
  }
}

/// Jobs on [airport]'s board the player can see and load now: everything
/// but a rival leader's first look.
List<Job> visibleBoard(
  Simulation sim,
  GameState state,
  AirportState airport,
  DateTime now,
) => [
  for (final j in airport.board)
    if (!sim.rivals.isHeld(state, j, now)) j,
];
