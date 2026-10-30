import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// The challenge board: dailies and the weekly, milestones, the plane parts
/// collection, and what was claimed lately. Opened from the top bar's
/// trophy.
class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen> {
  static const _tabs = ['Active', 'Milestones', 'Parts', 'Done'];
  var _tab = 0;

  void _act(
    GameState Function(Simulation sim, GameState state, DateTime now) action, {
    String? done,
  }) {
    final error = ref.read(gameSessionProvider.notifier).act(action);
    if (error != null) {
      showToast(context, ruleErrorText(error));
    } else if (done != null) {
      showToast(context, done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final title = config.progression.titleFor(state.player.level);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Challenges',
          subtitle: '$title · Lv ${state.player.level}',
          onBack: widget.onClose,
        ),
        Container(
          color: Board.panel,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++) ...[
                  BoardChip(
                    key: Key('challenges.tab.${_tabs[i].toLowerCase()}'),
                    label: _tabs[i],
                    selected: i == _tab,
                    onTap: () => setState(() => _tab = i),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: switch (_tab) {
              0 => _active(state),
              1 => _milestones(state),
              2 => _parts(state, config),
              _ => _done(state),
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _active(GameState state) {
    final sim = ref.read(simulationProvider);
    final challenges = sim.challenges;
    final config = ref.read(gameConfigProvider);
    if (!challenges.isUnlocked(state)) {
      final level = config.progression.featureUnlockLevel['challenges'];
      return [
        _Note(
          'The challenge board opens at airline level $level. Milestones '
          'are already counting.',
        ),
      ];
    }
    final extras = state.extras;
    final now = ref.read(clockProvider).now();
    final weekly = extras.weekly;
    return [
      BoardSection(
        title: 'Daily',
        trailing: Text(
          extras.rerollsLeft == 1
              ? '1 free reroll left'
              : '${extras.rerollsLeft} free rerolls left',
          style: const TextStyle(fontSize: 12, color: Board.muted),
        ),
        child: Column(
          children: [
            for (var i = 0; i < extras.dailies.length; i++)
              _ChallengeRow(
                key: Key('challenges.daily.$i'),
                text: challenges.text(extras.dailies[i]),
                challenge: extras.dailies[i],
                onClaim: () => _act(
                  (sim, s, now) => sim.claimDaily(s, i, now),
                  done: 'Claimed!',
                ),
                onReroll: extras.rerollsLeft > 0
                    ? () => _act((sim, s, now) => sim.rerollDaily(s, i, now))
                    : null,
              ),
            _Footer(
              'New dailies in '
              '${formatCountdown(challenges.nextDayAt(now).difference(now))}',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (weekly != null)
        BoardSection(
          title: 'Weekly',
          trailing: Text(
            '${formatCountdown(challenges.nextWeekAt(now).difference(now))} '
            'left',
            style: Board.flapStyle(size: 12, color: Board.muted),
          ),
          child: _ChallengeRow(
            key: const Key('challenges.weekly'),
            text: challenges.text(weekly),
            challenge: weekly,
            bonus: switch (weekly.bonus) {
              'partCrate' => 'part crate',
              'crewXp' => '${config.extras.challenges.weeklyCrewXp} crew XP',
              _ => null,
            },
            onClaim: () => _act(
              (sim, s, now) => sim.claimWeekly(s, now),
              done: 'Claimed!',
            ),
          ),
        ),
      const SizedBox(height: 12),
      ..._nextMilestone(state),
    ];
  }

  /// The unclaimed milestone closest to done.
  List<Widget> _nextMilestone(GameState state) {
    final challenges = ref.read(simulationProvider).challenges;
    final milestones = ref.read(gameConfigProvider).extras.milestones;
    MilestoneDef? best;
    var bestPct = -1.0;
    for (final m in milestones) {
      if (state.extras.isClaimed(m.id)) continue;
      final pct = challenges.progress(state, m) / m.target;
      if (pct > bestPct) (best, bestPct) = (m, pct);
    }
    if (best == null) return const [];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          'NEXT MILESTONE',
          style: TextStyle(fontSize: 12, color: Board.muted, letterSpacing: 1),
        ),
      ),
      _milestoneRow(state, best),
    ];
  }

  List<Widget> _milestones(GameState state) {
    final challenges = ref.read(simulationProvider).challenges;
    final milestones = [...ref.read(gameConfigProvider).extras.milestones];
    double order(MilestoneDef m) {
      if (state.extras.isClaimed(m.id)) return 3;
      if (challenges.milestoneReady(state, m)) return -1;
      return 1 - (challenges.progress(state, m) / m.target).clamp(0.0, 1.0);
    }

    milestones.sort((a, b) => order(a).compareTo(order(b)));
    final done = milestones.where((m) => state.extras.isClaimed(m.id)).length;
    return [
      _Note('$done of ${milestones.length} milestones done.'),
      const SizedBox(height: 8),
      for (final m in milestones) ...[
        _milestoneRow(state, m),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _milestoneRow(GameState state, MilestoneDef m) {
    final challenges = ref.read(simulationProvider).challenges;
    final reward = challenges.milestoneReward(state.player.level);
    final claimed = state.extras.isClaimed(m.id);
    final progress = challenges.progress(state, m);
    return _Card(
      key: Key('milestone.${m.id}'),
      child: _ChallengeBody(
        text: m.text,
        progress: progress.clamp(0, m.target),
        target: m.target,
        reward: claimed
            ? 'Done'
            : '+${formatCoins(reward.xp)} XP · ${formatCoins(reward.money)}'
                  '${m.unlock == null ? '' : ' · ${unlockLabel(m.unlock!)}'}',
        claimed: claimed,
        onClaim: !claimed && progress >= m.target
            ? () => _act(
                (sim, s, now) => sim.claimMilestone(s, m.id, now),
                done: 'Milestone claimed!',
              )
            : null,
      ),
    );
  }

  List<Widget> _parts(GameState state, GameConfig config) {
    final parts = ref.read(simulationProvider).parts;
    final unlock = config.progression.featureUnlockLevel['partCrates'];
    return [
      _Note(
        state.player.level < (unlock ?? 0)
            ? 'Part crates (marked with a gear) start turning up on cargo '
                  'boards at airline level $unlock. Deliver one to collect '
                  'the part inside.'
            : 'Deliver part crates (marked with a gear) to collect parts. '
                  'A full set builds a special plane.',
      ),
      const SizedBox(height: 8),
      for (final id in config.extras.partBuiltPlanes) ...[
        _SpecialPlaneCard(
          key: Key('parts.$id'),
          model: config.planes.model(id),
          kinds: config.extras.partKinds,
          state: state,
          parts: parts,
          sellPrice: config.extras.duplicatePartSellPrice,
          onBuild: () => _act(
            (sim, s, now) => sim.buildSpecialPlane(s, id, now),
            done: '${config.planes.model(id).name} built!',
          ),
          onSell: (partId) =>
              _act((sim, s, now) => sim.sellSparePart(s, partId, now)),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _done(GameState state) {
    final log = state.extras.log;
    if (log.isEmpty) return const [_Note('Claimed challenges show up here.')];
    return [
      for (final r in log)
        _Card(
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Board.good, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.text, style: const TextStyle(color: Board.ink)),
                    Text(
                      '${r.kind} · +${formatCoins(r.xp)} XP · '
                      '${formatCoins(r.money)}',
                      style: const TextStyle(fontSize: 12, color: Board.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

/// "badge:Storm Chaser" -> "Badge: Storm Chaser".
String unlockLabel(String unlock) {
  if (unlock == 'veteran') return 'Veteran crew';
  final i = unlock.indexOf(':');
  if (i < 0) return unlock;
  final kind = unlock.substring(0, i);
  return '${kind[0].toUpperCase()}${kind.substring(1)}: '
      '${unlock.substring(i + 1)}';
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({
    required this.text,
    required this.challenge,
    required this.onClaim,
    this.onReroll,
    this.bonus,
    super.key,
  });

  final String text;
  final ActiveChallenge challenge;
  final VoidCallback onClaim;
  final VoidCallback? onReroll;
  final String? bonus;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Board.line)),
    ),
    child: _ChallengeBody(
      text: text,
      progress: challenge.progress,
      target: challenge.target,
      reward: challenge.claimed
          ? 'Claimed'
          : '+${formatCoins(challenge.xp)} XP · ${formatCoins(challenge.money)}'
                '${bonus == null ? '' : ' · $bonus'}',
      claimed: challenge.claimed,
      onClaim: challenge.isDone && !challenge.claimed ? onClaim : null,
      onReroll: challenge.isDone ? null : onReroll,
      showReroll: !challenge.isDone && !challenge.claimed && bonus == null,
    ),
  );
}

class _ChallengeBody extends StatelessWidget {
  const _ChallengeBody({
    required this.text,
    required this.progress,
    required this.target,
    required this.reward,
    required this.claimed,
    required this.onClaim,
    this.onReroll,
    this.showReroll = false,
  });

  final String text;
  final int progress;
  final int target;
  final String reward;
  final bool claimed;
  final VoidCallback? onClaim;
  final VoidCallback? onReroll;
  final bool showReroll;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: claimed ? Board.muted : Board.ink,
              ),
            ),
            const SizedBox(height: 6),
            if (onClaim == null && !claimed) ...[
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (progress / target).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Board.line,
                        color: Board.amber,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${formatCoins(progress)} / ${formatCoins(target)}',
                    style: Board.flapStyle(size: 11, color: Board.muted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              reward,
              style: TextStyle(
                fontSize: 12,
                color: onClaim != null ? Board.amber : Board.muted,
              ),
            ),
          ],
        ),
      ),
      if (onClaim != null) ...[
        const SizedBox(width: 10),
        AmberButton(label: 'Claim', mono: true, height: 36, onPressed: onClaim),
      ] else if (showReroll) ...[
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Reroll',
          onPressed: onReroll,
          icon: Icon(
            Icons.casino_outlined,
            color: onReroll != null ? Board.amber : Board.line,
          ),
        ),
      ],
    ],
  );
}

class _SpecialPlaneCard extends StatelessWidget {
  const _SpecialPlaneCard({
    required this.model,
    required this.kinds,
    required this.state,
    required this.parts,
    required this.sellPrice,
    required this.onBuild,
    required this.onSell,
    super.key,
  });

  final PlaneModel model;
  final List<String> kinds;
  final GameState state;
  final Parts parts;
  final int sellPrice;
  final VoidCallback onBuild;
  final void Function(String partId) onSell;

  @override
  Widget build(BuildContext context) {
    final built = state.extras.isBuilt(model.id);
    final canBuild = parts.canBuild(state, model.id);
    final spares = [
      for (final k in kinds)
        if (parts.spares(state, ExtrasConfig.partId(model.id, k)) > 0) k,
    ];
    return BoardSection(
      title: model.name,
      trailing: built
          ? Text('BUILT', style: Board.flapStyle(size: 12, color: Board.good))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${model.look}. ${model.seats} seats, ${model.cargoSlots} cargo, '
              '${formatKm(model.rangeKm.toDouble())}, ${model.speedKmh.round()} km/h. '
              '${_twist(model.twist)}',
              style: const TextStyle(fontSize: 13, color: Board.muted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final k in kinds)
                  Expanded(
                    child: _PartSlot(
                      kind: k,
                      count: state.extras.partCount(
                        ExtrasConfig.partId(model.id, k),
                      ),
                      built: built,
                    ),
                  ),
              ],
            ),
            if (!built) ...[
              const SizedBox(height: 10),
              AmberButton(
                key: Key('parts.${model.id}.build'),
                label: canBuild ? 'Build ${model.name}' : 'Needs all 4 parts',
                onPressed: canBuild ? onBuild : null,
              ),
            ],
            for (final k in spares) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Spare ${_kindName(k).toLowerCase()} '
                      '×${parts.spares(state, ExtrasConfig.partId(model.id, k))}',
                      style: const TextStyle(color: Board.ink),
                    ),
                  ),
                  AmberButton(
                    key: Key('parts.${model.id}.$k.sell'),
                    label: 'Sell · ${formatCoins(sellPrice)}',
                    outlined: true,
                    height: 34,
                    onPressed: () => onSell(ExtrasConfig.partId(model.id, k)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _twist(String? twist) => switch (twist) {
    'sightseeing' =>
      'Flies sightseeing tours: round trips that land back home and pay 3×.',
    'supersonic' => 'Supersonic, but burns 3× fuel.',
    'airship' => 'Slow and huge, burns no fuel, ignores the jet stream.',
    _ => '',
  };
}

String _kindName(String kind) => '${kind[0].toUpperCase()}${kind.substring(1)}';

class _PartSlot extends StatelessWidget {
  const _PartSlot({
    required this.kind,
    required this.count,
    required this.built,
  });

  final String kind;
  final int count;
  final bool built;

  @override
  Widget build(BuildContext context) {
    final have = built || count > 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: have ? Board.raised : Board.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: have ? Board.amber : Board.line),
      ),
      child: Column(
        children: [
          Icon(
            have ? Icons.settings : Icons.settings_outlined,
            size: 20,
            color: have ? Board.amber : Board.line,
          ),
          const SizedBox(height: 4),
          Text(
            _kindName(kind),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: have ? Board.ink : Board.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 0),
    decoration: BoxDecoration(
      color: Board.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Board.line),
    ),
    child: child,
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Text(text, style: const TextStyle(color: Board.muted)),
  );
}

class _Footer extends StatelessWidget {
  const _Footer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(10),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: Board.muted),
    ),
  );
}
