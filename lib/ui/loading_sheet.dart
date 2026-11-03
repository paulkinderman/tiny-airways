import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'map_scene_builder.dart';
import 'plane_art.dart';
import 'rivals_screens.dart';
import 'route_picker.dart' show maxRouteStops;
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// The loading sheet: a parked plane's seats and slots, the airport's board
/// filtered by destination, charter progress and the way to the route
/// picker.
class LoadingSheet extends ConsumerStatefulWidget {
  const LoadingSheet({required this.planeId, super.key});

  final String planeId;

  @override
  ConsumerState<LoadingSheet> createState() => _LoadingSheetState();
}

class _LoadingSheetState extends ConsumerState<LoadingSheet> {
  /// Destination filter; null shows every job.
  String? _filter;

  GameSession get _session => ref.read(gameSessionProvider.notifier);

  void _report(RuleError? error) {
    if (error != null && mounted) showToast(context, ruleErrorText(error));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final ui = ref.read(uiProvider.notifier);
    final plane = state.plane(widget.planeId);
    if (plane == null || plane.status != PlaneStatus.parked) {
      return const SizedBox.shrink();
    }
    final now = ref.read(clockProvider).now();
    final airport = state.airport(plane.cityId)!;
    final city = config.world.city(plane.cityId);
    final stats = PlaneStats.of(sim.rules, state, plane);
    final load = sim.loading.summary(state, plane, now);

    final board = visibleBoard(sim, state, airport, now)
      ..sort((a, b) => b.payout.compareTo(a.payout));
    final counts = <String, int>{};
    for (final j in board) {
      counts[j.destCityId] = (counts[j.destCityId] ?? 0) + 1;
    }
    final destinations = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    if (_filter != null && !counts.containsKey(_filter)) _filter = null;
    final shown = [
      for (final j in board)
        if (_filter == null || j.destCityId == _filter) j,
    ];
    final onBoardPay = plane.load.fold(0, (sum, j) => sum + j.payout);
    final capacity = load.seats + load.cargoSlots;
    final used = load.seatsUsed + load.cargoSlotsUsed;
    final refreshCost = sim.boards.refreshCost(city.id, state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Load ${planeName(config, plane)}',
          subtitle:
              '${stats.model.name} · at ${city.name} · range '
              '${formatKm(stats.rangeFrom(sim.rules, airport))}',
          onBack: () => ui.open(AirportPanel(city.id, planeId: plane.id)),
          trailing: PlaneArt(plane.modelId, height: 40),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Board.line)),
          ),
          child: Column(
            children: [
              if (load.seats > 0 || load.seatsUsed > 0)
                _SlotRow(
                  label: 'Seats ${load.seatsUsed}/${load.seats}',
                  used: load.seatsUsed,
                  total: load.seats,
                  color: Board.amber,
                ),
              if (load.cargoSlots > 0) ...[
                const SizedBox(height: 8),
                _SlotRow(
                  label: 'Cargo ${load.cargoSlotsUsed}/${load.cargoSlots}',
                  used: load.cargoSlotsUsed,
                  total: load.cargoSlots,
                  color: Board.cargo,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  BoardChip(
                    key: const Key('load.filter.all'),
                    label: 'All ${board.length}',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final d in destinations)
                    BoardChip(
                      key: Key('load.filter.$d'),
                      label: '${config.world.city(d).name} ${counts[d]}',
                      selected: _filter == d,
                      onTap: () => setState(() => _filter = d),
                    ),
                  BoardChip(
                    key: const Key('load.refresh'),
                    icon: Icons.refresh,
                    label: 'New jobs · ${formatCoins(refreshCost)}',
                    selected: false,
                    dashed: true,
                    onTap: () => _report(
                      _session.act(
                        (sim, s, now) => sim.refreshBoard(s, city.id, now),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TickBuilder(
                builder: (context, now) => Text(
                  'Free rotation in '
                  '${formatMinSec(sim.boards.nextRotationAt(state).difference(now))}.'
                  '${plane.load.isEmpty ? '' : ' Your ${plane.load.length} added jobs stay.'}',
                  style: const TextStyle(fontSize: 13, color: Board.muted),
                ),
              ),
              const SizedBox(height: 10),
              if (_filter != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AmberButton(
                    key: const Key('load.fillTo'),
                    label: 'Fill to ${config.world.city(_filter!).name}',
                    outlined: true,
                    onPressed: () => _fillTo(_filter!),
                  ),
                ),
              for (final j in plane.load)
                _JobRow(
                  key: Key('load.aboard.${j.id}'),
                  sim: sim,
                  fromCityId: city.id,
                  job: j,
                  added: true,
                  bonusPct: _loadBonusPct(sim, load, j),
                  onTap: () => _report(
                    _session.act(
                      (sim, s, now) => sim.unloadJob(s, plane.id, j.id, now),
                    ),
                  ),
                ),
              if (plane.load.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('load.unloadAll'),
                    icon: const Icon(Icons.connecting_airports, size: 18),
                    label: Text(
                      plane.load.any((j) => j.originCityId != city.id)
                          ? 'Unload all here (layover)'
                          : 'Unload all',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Board.signature,
                    ),
                    onPressed: () => _report(
                      _session.act(
                        (sim, s, now) => sim.unloadAll(s, plane.id, now),
                      ),
                    ),
                  ),
                ),
              for (final j in shown)
                _JobRow(
                  key: Key('load.job.${j.id}'),
                  sim: sim,
                  fromCityId: city.id,
                  job: j,
                  added: false,
                  onTap: () => _add(sim, state, plane, j),
                  onLongPress: () => _connect(sim, state, plane, j),
                ),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No jobs waiting here. Pay for new jobs or wait for the '
                    'next rotation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Board.muted),
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Board.panel,
            border: Border(top: BorderSide(color: Board.line)),
          ),
          child: Column(
            children: [
              _BonusCard(sim: sim, load: load, onFill: _fillTo, board: board),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$used of $capacity loaded',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Board.muted,
                          ),
                        ),
                        Text(
                          '${formatCoins(onBoardPay)} on board',
                          key: const Key('load.onBoard'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Board.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AmberButton(
                    key: const Key('load.chooseRoute'),
                    label: 'Choose route',
                    height: 52,
                    onPressed: () => ui.open(
                      RoutePanel(
                        plane.id,
                        stops: _suggestedStops(sim, state, plane, now),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The charter (passengers) or full-hold (cargo) bonus [job] will earn
  /// if the plane leaves loaded as it is now, or null.
  static double? _loadBonusPct(Simulation sim, LoadSummary load, Job job) {
    final jobs = sim.rules.config.jobs;
    if (job.type == JobType.passenger) {
      return load.isCharter ? jobs.charterBonusPct : null;
    }
    return load.isFullHold ? jobs.fullHoldBonusPct : null;
  }

  void _fillTo(String cityId) => _report(
    _session.act((sim, s, now) => sim.fillTo(s, widget.planeId, cityId, now)),
  );

  /// Starts the route through every airport where something aboard gets
  /// off, nearest first, if the plane can fly that way; else an empty
  /// route.
  List<String> _suggestedStops(
    Simulation sim,
    GameState state,
    Plane plane,
    DateTime now,
  ) {
    final left = {for (final j in plane.load) j.unloadCityId}
      ..remove(plane.cityId);
    if (left.isEmpty || left.length > maxRouteStops) return const [];
    final stops = <String>[];
    while (left.isNotEmpty) {
      final options = nextStopOptions(sim, state, plane, stops, now);
      final from = stops.isEmpty ? plane.cityId : stops.last;
      final next =
          (left.where(options.contains).toList()..sort(
                (a, b) => sim.rules
                    .distanceKm(from, a)
                    .compareTo(sim.rules.distanceKm(from, b)),
              ))
              .firstOrNull;
      if (next == null) return const [];
      stops.add(next);
      left.remove(next);
    }
    return stops;
  }

  void _add(Simulation sim, GameState state, Plane plane, Job job) {
    final now = ref.read(clockProvider).now();
    final direct = sim.flights.legProblem(
      state,
      plane,
      plane.cityId,
      job.destCityId,
      now,
    );
    if (direct == RuleError.outOfRange) {
      _connect(sim, state, plane, job);
      return;
    }
    _report(
      _session.act((sim, s, now) => sim.loadJob(s, plane.id, job.id, now)),
    );
  }

  /// Asks where to drop [job] so it can connect onward.
  Future<void> _connect(
    Simulation sim,
    GameState state,
    Plane plane,
    Job job,
  ) async {
    final now = ref.read(clockProvider).now();
    final world = sim.rules.world;
    final options = nextStopOptions(sim, state, plane, const [], now).toList()
      ..remove(job.destCityId)
      ..sort(
        (a, b) => sim.rules
            .distanceKm(a, job.destCityId)
            .compareTo(sim.rules.distanceKm(b, job.destCityId)),
      );
    if (options.isEmpty) {
      showToast(
        context,
        '${world.city(job.destCityId).name} is out of range, and there is '
        'nowhere in range to connect through.',
      );
      return;
    }
    final drop = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Board.panel,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'LAYOVER ON THE WAY TO ${world.city(job.destCityId).name}',
                style: Board.flapStyle(size: 15),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Drop it at one of your airports. It waits in that airport\'s '
                'jobs for another plane, and pays its full fare when it '
                'reaches its city.',
                style: TextStyle(color: Board.muted),
              ),
            ),
            for (final id in options)
              Builder(
                builder: (context) {
                  final free = sim.loading.freeLayoverSlots(state, id);
                  final fits = free >= job.slots;
                  return ListTile(
                    key: Key('load.connect.$id'),
                    enabled: fits,
                    leading: Icon(
                      Icons.connecting_airports,
                      color: fits ? Board.signature : Board.muted,
                    ),
                    title: Text('Layover at ${world.city(id).name}'),
                    subtitle: Text(
                      '${formatKm(sim.rules.distanceKm(id, job.destCityId))} '
                      'from ${world.city(job.destCityId).name} · '
                      '${fits ? '$free layover slots free' : 'layovers full'}',
                      style: const TextStyle(color: Board.muted),
                    ),
                    onTap: () => Navigator.of(context).pop(id),
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (drop == null) return;
    _report(
      _session.act(
        (sim, s, now) =>
            sim.loadJob(s, plane.id, job.id, now, dropAtCityId: drop),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.label,
    required this.used,
    required this.total,
    required this.color,
  });

  final String label;
  final int used;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 82,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Board.muted),
        ),
      ),
      Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < total || i < used; i++)
              Container(
                width: 32,
                height: 22,
                decoration: BoxDecoration(
                  color: i < used ? color : null,
                  borderRadius: BorderRadius.circular(6),
                  border: i < used
                      ? null
                      : Border.all(color: Board.muted.withValues(alpha: 0.5)),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.sim,
    required this.fromCityId,
    required this.job,
    required this.added,
    required this.onTap,
    this.onLongPress,
    this.bonusPct,
    super.key,
  });

  final Simulation sim;
  final String fromCityId;
  final Job job;
  final bool added;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// A charter or full-hold bonus, shown as a badge in the top right.
  final double? bonusPct;

  @override
  Widget build(BuildContext context) {
    final world = sim.rules.world;
    final notes = [
      if (job.kind == JobKind.sightseeing)
        'round trip, Barnstormer only'
      else
        formatKm(sim.rules.distanceKm(fromCityId, job.destCityId)),
      if (job.kind == JobKind.partCrate) 'part crate: a plane part',
      if (job.dropAtCityId != null)
        'layover at ${world.city(job.dropAtCityId!).name}'
      else if (added)
        'direct',
      if (job.slots > 1) '${job.kind.name}, ${job.slots} slots',
      if (job.kind == JobKind.vip) 'VIP',
      if (job.kind == JobKind.fragile) 'fragile',
      if (job.kind == JobKind.rush) 'rush: next plane out',
    ];
    final card = Material(
      color: Board.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: added ? Board.amber : Board.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              Icon(
                job.type == JobType.passenger
                    ? Icons.person_outline
                    : Icons.inventory_2_outlined,
                color: job.type == JobType.passenger
                    ? Board.amber
                    : Board.cargo,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jobDestination(world, job),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Board.ink,
                      ),
                    ),
                    Text(
                      notes.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Board.muted),
                    ),
                  ],
                ),
              ),
              Text(
                jobPayLabel(job),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Board.ink,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 84,
                child: AmberButton(
                  label: added ? 'Added' : 'Add',
                  outlined: !added,
                  height: 40,
                  onPressed: onTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final pct = bonusPct;
    final layover = job.isConnecting;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: pct == null && !layover
          ? card
          : Stack(
              clipBehavior: Clip.none,
              children: [
                card,
                if (layover)
                  Positioned(
                    top: -7,
                    left: 12,
                    child: IgnorePointer(
                      child: LayoverBadge(key: Key('load.layover.${job.id}')),
                    ),
                  ),
                if (pct != null)
                  Positioned(
                    top: -7,
                    right: 12,
                    child: IgnorePointer(
                      child: Container(
                        key: Key('load.bonus.${job.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: const BoxDecoration(
                          color: Board.good,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Text(
                          '+${pct.round()}%',
                          style: Board.flapStyle(size: 11, color: Board.ground),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Charter and full-hold progress, with a one-tap fill toward the best
/// destination.
class _BonusCard extends StatelessWidget {
  const _BonusCard({
    required this.sim,
    required this.load,
    required this.board,
    required this.onFill,
  });

  final Simulation sim;
  final LoadSummary load;
  final List<Job> board;
  final void Function(String cityId) onFill;

  @override
  Widget build(BuildContext context) {
    final world = sim.rules.world;
    final jobs = sim.rules.config.jobs;
    final lines = <String>[];
    if (load.seats > 0) {
      lines.add(
        load.isCharter
            ? 'Charter! Every passenger pays +${jobs.charterBonusPct.round()}%'
            : load.charterCityId == null
            ? 'Fill all ${load.seats} seats for one city: '
                  '+${jobs.charterBonusPct.round()}%'
            : 'Best match: ${load.charterCount} of ${load.seats} seats to '
                  '${world.city(load.charterCityId!).name}',
      );
    }
    if (load.cargoSlots > 0) {
      lines.add(
        load.isFullHold
            ? 'Full hold! Every crate pays +${jobs.fullHoldBonusPct.round()}%'
            : load.holdCityId == null
            ? load.cargoSlots == 1
                  ? 'Fill the cargo slot for one city: '
                        '+${jobs.fullHoldBonusPct.round()}%'
                  : 'Fill all ${load.cargoSlots} slots for one city: '
                        '+${jobs.fullHoldBonusPct.round()}%'
            : 'Hold: ${load.holdCount} of ${load.cargoSlots} slots to '
                  '${world.city(load.holdCityId!).name}',
      );
    }
    // Fill toward the city already winning, or the busiest destination.
    String? target = load.charterCityId ?? load.holdCityId;
    if (target == null && board.isNotEmpty) {
      final counts = <String, int>{};
      for (final j in board) {
        counts[j.destCityId] = (counts[j.destCityId] ?? 0) + j.slots;
      }
      target = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    }
    final done =
        (load.seats == 0 || load.isCharter) &&
        (load.cargoSlots == 0 || load.isFullHold);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Board.flap,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Board.amber.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHARTER BONUS +${jobs.charterBonusPct.round()}%',
                  style: Board.flapStyle(size: 12),
                ),
                const SizedBox(height: 3),
                for (final l in lines)
                  Text(
                    l,
                    style: const TextStyle(fontSize: 13, color: Board.ink),
                  ),
              ],
            ),
          ),
          if (!done && target != null) ...[
            const SizedBox(width: 8),
            AmberButton(
              key: const Key('load.makeCharter'),
              label: 'Make charter',
              height: 40,
              onPressed: () => onFill(target!),
            ),
          ],
        ],
      ),
    );
  }
}
