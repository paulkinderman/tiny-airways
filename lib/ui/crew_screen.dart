import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'crew_detail.dart';
import 'crew_format.dart';
import 'crew_seats.dart';
import 'format.dart';
import 'growth_sheets.dart';
import 'theme.dart';
import 'widgets.dart';

enum _CrewTab { planes, roster, rookies }

/// What a crew member can upgrade right now.
enum CrewUpgrade {
  /// Flight crew with skill points to spend.
  points,

  /// Airport staff with a next tier the airline can afford.
  staff,
}

/// What [member] can upgrade now, or null if nothing.
CrewUpgrade? crewUpgrade(Simulation sim, GameState state, CrewMember member) {
  final desk = sim.crew;
  if (desk.unspentPoints(member) > 0) return CrewUpgrade.points;
  final paths = sim.rules.config.crew.staffPaths[member.roleId];
  if (paths == null || member.cityId == null) return null;
  for (final p in paths) {
    final cost = desk.staffTierCost(state, member, p.id);
    if (cost != null && cost <= state.player.money) return CrewUpgrade.staff;
  }
  return null;
}

/// How many flight crew have skill points to spend: the Crew tab's badge.
/// Affordable staff tiers are left out so the badge doesn't stay lit
/// whenever the airline has money.
int crewWithPoints(Simulation sim, GameState state) =>
    state.crew.members.where((m) => sim.crew.unspentPoints(m) > 0).length;

/// A crew member for the Crew tab to open next, e.g. from the level-up
/// toast. The Crew tab clears it once it has opened them.
final crewFocusProvider = NotifierProvider<CrewFocus, String?>(CrewFocus.new);

class CrewFocus extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(String? memberId) => state = memberId;
}

/// The Crew tab: the Planes view (every seat, plane by plane), everyone on
/// staff by plane and airport, and the rookie shelf
/// and pilot school. Tapping someone opens
/// their skill tree (or staff upgrades) and where they work.
class CrewScreen extends ConsumerStatefulWidget {
  const CrewScreen({super.key});

  @override
  ConsumerState<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends ConsumerState<CrewScreen> {
  _CrewTab _tab = _CrewTab.planes;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(crewFocusProvider);
    if (_selected != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(crewFocusProvider.notifier).focus(null),
      );
    }
  }

  void _open(String memberId) => setState(() => _selected = memberId);

  /// Runs a crew action; on success returns the new state.
  GameState? _act(
    GameState Function(Simulation sim, GameState state, DateTime now) action,
  ) {
    final session = ref.read(gameSessionProvider.notifier);
    final error = session.act(action);
    if (error != null) {
      showToast(context, ruleErrorText(error), kind: ToastKind.error);
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
      kind: ToastKind.done,
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
      kind: ToastKind.done,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(crewFocusProvider, (_, id) {
      if (id == null) return;
      setState(() => _selected = id);
      ref.read(crewFocusProvider.notifier).focus(null);
    });
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
    final desk = ref.read(simulationProvider).crew;
    final pilots = desk.pilotCount(state);
    final pilotSlots = desk.pilotSlots(state);
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
                      '$staff crew · $pilots/$pilotSlots pilots',
                      key: const Key('crew.pilotCount'),
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
                _CrewTab.planes => CrewSeatsBoard(now: now, onOpen: _open),
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
          (_CrewTab.planes, 'Planes'),
          (_CrewTab.roster, 'Roster'),
          (_CrewTab.rookies, 'Rookies'),
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
                      fontSize: 14,
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

/// One person in the roster: avatar, name, role and level, and an
/// UPGRADE pill when they have skill points to spend (or, for airport
/// staff, a tier the airline can afford).
class CrewRow extends ConsumerWidget {
  const CrewRow({
    required this.member,
    required this.onTap,
    this.keyPrefix = 'crew.member',
    super.key,
  });

  final CrewMember member;
  final VoidCallback onTap;

  /// Rows in the "Ready to upgrade" group use another prefix, so the same
  /// person's row in their plane or airport keeps its own key.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final points = sim.crew.unspentPoints(member);
    final upgrade = crewUpgrade(sim, state, member);
    return InkWell(
      key: Key('$keyPrefix.${member.id}'),
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
            if (upgrade != null)
              UpgradePill(
                key: Key('crew.upgrade.${member.id}'),
                label: switch (upgrade) {
                  CrewUpgrade.points =>
                    points > 1 ? 'UPGRADE ×$points' : 'UPGRADE',
                  CrewUpgrade.staff => 'UPGRADE',
                },
                outlined: upgrade == CrewUpgrade.staff,
              ),
            const Icon(Icons.chevron_right, color: Board.muted),
          ],
        ),
      ),
    );
  }
}

/// The amber "UPGRADE" pill on a crew row. Outlined for airport staff
/// tiers, which cost coins rather than points.
class UpgradePill extends StatelessWidget {
  const UpgradePill({required this.label, this.outlined = false, super.key});

  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
    decoration: BoxDecoration(
      color: outlined ? const Color(0xFF3A2E10) : Board.amber,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Board.amber, width: 1.5),
      boxShadow: outlined
          ? null
          : const [BoxShadow(color: Color(0x66FFC53D), blurRadius: 10)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.arrow_upward_rounded,
          size: 13,
          color: outlined ? Board.amber : Board.amberInk,
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: Board.flapStyle(
            size: 10,
            color: outlined ? Board.amber : Board.amberInk,
          ),
        ),
      ],
    ),
  );
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
    final pilotsFull = desk.freePilotSlots(state) == 0;
    final ready = [
      for (final m in state.crew.members)
        if (crewUpgrade(sim, state, m) != null) m,
    ];

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
                    label: pilotsFull
                        ? 'Pilots full'
                        : 'Hire ${formatCoins(shelf.pilotPrice)}',
                    mono: true,
                    height: 36,
                    onPressed:
                        !pilotsFull && state.player.money >= shelf.pilotPrice
                        ? onHirePilot
                        : null,
                  ),
                ],
              ),
            ),
          ),
        if (ready.isNotEmpty) ...[
          BoardSection(
            key: const Key('crew.ready'),
            title: 'Ready to upgrade',
            trailing: const Icon(
              Icons.arrow_circle_up_rounded,
              color: Board.amber,
              size: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in ready)
                  CrewRow(
                    member: m,
                    keyPrefix: 'crew.ready',
                    onTap: () => onOpen(m.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
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
                    final where = p.isStored
                        ? ' · in the hangar'
                        : p.onGround
                        ? ''
                        : ' · in the air';
                    return '$crew of ${s.pilots + s.open} seats$where';
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
  const _OfferCard({required this.offer, required this.onHire});

  final CrewOffer offer;
  final void Function(CrewOffer offer) onHire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final money = ref.watch(gameSessionProvider.select((s) => s.player.money));
    final m = offer.member;
    final sig = m.signatureId == null
        ? null
        : config.crew.signature(m.signatureId!);
    final subtitle = memberSubtitle(config, m);
    final pilotsFull =
        m.roleId == 'pilot' &&
        ref
                .read(simulationProvider)
                .crew
                .freePilotSlots(ref.watch(gameSessionProvider)) ==
            0;
    final button = AmberButton(
      key: Key('crew.hire.${offer.id}'),
      label: offer.taken
          ? 'Hired'
          : pilotsFull
          ? 'Pilots full'
          : 'Hire ${formatCoins(offer.price)}',
      mono: true,
      height: 44,
      onPressed: offer.taken || pilotsFull || money < offer.price
          ? null
          : () => onHire(offer),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Board.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Board.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CrewAvatar(name: m.name),
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
              if (sig != null) ...[
                const SizedBox(width: 8),
                SignatureChip(sig.name),
              ],
            ],
          ),
          const SizedBox(height: 12),
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
    final desk = ref.read(simulationProvider).crew;
    final shelf = desk.shelves(state, now);
    final growth = (config.crew.hiring.nonPilotPriceGrowth * 100).round();
    final pilots = desk.pilotCount(state);
    final pilotSlots = desk.pilotSlots(state);
    final pilotsFull = desk.freePilotSlots(state) == 0;
    final license = desk.pilotLicensePrice(state);
    final canLicense = state.player.money >= license;
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
                      '${shelf.pilotClass.name.toLowerCase()} planes. '
                      '$pilots of $pilotSlots pilots employed.',
                      style: const TextStyle(fontSize: 13, color: Board.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AmberButton(
                key: const Key('crew.hirePilot'),
                label: pilotsFull
                    ? 'Pilots full'
                    : 'Hire ${formatCoins(shelf.pilotPrice)}',
                mono: true,
                height: 44,
                onPressed: !pilotsFull && state.player.money >= shelf.pilotPrice
                    ? onHirePilot
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AmberButton(
          key: const Key('crew.buyPilotLicense'),
          outlined: !pilotsFull,
          label: canLicense
              ? 'Pilot license +1 pilot · ${formatCoins(license)}'
              : 'Pilot license · need ${formatCoins(license)}',
          onPressed: canLicense
              ? () => actOrExplain(
                  context,
                  ref,
                  (sim, s, now) => sim.buyPilotLicense(s, now),
                )
              : null,
        ),
        const SizedBox(height: 6),
        const Text(
          'Your airline may employ a limited number of pilots. Levelling up '
          'adds more; a license adds one now.',
          style: TextStyle(fontSize: 12, color: Board.muted),
        ),
      ],
    );
  }
}
