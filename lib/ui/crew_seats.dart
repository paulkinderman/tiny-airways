import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'crew_format.dart';
import 'format.dart';
import 'growth_sheets.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Crew tab's Planes view: every plane with its seats laid out, pilot
/// seats first. Tapping an empty seat picks who sits there; tapping someone
/// in a seat swaps, moves or benches them. Auto-fill puts idle pilots into
/// empty pilot seats.
class CrewSeatsBoard extends ConsumerWidget {
  const CrewSeatsBoard({required this.now, required this.onOpen, super.key});

  final DateTime now;

  /// Opens a crew member's page (skills and where they work).
  final void Function(String memberId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final desk = sim.crew;
    final short = desk.planesShortOfPilots(state);
    final idle = desk.idlePilots(state);
    int order(Plane p) => short.contains(p)
        ? 0
        : p.status == PlaneStatus.parked
        ? 1
        : 2;
    final planes = [...state.planes]
      ..sort((a, b) => order(a).compareTo(order(b)));

    final headline = short.isEmpty
        ? 'Every parked plane has its pilots'
        : short.length == 1
        ? '1 plane can\'t fly'
        : '${short.length} planes can\'t fly';
    final idleText = idle.isEmpty
        ? 'no idle pilots'
        : idle.length == 1
        ? '1 pilot idle'
        : '${idle.length} pilots idle';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          key: const Key('crew.seats.summary'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Board.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Board.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: headline,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Board.ink,
                        ),
                      ),
                      TextSpan(text: ' · $idleText\n'),
                      const TextSpan(
                        text: 'Tap a seat to fill it, or tap someone to swap.',
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, color: Board.muted),
                ),
              ),
              const SizedBox(width: 10),
              AmberButton(
                key: const Key('crew.seats.autoFill'),
                label: 'Auto-fill',
                height: 38,
                onPressed: short.isEmpty || idle.isEmpty
                    ? null
                    : () {
                        final before = ref.read(gameSessionProvider);
                        if (!actOrExplain(
                          context,
                          ref,
                          (sim, s, now) => sim.autoFillPilots(s, now),
                        )) {
                          return;
                        }
                        final after = ref.read(gameSessionProvider);
                        final moved = after.crew.members
                            .where(
                              (m) =>
                                  m.planeId != null &&
                                  before.crew.member(m.id)?.planeId == null,
                            )
                            .length;
                        showToast(
                          context,
                          moved == 1
                              ? 'Seated 1 idle pilot.'
                              : 'Seated $moved idle pilots.',
                          kind: ToastKind.done,
                        );
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (planes.isEmpty)
          const Text('No planes yet.', style: TextStyle(color: Board.muted)),
        for (final p in planes)
          _PlaneSeats(
            plane: p,
            short: short.contains(p),
            now: now,
            onOpen: onOpen,
          ),
      ],
    );
  }
}

/// One plane's card: name, status, and its seats.
class _PlaneSeats extends ConsumerWidget {
  const _PlaneSeats({
    required this.plane,
    required this.short,
    required this.now,
    required this.onOpen,
  });

  final Plane plane;
  final bool short;
  final DateTime now;
  final void Function(String memberId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final desk = ref.read(simulationProvider).crew;
    final seats = desk.seats(plane);
    final crew = state.crew.onPlane(plane.id);
    final pilots = [
      for (final m in crew)
        if (m.roleId == 'pilot') m,
    ];
    final inPilotSeats = pilots.take(seats.pilots).toList();
    final inOpenSeats = [
      for (final m in crew)
        if (!inPilotSeats.contains(m)) m,
    ];
    final parked = plane.status == PlaneStatus.parked;
    final model = config.planes.model(plane.modelId);
    final className = config.planes.planeClass(model.classId).name;
    final (tag, tagColor, tagInk) = !parked
        ? ('IN THE AIR', Board.raised, Board.muted)
        : short
        ? (
            seats.pilots - pilots.length == 1 ? 'NEEDS PILOT' : 'NEEDS PILOTS',
            const Color(0xFF3A1A18),
            Board.bad,
          )
        : ('READY', const Color(0xFF14301F), Board.good);
    final leg = plane.leg;
    final where = parked || leg == null
        ? '$className · ${config.world.city(plane.cityId).name}'
        : '→ ${config.world.city(leg.toCityId).name} · '
              '${formatCountdown(_left(leg.arriveAt))}';

    final tiles = <Widget>[
      for (var i = 0; i < seats.pilots; i++)
        i < inPilotSeats.length
            ? _FilledSeat(
                key: Key('crew.seat.${plane.id}.$i'),
                member: inPilotSeats[i],
                locked: !parked,
                onTap: () => _openMember(context, inPilotSeats[i].id),
              )
            : _EmptySeat(
                key: Key('crew.seat.${plane.id}.$i'),
                label: '+ Pilot',
                urgent: parked,
                onTap: parked ? () => _openEmpty(context, true) : null,
              ),
      for (var i = 0; i < seats.open; i++)
        i < inOpenSeats.length
            ? _FilledSeat(
                key: Key('crew.seat.${plane.id}.${seats.pilots + i}'),
                member: inOpenSeats[i],
                locked: !parked,
                onTap: () => _openMember(context, inOpenSeats[i].id),
              )
            : _EmptySeat(
                key: Key('crew.seat.${plane.id}.${seats.pilots + i}'),
                label: '+ Crew',
                urgent: false,
                onTap: parked ? () => _openEmpty(context, false) : null,
              ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: parked ? 1 : 0.8,
        child: Container(
          key: Key('crew.planeSeats.${plane.id}'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: Board.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: short ? Board.bad : Board.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Flexible(child: FlapText(planeName(config, plane), size: 13)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tagColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      tag,
                      style: Board.flapStyle(size: 9, color: tagInk),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      where,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Board.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, c) {
                  final w = tiles.length == 1
                      ? c.maxWidth
                      : (c.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tiles) SizedBox(width: w, child: t),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Duration _left(DateTime at) {
    final d = at.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  void _openEmpty(BuildContext context, bool pilotSeat) => showBoardSheet(
    context,
    _FillSeatSheet(planeId: plane.id, pilotSeat: pilotSeat),
  );

  void _openMember(BuildContext context, String memberId) => showBoardSheet(
    context,
    _SeatMemberSheet(memberId: memberId, onOpen: onOpen),
  );
}

class _FilledSeat extends ConsumerWidget {
  const _FilledSeat({
    required this.member,
    required this.locked,
    required this.onTap,
    super.key,
  });

  final CrewMember member;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final role = config.crew.role(member.roleId).name;
    return Material(
      color: Board.raised,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              CrewAvatar(
                name: member.name,
                size: 30,
                veteran: member.isVeteran,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Board.ink,
                      ),
                    ),
                    Text(
                      '$role · Lv ${member.level}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Board.muted),
                    ),
                  ],
                ),
              ),
              if (locked)
                const Icon(Icons.lock_outline, size: 14, color: Board.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat({
    required this.label,
    required this.urgent,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool urgent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? Board.bad : Board.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: urgent ? Board.bad : const Color(0xFF3B4A5E),
            width: 1.5,
          ),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, color: color)),
      ),
    );
  }
}

// Sheets -----------------------------------------------------------------

/// Runs [action]; on success closes the sheet and shows [done].
void _actAndClose(
  BuildContext context,
  WidgetRef ref,
  GameState Function(Simulation sim, GameState state, DateTime now) action,
  String done,
) {
  if (!actOrExplain(context, ref, action)) return;
  showToast(context, done, kind: ToastKind.done);
  Navigator.of(context).pop();
}

/// What it costs [state] to take [member] off their plane: the plane left
/// short of pilots, if any.
String? _leavesShort(
  Simulation sim,
  GameState before,
  GameState after,
  CrewMember member,
) {
  final id = member.planeId;
  if (id == null) return null;
  final plane = after.plane(id);
  if (plane == null || plane.status != PlaneStatus.parked) return null;
  final was = sim.rules.crew.departureProblem(before, before.plane(id)!);
  final now = sim.rules.crew.departureProblem(after, plane);
  return was == null && now != null ? plane.id : null;
}

GameState? _try(GameState Function() f) {
  try {
    return f();
  } on RuleException {
    return null;
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
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
  );
}

class _Group extends StatelessWidget {
  const _Group(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
    child: Text(
      title.toUpperCase(),
      style: Board.flapStyle(size: 11, color: Board.muted),
    ),
  );
}

/// A person (or the hire option) in a sheet, with its action on the right.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.warning,
    this.action,
    this.onTap,
    this.trailing,
    super.key,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String? warning;
  final String? action;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Opacity(
      opacity: onTap == null && trailing == null ? 0.45 : 1,
      child: Material(
        color: Board.raised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Board.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Board.muted,
                        ),
                      ),
                      if (warning != null)
                        Text(
                          warning!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Board.bad,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
                if (action != null && onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      action!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Board.amber,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _role(WidgetRef ref, CrewMember m) =>
    '${ref.read(gameConfigProvider).crew.role(m.roleId).name} · Lv ${m.level}';

String _inAir(Plane plane, DateTime now) {
  final leg = plane.leg;
  if (leg == null) return 'In the air';
  final d = leg.arriveAt.difference(now);
  return 'In the air, lands in ${formatCountdown(d.isNegative ? Duration.zero : d)}';
}

/// Picks who sits in an empty seat on parked plane [planeId]: idle crew,
/// crew on other planes, anyone in the air (greyed), and, for a pilot
/// seat, a rookie hired straight into it.
class _FillSeatSheet extends ConsumerWidget {
  const _FillSeatSheet({required this.planeId, required this.pilotSeat});

  final String planeId;
  final bool pilotSeat;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TickBuilder(
    builder: (context, now) {
      final state = ref.watch(gameSessionProvider);
      final config = ref.watch(gameConfigProvider);
      final sim = ref.read(simulationProvider);
      final desk = sim.crew;
      final plane = state.plane(planeId);
      if (plane == null || plane.status != PlaneStatus.parked) {
        return const SizedBox.shrink();
      }
      final name = planeName(config, plane);
      final need = sim.rules.crew.departureProblem(state, plane);
      final candidates = [
        for (final m in state.crew.members)
          if (config.crew.role(m.roleId).isFlightCrew &&
              m.planeId != planeId &&
              (!pilotSeat || m.roleId == 'pilot'))
            m,
      ]..sort((a, b) => b.level.compareTo(a.level));
      final idle = [
        for (final m in candidates)
          if (m.planeId == null) m,
      ];
      final elsewhere = [
        for (final m in candidates)
          if (m.planeId != null) m,
      ];
      final shelf = desk.shelves(state, now);
      final freeSlots = desk.freePilotSlots(state);

      Widget row(CrewMember m) {
        final from = m.planeId == null ? null : state.plane(m.planeId!);
        final after = _try(
          () => desk.assignToPlane(state, m.id, planeId, state.simulatedTo),
        );
        final short = after == null ? null : _leavesShort(sim, state, after, m);
        final where = from == null ? 'not on a plane' : planeName(config, from);
        return _PickRow(
          key: Key('crew.seatPick.${m.id}'),
          leading: CrewAvatar(name: m.name, size: 36, veteran: m.isVeteran),
          title: m.name,
          subtitle: '${_role(ref, m)} · $where',
          warning: from != null && from.status != PlaneStatus.parked
              ? _inAir(from, now)
              : short != null
              ? '$where would be short a pilot'
              : null,
          action: m.planeId == null ? 'Assign' : 'Move',
          onTap: after == null
              ? null
              : () => _actAndClose(
                  context,
                  ref,
                  (sim, s, now) => sim.assignCrewToPlane(s, m.id, planeId, now),
                  '${m.name} now flies $name.',
                ),
        );
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          _SheetHeader(
            title: pilotSeat ? 'Pilot for $name' : 'Crew for $name',
            subtitle:
                'Parked at ${config.world.city(plane.cityId).name}'
                '${need == null ? '' : ' · ${need.toLowerCase()}'}',
          ),
          const _Group('Idle'),
          if (idle.isEmpty)
            Text(
              pilotSeat
                  ? 'No pilots are waiting for a plane.'
                  : 'No flight crew are waiting for a plane.',
              style: const TextStyle(fontSize: 13, color: Board.muted),
            ),
          for (final m in idle) row(m),
          if (elsewhere.isNotEmpty) ...[
            const _Group('On other planes'),
            for (final m in elsewhere) row(m),
          ],
          if (pilotSeat) ...[
            const _Group('Hire'),
            _PickRow(
              leading: const CircleAvatar(
                radius: 18,
                backgroundColor: Board.raised,
                child: Icon(
                  Icons.school_outlined,
                  color: Board.amber,
                  size: 18,
                ),
              ),
              title: 'Rookie pilot',
              subtitle: freeSlots == 0
                  ? 'Pilots full · buy a license on Rookies'
                  : 'Starts in this seat · '
                        '${desk.pilotCount(state)} of ${desk.pilotSlots(state)} '
                        'pilots employed',
              trailing: AmberButton(
                key: const Key('crew.seatHire'),
                label: freeSlots == 0
                    ? 'Pilots full'
                    : formatCoins(shelf.pilotPrice),
                mono: true,
                height: 36,
                onPressed:
                    freeSlots > 0 && state.player.money >= shelf.pilotPrice
                    ? () => _actAndClose(
                        context,
                        ref,
                        (sim, s, now) =>
                            sim.hirePilot(s, now, planeId: planeId),
                        'Hired a rookie pilot for $name.',
                      )
                    : null,
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// What to do with someone in a seat: swap them with another crew member,
/// move them to a plane with room, take them off, or open their skills.
class _SeatMemberSheet extends ConsumerWidget {
  const _SeatMemberSheet({required this.memberId, required this.onOpen});

  final String memberId;
  final void Function(String memberId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TickBuilder(
    builder: (context, now) {
      final state = ref.watch(gameSessionProvider);
      final config = ref.watch(gameConfigProvider);
      final sim = ref.read(simulationProvider);
      final desk = sim.crew;
      final m = state.crew.member(memberId);
      final plane = m?.planeId == null ? null : state.plane(m!.planeId!);
      if (m == null || plane == null) return const SizedBox.shrink();
      final name = planeName(config, plane);
      final parked = plane.status == PlaneStatus.parked;
      final isCaptain = desk.effects.aboard(state, plane).captain?.id == m.id;

      final others =
          [
            for (final o in state.crew.members)
              if (o.id != m.id &&
                  o.planeId != m.planeId &&
                  config.crew.role(o.roleId).isFlightCrew &&
                  (m.roleId != 'pilot' ||
                      o.roleId == 'pilot' ||
                      o.planeId == null))
                o,
          ]..sort((a, b) {
            final idle = (a.planeId == null ? 0 : 1).compareTo(
              b.planeId == null ? 0 : 1,
            );
            return idle != 0 ? idle : b.level.compareTo(a.level);
          });
      final moveTo = [
        for (final p in state.planes)
          if (p.id != plane.id &&
              p.status == PlaneStatus.parked &&
              desk.hasSeatFor(state, p, m))
            p,
      ];
      final afterOff = _try(
        () => desk.unassign(state, m.id, state.simulatedTo),
      );
      final offShort = afterOff == null
          ? null
          : _leavesShort(sim, state, afterOff, m);

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Row(
            children: [
              CrewAvatar(name: m.name, veteran: m.isVeteran),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetHeader(
                  title: m.name,
                  subtitle:
                      '${_role(ref, m)} · '
                      '${isCaptain ? 'captain of' : 'flies'} $name',
                ),
              ),
              AmberButton(
                key: const Key('crew.seatSkills'),
                label: 'Skills',
                outlined: true,
                height: 38,
                onPressed: () {
                  Navigator.of(context).pop();
                  onOpen(m.id);
                },
              ),
            ],
          ),
          if (!parked) ...[
            const SizedBox(height: 14),
            Text(
              '$name is in the air. ${_inAir(plane, now)}; '
              'swap or move ${m.name} once it lands.',
              style: const TextStyle(fontSize: 13, color: Board.muted),
            ),
          ] else ...[
            const _Group('Swap with'),
            if (others.isEmpty)
              const Text(
                'Nobody to swap with yet.',
                style: TextStyle(fontSize: 13, color: Board.muted),
              ),
            for (final o in others)
              () {
                final from = o.planeId == null ? null : state.plane(o.planeId!);
                final ok = desk.canSwap(state, m.id, o.id);
                return _PickRow(
                  key: Key('crew.swap.${o.id}'),
                  leading: CrewAvatar(
                    name: o.name,
                    size: 36,
                    veteran: o.isVeteran,
                  ),
                  title: o.name,
                  subtitle:
                      '${_role(ref, o)} · '
                      '${from == null ? 'idle' : planeName(config, from)}',
                  warning: from != null && from.status != PlaneStatus.parked
                      ? _inAir(from, now)
                      : null,
                  action: 'Swap',
                  onTap: ok
                      ? () => _actAndClose(
                          context,
                          ref,
                          (sim, s, now) => sim.swapCrew(s, m.id, o.id, now),
                          from == null
                              ? '${o.name} now flies $name.'
                              : '${m.name} and ${o.name} swapped planes.',
                        )
                      : null,
                );
              }(),
            if (moveTo.isNotEmpty) ...[
              const _Group('Move to'),
              for (final p in moveTo)
                _PickRow(
                  key: Key('crew.moveTo.${p.id}'),
                  leading: Icon(
                    Icons.flight,
                    color: sim.rules.crew.departureProblem(state, p) != null
                        ? Board.bad
                        : Board.amber,
                  ),
                  title: planeName(config, p),
                  subtitle:
                      '${config.world.city(p.cityId).name} · '
                      '${sim.rules.crew.departureProblem(state, p) != null ? 'needs a pilot' : 'has a free seat'}',
                  warning: offShort != null
                      ? '$name would be short a pilot'
                      : null,
                  action: 'Move',
                  onTap: () => _actAndClose(
                    context,
                    ref,
                    (sim, s, now) => sim.assignCrewToPlane(s, m.id, p.id, now),
                    '${m.name} now flies ${planeName(config, p)}.',
                  ),
                ),
            ],
            const SizedBox(height: 14),
            OutlinedButton(
              key: const Key('crew.seatOff'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Board.ink,
                side: const BorderSide(color: Color(0xFF3B4A5E), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: afterOff == null
                  ? null
                  : () => _actAndClose(
                      context,
                      ref,
                      (sim, s, now) => sim.unassignCrew(s, m.id, now),
                      '${m.name} is off $name.',
                    ),
              child: Text(
                offShort != null
                    ? 'Take off this plane (it will be short a pilot)'
                    : 'Take off this plane',
              ),
            ),
          ],
        ],
      );
    },
  );
}
