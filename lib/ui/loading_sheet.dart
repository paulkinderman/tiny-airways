import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'growth_sheets.dart' show PlaneUpgradeRows;
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

  /// Whether the upgrade tray is open.
  bool _tray = false;

  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Opens the upgrade tray at the top of the list.
  void _openTray() {
    setState(() => _tray = true);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  GameSession get _session => ref.read(gameSessionProvider.notifier);

  void _report(RuleError? error) {
    if (error != null && mounted) {
      showToast(context, ruleErrorText(error), kind: ToastKind.error);
    }
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
    final jobsConfig = config.jobs;
    final canUpgrade = stats.model.price != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Load ${planeName(config, plane)}',
          subtitle:
              '${stats.model.name} · at ${city.name} · range '
              '${formatKm(stats.rangeFrom(sim.rules, airport))}',
          onBack: () => ui.open(AirportPanel(city.id, planeId: plane.id)),
          trailing: canUpgrade
              ? _UpgradeToggle(
                  open: _tray,
                  onTap: () =>
                      _tray ? setState(() => _tray = false) : _openTray(),
                )
              : PlaneArt(plane.modelId, height: 34),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                  bonus: _BonusPill(
                    key: const Key('load.bonusPill.seats'),
                    pct: jobsConfig.charterBonusPct,
                    label: 'charter',
                    earned: load.isCharter,
                  ),
                ),
              if (load.cargoSlots > 0) ...[
                const SizedBox(height: 6),
                _SlotRow(
                  label: 'Cargo ${load.cargoSlotsUsed}/${load.cargoSlots}',
                  used: load.cargoSlotsUsed,
                  total: load.cargoSlots,
                  color: Board.cargo,
                  bonus: _BonusPill(
                    key: const Key('load.bonusPill.cargo'),
                    pct: jobsConfig.fullHoldBonusPct,
                    label: 'full hold',
                    earned: load.isFullHold,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const Key('load.list'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (_tray && canUpgrade) ...[
                _UpgradeTray(
                  title: 'Upgrade ${planeName(config, plane)}',
                  money: state.player.money,
                  onClose: () => setState(() => _tray = false),
                  child: PlaneUpgradeRows(
                    key: const Key('load.tray'),
                    planeId: plane.id,
                    keyPrefix: 'load.tray',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SingleChildScrollView(
                key: const Key('load.filters'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    BoardChip(
                      key: const Key('load.filter.all'),
                      label: 'All ${board.length}',
                      selected: _filter == null,
                      dense: true,
                      onTap: () => setState(() => _filter = null),
                    ),
                    for (final d in destinations) ...[
                      const SizedBox(width: 6),
                      BoardChip(
                        key: Key('load.filter.$d'),
                        label: '${config.world.city(d).name} ${counts[d]}',
                        selected: _filter == d,
                        dense: true,
                        onTap: () => setState(() => _filter = d),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TickBuilder(
                      builder: (context, now) => Text(
                        'Free new jobs in '
                        '${formatMinSec(sim.boards.nextRotationAt(state).difference(now))}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Board.muted,
                        ),
                      ),
                    ),
                  ),
                  BoardChip(
                    key: const Key('load.refresh'),
                    icon: Icons.refresh,
                    label: 'Now · ${formatCoins(refreshCost)}',
                    selected: false,
                    dashed: true,
                    dense: true,
                    onTap: () => _report(
                      _session.act(
                        (sim, s, now) => sim.refreshBoard(s, city.id, now),
                      ),
                    ),
                  ),
                ],
              ),
              if (firstLookNote(sim, state, airport, now) case final note?)
                Padding(
                  key: const Key('load.firstLook'),
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    note,
                    style: const TextStyle(fontSize: 12, color: Board.muted),
                  ),
                ),
              if (plane.load.isNotEmpty) ...[
                _ListLabel(
                  'On board · ${plane.load.length}',
                  trailing: TextButton.icon(
                    key: const Key('load.unloadAll'),
                    icon: const Icon(Icons.connecting_airports, size: 16),
                    label: Text(
                      plane.load.any((j) => j.originCityId != city.id)
                          ? 'Unload all (layover)'
                          : 'Unload all',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Board.signature,
                      textStyle: const TextStyle(
                        fontFamily: Board.sans,
                        fontSize: 13,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () => _report(
                      _session.act(
                        (sim, s, now) => sim.unloadAll(s, plane.id, now),
                      ),
                    ),
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
              ],
              _ListLabel(
                _filter == null
                    ? 'Waiting here · ${shown.length}'
                    : 'To ${config.world.city(_filter!).name} · ${shown.length}',
                trailing: _filter == null
                    ? null
                    : TextButton(
                        key: const Key('load.fillTo'),
                        style: TextButton.styleFrom(
                          foregroundColor: Board.amber,
                          textStyle: const TextStyle(
                            fontFamily: Board.sans,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: () => _fillTo(_filter!),
                        child: Text(
                          'Fill to ${config.world.city(_filter!).name}',
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
                  leavesSoon: sim.boards.leavesSoon(state, j, now),
                  onTap: () => _add(j),
                  onLongPress: () => _connect(sim, state, plane, j),
                  removeCityId: j.isConnecting ? city.id : null,
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
              const SizedBox(height: 14),
              Center(
                child: TextButton.icon(
                  key: const Key('load.store'),
                  icon: const Icon(Icons.warehouse_outlined, size: 16),
                  label: Text(
                    plane.load.isEmpty
                        ? 'Park in hangar (frees the gate)'
                        : 'Unload and park in hangar (frees the gate)',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Board.muted,
                    textStyle: const TextStyle(
                      fontFamily: Board.sans,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () {
                    final error = _session.act(
                      (sim, s, now) => sim.storePlane(s, plane.id, now),
                    );
                    _report(error);
                    if (error == null) {
                      ui.open(AirportPanel(city.id));
                      showToast(
                        context,
                        '${planeName(config, plane)} is in the hangar at '
                        '${city.name}.',
                        kind: ToastKind.done,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Board.panel,
            border: Border(top: BorderSide(color: Board.line)),
          ),
          child: Column(
            children: [
              _BonusCard(
                sim: sim,
                load: load,
                aboard: plane.load,
                plan: sim.loading.bestFill(state, plane.id, now),
                onFill: _fillTo,
              ),
              const SizedBox(height: 10),
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
                    height: 48,
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

  /// Tapping a job always just boards it. A layover is only ever chosen on
  /// purpose, by holding the job.
  void _add(Job job) => _load(job);

  /// Loads [job], first offering to buy the seat or slot it needs when the
  /// plane is full.
  Future<bool> _load(Job job, {String? dropAtCityId}) async {
    final sim = ref.read(simulationProvider);
    final state = ref.read(gameSessionProvider);
    final plane = state.plane(widget.planeId);
    if (plane == null) return false;
    final now = ref.read(clockProvider).now();
    final track = sim.growth.roomUpgradeFor(state, plane, job, now);
    if (track == null) {
      final error = _session.act(
        (sim, s, now) =>
            sim.loadJob(s, plane.id, job.id, now, dropAtCityId: dropAtCityId),
      );
      _report(error);
      return error == null;
    }
    final buy = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Board.panel,
      builder: (context) =>
          _RoomUpgradePrompt(planeId: plane.id, job: job, track: track),
    );
    if (buy != true || !mounted) return false;
    final error = _session.act(
      (sim, s, now) => sim.upgradeAndLoad(
        s,
        plane.id,
        job.id,
        now,
        dropAtCityId: dropAtCityId,
      ),
    );
    _report(error);
    return error == null;
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
        kind: ToastKind.error,
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
    await _load(job, dropAtCityId: drop);
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.label,
    required this.used,
    required this.total,
    required this.color,
    this.bonus,
  });

  /// The row's load bonus, on the right.
  final Widget? bonus;

  final String label;
  final int used;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 74,
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
                width: 28,
                height: 18,
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
      if (bonus != null) ...[const SizedBox(width: 6), bonus!],
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
    this.removeCityId,
    this.bonusPct,
    this.leavesSoon = false,
    super.key,
  });

  final Simulation sim;

  /// The job leaves the board at the next rotation.
  final bool leavesSoon;
  final String fromCityId;
  final Job job;
  final bool added;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Where this layover job waits, to show its remove button; null for
  /// jobs that can't be removed.
  final String? removeCityId;

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
      if (job.slots > 1 && job.type == JobType.passenger)
        'group of ${job.slots}'
      else if (job.slots > 1)
        '${job.kind.name}, ${job.slots} slots',
      if (job.kind == JobKind.vip) 'VIP',
      if (job.kind == JobKind.fragile) 'fragile',
      if (job.kind == JobKind.rush) 'rush: next plane out',
      if (leavesSoon) 'leaves soon',
    ];
    final card = Material(
      color: added ? Board.raised : Board.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: added ? Board.amber : Board.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            children: [
              Icon(
                job.type == JobType.passenger
                    ? Icons.person_outline
                    : Icons.inventory_2_outlined,
                color: job.type == JobType.passenger
                    ? Board.amber
                    : Board.cargo,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jobDestination(world, job),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Board.ink,
                      ),
                    ),
                    Text(
                      notes.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Board.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (removeCityId != null) ...[
                RemoveLayoverButton(cityId: removeCityId!, job: job),
                const SizedBox(width: 4),
              ],
              _PayButton(
                key: Key('load.pay.${job.id}'),
                label: jobPayLabel(job),
                added: added,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
    final pct = bonusPct;
    final layover = job.isConnecting;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

/// The best match for a charter: the destination whose fill earns the
/// plane the most (counting the charter and full-hold bonus), how full it
/// would leave the plane and what it adds, and a one-tap fill toward it.
/// The bonus percentages themselves sit by the slots at the top.
class _BonusCard extends StatelessWidget {
  const _BonusCard({
    required this.sim,
    required this.load,
    required this.aboard,
    required this.plan,
    required this.onFill,
  });

  final Simulation sim;
  final LoadSummary load;
  final List<Job> aboard;
  final FillPlan? plan;
  final void Function(String cityId) onFill;

  @override
  Widget build(BuildContext context) {
    final world = sim.rules.world;
    final done =
        (load.seats == 0 || load.isCharter) &&
        (load.cargoSlots == 0 || load.isFullHold);
    final plan = done ? null : this.plan;
    final target = done
        ? (load.charterCityId ?? load.holdCityId)
        : plan?.cityId;
    int to(JobType type) => [...aboard, ...?plan?.jobs]
        .where((j) => j.type == type && j.unloadCityId == target)
        .fold(0, (sum, j) => sum + j.slots);
    final String line;
    if (target == null) {
      line = load.seatsUsed + load.cargoSlotsUsed > 0
          ? 'Nothing waiting here fits'
          : 'Fill every seat and slot for one city';
    } else {
      final parts = [
        if (load.seats > 0)
          '${to(JobType.passenger)}/${load.seats} '
              '${load.seats == 1 ? 'seat' : 'seats'}',
        if (load.cargoSlots > 0)
          '${to(JobType.cargo)}/${load.cargoSlots} '
              '${load.cargoSlots == 1 ? 'slot' : 'slots'}',
      ];
      line = '${world.city(target).name} · ${parts.join(' · ')}';
    }
    final full =
        plan != null &&
        (load.seats == 0 || plan.charter) &&
        (load.cargoSlots == 0 || plan.fullHold);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: Board.flap,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Board.amber.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  done
                      ? 'CHARTER SET'
                      : plan != null && plan.gain > 0
                      ? 'BEST MATCH · +${formatCoins(plan.gain)}'
                      : 'BEST MATCH',
                  key: const Key('load.bestMatchHeader'),
                  style: Board.flapStyle(size: 11),
                ),
                Text(
                  line,
                  key: const Key('load.bestMatch'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Board.ink),
                ),
              ],
            ),
          ),
          if (plan != null) ...[
            const SizedBox(width: 8),
            AmberButton(
              key: const Key('load.makeCharter'),
              label: full ? 'Make charter' : 'Best fill',
              mono: true,
              height: 34,
              onPressed: () => onFill(plan.cityId),
            ),
          ],
        ],
      ),
    );
  }
}

/// A slot row's load bonus in orange: "+25% charter", outlined like the
/// Add buttons, filled with a tick once the load as it stands earns it.
class _BonusPill extends StatelessWidget {
  const _BonusPill({
    required this.pct,
    required this.label,
    required this.earned,
    super.key,
  });

  final double pct;
  final String label;
  final bool earned;

  @override
  Widget build(BuildContext context) => Container(
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 7),
    decoration: BoxDecoration(
      color: earned ? Board.cargo : null,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Board.cargo, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (earned) ...[
          const Icon(Icons.check, size: 12, color: Board.ground),
          const SizedBox(width: 2),
        ],
        Text(
          // Narrow phones get just the percentage.
          MediaQuery.sizeOf(context).width < 360
              ? '+${pct.round()}%'
              : '+${pct.round()}% $label',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: earned ? Board.ground : Board.cargo,
          ),
        ),
      ],
    ),
  );
}

/// The header's Upgrade button, which opens and closes the upgrade tray.
class _UpgradeToggle extends StatelessWidget {
  const _UpgradeToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: open ? Board.amber : Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Board.amber, width: 1.5),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: const Key('load.upgrade'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_upward_rounded,
              size: 15,
              color: open ? Board.amberInk : Board.amber,
            ),
            const SizedBox(width: 3),
            Text(
              'Upgrade',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: open ? Board.amberInk : Board.amber,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The upgrade tray at the top of the loading sheet: every track of the
/// plane, bought in place without leaving the sheet.
class _UpgradeTray extends StatelessWidget {
  const _UpgradeTray({
    required this.title,
    required this.money,
    required this.onClose,
    required this.child,
  });

  final String title;
  final int money;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Board.flap,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Board.amber.withValues(alpha: 0.7)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Board.flapStyle(size: 12),
                ),
              ),
              Text(
                'You have ${formatCoins(money)}',
                style: const TextStyle(fontSize: 12, color: Board.muted),
              ),
              IconButton(
                key: const Key('load.tray.close'),
                tooltip: 'Close upgrades',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.expand_less, color: Board.muted),
              ),
            ],
          ),
        ),
        child,
      ],
    ),
  );
}

/// Offered when a job won't fit: buy the seat or slot it needs and load it
/// in one go. Pops true to buy.
class _RoomUpgradePrompt extends ConsumerWidget {
  const _RoomUpgradePrompt({
    required this.planeId,
    required this.job,
    required this.track,
  });

  final String planeId;
  final Job job;
  final PlaneTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final plane = state.plane(planeId);
    if (plane == null) return const SizedBox.shrink();
    final growth = sim.growth;
    final cost = growth.planeUpgradeCost(plane, track) ?? 0;
    final level = growth.trackLevel(plane, track);
    final maxLevel = config.planes.upgrades.maxLevel;
    final per = config.planes.upgrades.capacityPerLevel;
    final load = sim.loading.summary(
      state,
      plane,
      ref.read(clockProvider).now(),
    );
    final seats = job.type == JobType.passenger;
    final unit = seats ? 'seat' : 'slot';
    final units = seats ? 'Seats' : 'Cargo slots';
    final have = seats ? load.seats : load.cargoSlots;
    final affordable = state.player.money >= cost;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              seats ? 'SEATS ARE FULL' : 'THE HOLD IS FULL',
              style: Board.flapStyle(size: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Add ${per == 1 ? 'a $unit' : '$per ${unit}s'} to '
              '${planeName(config, plane)} for ${formatCoins(cost)} and load '
              '${jobDestination(config.world, job)} (${jobPayLabel(job)})? '
              '$units go from $have to ${have + per}, level ${level + 1} '
              'of $maxLevel.',
              style: const TextStyle(fontSize: 14, color: Board.ink),
            ),
            if (!affordable) ...[
              const SizedBox(height: 6),
              Text(
                'You have ${formatCoins(state.player.money)}.',
                style: const TextStyle(fontSize: 13, color: Board.bad),
              ),
            ],
            const SizedBox(height: 14),
            AmberButton(
              key: const Key('load.upgradeAndLoad'),
              label: affordable
                  ? 'Add $unit & load · ${formatCoins(cost)}'
                  : 'Need ${formatCoins(cost)}',
              height: 52,
              onPressed: affordable
                  ? () => Navigator.of(context).pop(true)
                  : null,
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('load.upgradeAndLoad.cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: Board.muted),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A job's button with its pay inside, styled like the upgrade buttons:
/// "BOARD 403" to put it aboard, a filled "DE-PLANE 403" once it is aboard
/// to take it off again.
class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.label,
    required this.added,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = added ? Board.amberInk : Board.amber;
    return Semantics(
      button: true,
      label: added ? 'De-plane, pays $label' : 'Board, pays $label',
      child: Material(
        color: added ? Board.amber : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Board.amber, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // At least 132 wide so most amounts line up; big payouts widen it.
          child: IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 132, minHeight: 34),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Mono capitals like the upgrade buttons, with the pay
                    // right-aligned so amounts line up down the list.
                    Text(
                      added ? 'DE-PLANE' : 'BOARD',
                      style: Board.flapStyle(size: 13, color: fg),
                    ),
                    const SizedBox(width: 10),
                    Text(label, style: Board.flapStyle(size: 13, color: fg)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small heading over a group of jobs ("ON BOARD · 3"), with an
/// optional action on the right.
class _ListLabel extends StatelessWidget {
  const _ListLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: SizedBox(
      height: 30,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Board.flapStyle(size: 11, color: Board.muted),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}
