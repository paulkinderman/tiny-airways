import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'crew_detail.dart';
import 'crew_format.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

enum _CrewTab { roster, rookies, veterans }

/// The Crew tab: everyone on staff by plane and airport, the rookie shelf
/// and pilot school, and the veteran of the day. Tapping someone opens
/// their skill tree (or staff upgrades) and where they work.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key});

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  _CrewTab _tab = _CrewTab.roster;
  String? _selected;

  void _open(String memberId) => setState(() => _selected = memberId);

  /// Runs a crew action; on success returns the new state.
  GameState? _act(
    GameState Function(Simulation sim, GameState state, DateTime now) action,
  ) {
    final session = ref.read(gameSessionProvider.notifier);
    final error = session.act(action);
    if (error != null) {
      showToast(context, ruleErrorText(error));
      return null;
    }
    return ref.read(gameSessionProvider);
  }

  void _hire(CrewOffer offer) {
    final s = _act((sim, s, now) => sim.hireCrew(s, offer.id, now));
    if (s == null) return;
    showToast(
      context,
      'Hired ${offer.member.name}. Now choose where they work.',
    );
    _open(s.crew.members.last.id);
  }

  void _hirePilot() {
    final s = _act((sim, s, now) => sim.hirePilot(s, now));
    if (s == null) return;
    final pilot = s.crew.members.last;
    final config = ref.read(gameConfigProvider);
    showToast(
      context,
      'Hired ${pilot.name}, '
      '${memberPlace(config, s, pilot) == 'unassigned' ? 'waiting for a plane' : memberPlace(config, s, pilot)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final selected = _selected;
    if (selected != null && state.crew.member(selected) != null) {
      return CrewDetail(
        key: ValueKey(selected),
        memberId: selected,
        onBack: () => setState(() => _selected = null),
      );
    }
    final staff = state.crew.members.length;
    return ColoredBox(
      color: Board.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Board.panel,
              border: Border(bottom: BorderSide(color: Board.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('CREW', style: Board.flapStyle(size: 20)),
                    ),
                    Text(
                      '$staff crew on staff',
                      style: const TextStyle(fontSize: 13, color: Board.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Segments(
                  value: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
              ],
            ),
          ),
          Expanded(
            child: TickBuilder(
              builder: (context, now) => switch (_tab) {
                _CrewTab.roster => _Roster(
                  onOpen: _open,
                  onHirePilot: _hirePilot,
                  now: now,
                ),
                _CrewTab.rookies => _Rookies(
                  now: now,
                  onHire: _hire,
                  onHirePilot: _hirePilot,
                ),
                _CrewTab.veterans => _Veterans(now: now, onHire: _hire),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.value, required this.onChanged});

  final _CrewTab value;
  final void Function(_CrewTab tab) onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Board.raised,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (final (tab, label) in [
          (_CrewTab.roster, 'Roster'),
          (_CrewTab.rookies, 'Rookies'),
          (_CrewTab.veterans, 'Veterans'),
        ])
          Expanded(
            child: Material(
              color: tab == value ? Board.amber : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: Key('crew.tab.${tab.name}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(tab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: tab == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: tab == value ? Board.amberInk : Board.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// One person in the roster: avatar, name, role and level, and a badge
/// when they have skill points to spend.
class CrewRow extends ConsumerWidget {
  const CrewRow({required this.member, required this.onTap, super.key});

  final CrewMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final points = ref.read(simulationProvider).crew.unspentPoints(member);
    return InkWell(
      key: Key('crew.member.${member.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Board.line)),
        ),
        child: Row(
          children: [
            CrewAvatar(name: member.name, size: 38, veteran: member.isVeteran),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Board.ink,
                    ),
                  ),
                  Text(
                    memberSubtitle(config, member),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Board.muted),
                  ),
                ],
              ),
            ),
            if (points > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Board.amber,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$points PT',
                  style: Board.flapStyle(size: 10, color: Board.amberInk),
                ),
              ),
            const Icon(Icons.chevron_right, color: Board.muted),
          ],
        ),
      ),
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster({
    required this.onOpen,
    required this.onHirePilot,
    required this.now,
  });

  final void Function(String memberId) onOpen;
  final VoidCallback onHirePilot;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final sim = ref.read(simulationProvider);
    final desk = sim.crew;
    final short = [
      for (final p in state.planes)
        if (sim.rules.crew.departureProblem(state, p) != null) p,
    ];
    final bench = [
      for (final m in state.crew.members)
        if (!m.isAssigned) m,
    ];
    final shelf = desk.shelves(state, now);

    Widget empty(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Text(text, style: const TextStyle(color: Board.muted)),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final p in short)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              key: Key('crew.short.${p.id}'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Board.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Board.bad),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Board.bad),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${planeName(config, p)}: '
                      '${sim.rules.crew.departureProblem(state, p)!.toLowerCase()} to fly.',
                      style: const TextStyle(color: Board.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AmberButton(
                    key: Key('crew.hirePilotFor.${p.id}'),
                    label: 'Hire ${formatCoins(shelf.pilotPrice)}',
                    mono: true,
                    height: 36,
                    onPressed: state.player.money >= shelf.pilotPrice
                        ? onHirePilot
                        : null,
                  ),
                ],
              ),
            ),
          ),
        BoardSection(
          title: 'Planes',
          trailing: const Icon(Icons.flight, color: Board.amber, size: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.planes.isEmpty) empty('No planes yet.'),
              for (final p in state.planes) ...[
                _PlaceHeading(
                  title: planeName(config, p),
                  detail: () {
                    final s = desk.seats(p);
                    final crew = state.crew.onPlane(p.id).length;
                    final flying = p.status != PlaneStatus.parked;
                    return '$crew of ${s.pilots + s.open} seats'
                        '${flying ? ' · in the air' : ''}';
                  }(),
                ),
                for (final m in state.crew.onPlane(p.id))
                  CrewRow(member: m, onTap: () => onOpen(m.id)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        BoardSection(
          title: 'Airports',
          trailing: const Icon(Icons.place, color: Board.amber, size: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in state.airports) ...[
                _PlaceHeading(
                  title: config.world.city(a.cityId).name,
                  detail:
                      '${state.crew.atAirport(a.cityId).length} of '
                      '${desk.staffSlots(state, a.cityId)} staff',
                ),
                for (final m in state.crew.atAirport(a.cityId))
                  CrewRow(member: m, onTap: () => onOpen(m.id)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        BoardSection(
          title: 'Unassigned',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bench.isEmpty)
                empty('Everyone is at work. Hire more on the Rookies shelf.'),
              for (final m in bench)
                CrewRow(member: m, onTap: () => onOpen(m.id)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaceHeading extends StatelessWidget {
  const _PlaceHeading({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Board.line)),
    ),
    child: Row(
      children: [
        Flexible(child: FlapText(title, size: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            detail,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Board.muted),
          ),
        ),
      ],
    ),
  );
}

/// A shelf offer: who they are, their signature and the Hire button.
class _OfferCard extends ConsumerWidget {
  const _OfferCard({
    required this.offer,
    required this.onHire,
    this.veteran = false,
  });

  final CrewOffer offer;
  final void Function(CrewOffer offer) onHire;
  final bool veteran;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final money = ref.watch(gameSessionProvider.select((s) => s.player.money));
    final m = offer.member;
    final sig = m.signatureId == null
        ? null
        : config.crew.signature(m.signatureId!);
    final role = config.crew.role(m.roleId);
    final subtitle = veteran
        ? [
            role.name,
            growthSummary(config, m),
          ].where((s) => s.isNotEmpty).join(' · ')
        : memberSubtitle(config, m);
    final button = AmberButton(
      key: Key('crew.hire.${offer.id}'),
      label: offer.taken ? 'Hired' : 'Hire ${formatCoins(offer.price)}',
      mono: true,
      height: 44,
      onPressed: offer.taken || money < offer.price
          ? null
          : () => onHire(offer),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: veteran ? Board.flap : Board.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: veteran ? Board.amber : Board.line,
          width: veteran ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (veteran) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'VETERAN OF THE DAY',
                    style: Board.flapStyle(size: 12),
                  ),
                ),
                Text(
                  'LV ${m.level}',
                  style: Board.flapStyle(size: 12, color: Board.ink),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CrewAvatar(name: m.name, veteran: veteran),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Board.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: Board.muted),
                    ),
                  ],
                ),
              ),
              if (sig != null && !veteran) ...[
                const SizedBox(width: 8),
                SignatureChip(sig.name),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (veteran) ...[
            if (offer.bio != null)
              Text(
                offer.bio!,
                style: const TextStyle(fontSize: 13, color: Board.ink),
              ),
            if (sig != null) ...[
              const SizedBox(height: 6),
              Text(
                'Signature: ${sig.name}. From ${config.world.city(m.homeCityId).name}.',
                style: const TextStyle(fontSize: 12, color: Board.signature),
              ),
            ],
            const SizedBox(height: 12),
            button,
          ] else
            Row(
              children: [
                Expanded(
                  child: Text(
                    sig == null
                        ? 'Grows with money: three upgrade paths at their airport'
                        : signatureBlurb(config, m),
                    style: const TextStyle(fontSize: 13, color: Board.muted),
                  ),
                ),
                const SizedBox(width: 10),
                button,
              ],
            ),
        ],
      ),
    );
  }
}

class _Rookies extends ConsumerWidget {
  const _Rookies({
    required this.now,
    required this.onHire,
    required this.onHirePilot,
  });

  final DateTime now;
  final void Function(CrewOffer offer) onHire;
  final VoidCallback onHirePilot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final shelf = ref.read(simulationProvider).crew.shelves(state, now);
    final growth = (config.crew.hiring.nonPilotPriceGrowth * 100).round();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'New rookies in ${formatCountdown(shelf.rookiesRefreshAt.difference(now))}',
                style: const TextStyle(fontSize: 13, color: Board.muted),
              ),
            ),
            Text(
              '+$growth% PER HIRE',
              style: Board.flapStyle(size: 11, color: Board.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final o in shelf.rookies) _OfferCard(offer: o, onHire: onHire),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Board.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Board.line),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Board.raised,
                child: Icon(Icons.school_outlined, color: Board.amber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pilot school',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Board.ink,
                      ),
                    ),
                    Text(
                      'A rookie pilot, always available. Priced for your '
                      '${shelf.pilotClass.name.toLowerCase()} planes.',
                      style: const TextStyle(fontSize: 13, color: Board.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AmberButton(
                key: const Key('crew.hirePilot'),
                label: 'Hire ${formatCoins(shelf.pilotPrice)}',
                mono: true,
                height: 44,
                onPressed: state.player.money >= shelf.pilotPrice
                    ? onHirePilot
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Veterans extends ConsumerWidget {
  const _Veterans({required this.now, required this.onHire});

  final DateTime now;
  final void Function(CrewOffer offer) onHire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final shelf = ref.read(simulationProvider).crew.shelves(state, now);
    final vet = shelf.veteran;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'A new veteran in ${formatCountdown(shelf.veteranRefreshAt.difference(now))}. '
          'Veterans arrive with their skill points already spent.',
          style: const TextStyle(fontSize: 13, color: Board.muted),
        ),
        const SizedBox(height: 10),
        if (vet == null)
          const Text(
            'You have hired every veteran there is.',
            style: TextStyle(color: Board.muted),
          )
        else
          _OfferCard(offer: vet, onHire: onHire, veteran: true),
      ],
    );
  }
}
