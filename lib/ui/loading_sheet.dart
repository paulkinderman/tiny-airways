import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'fleet_board.dart' show confirmParkPlane;
import 'format.dart';
import 'growth_sheets.dart' show PlaneUpgradeRows;
import 'load_view.dart';
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
  /// The job list's filters. They stay through board refreshes and reset
  /// when the sheet closes.
  LoadFilter _filter = const LoadFilter();

  /// How the city picker sorts its cities.
  CitySort _sort = CitySort.seats;

  /// On-board cities opened to show their jobs (when the load is folded).
  final _openAboard = <String>{};

  /// Waiting-job cities opened past their first few rows.
  final _openWaiting = <String>{};

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

  /// More on-board jobs than this fold into one line per city.
  static const _foldAboardOver = 4;

  /// Rows a waiting city shows before "+ N more" (the first city shows
  /// all of its jobs).
  static const _groupPreview = 4;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final filter = _filter;
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final world = config.world;
    final ui = ref.read(uiProvider.notifier);
    final plane = state.plane(widget.planeId);
    if (plane == null || plane.status != PlaneStatus.parked) {
      return const SizedBox.shrink();
    }
    final now = ref.read(clockProvider).now();
    final airport = state.airport(plane.cityId)!;
    final city = world.city(plane.cityId);
    final stats = PlaneStats.of(sim.rules, state, plane);
    final load = sim.loading.summary(state, plane, now);
    final view = LoadView.of(sim, state, plane, now);

    bool typeShown(Job j) =>
        !(filter.seatsOnly && j.type != JobType.passenger) &&
        !(filter.cargoOnly && j.type != JobType.cargo);
    bool shown(Job j) =>
        typeShown(j) && !(filter.fitsOnly && view.tooBig.contains(j.id));
    final groups = [
      for (final g in view.groups)
        if (filter.cityId == null || g.cityId == filter.cityId)
          (
            g,
            [
              for (final j in g.jobs)
                if (shown(j)) j,
            ],
          ),
    ].where((e) => e.$2.isNotEmpty).toList();
    final shownCount = groups.fold(0, (sum, e) => sum + e.$2.length);
    final cantTake = filter.fitsOnly || filter.cityId != null
        ? const <Job>[]
        : [
            for (final j in view.cantTake)
              if (typeShown(j)) j,
          ];
    final onBoardPay = plane.load.fold(0, (sum, j) => sum + j.payout);
    final capacity = load.seats + load.cargoSlots;
    final used = load.seatsUsed + load.cargoSlotsUsed;
    final refreshCost = sim.boards.refreshCost(city.id, state);
    final jobsConfig = config.jobs;
    final canUpgrade = stats.model.price != null;
    final filterCity = filter.cityId;
    void setFilter(LoadFilter Function(LoadFilter) change) =>
        setState(() => _filter = change(_filter));

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
                  key: const Key('load.slots.seats'),
                  label: 'Seats ${load.seatsUsed}/${load.seats}',
                  used: load.seatsUsed,
                  primary: load.charterCount,
                  total: load.seats,
                  color: Board.amber,
                  caption: _slotCaption(
                    world,
                    load.charterCityId,
                    load.charterCount,
                    load.seatsUsed,
                    load.freeSeats,
                    'seat',
                  ),
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
                  key: const Key('load.slots.cargo'),
                  label: 'Cargo ${load.cargoSlotsUsed}/${load.cargoSlots}',
                  used: load.cargoSlotsUsed,
                  primary: load.holdCount,
                  total: load.cargoSlots,
                  color: Board.cargo,
                  caption: _slotCaption(
                    world,
                    load.holdCityId,
                    load.holdCount,
                    load.cargoSlotsUsed,
                    load.freeCargoSlots,
                    'slot',
                  ),
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
              _FilterRow(
                filter: filter,
                cityLabel: filterCity == null
                    ? 'All cities · ${view.boardCount}'
                    : '${world.city(filterCity).name} · '
                          '${view.group(filterCity)?.jobs.length ?? 0}',
                hasSeats: load.seats > 0,
                hasCargo: load.cargoSlots > 0,
                onCity: () => _pickCity(view, filter),
                onChange: setFilter,
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
                    label: 'Refresh · ${formatCoins(refreshCost)}',
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
                  'On board · ${plane.load.length} '
                  '${plane.load.length == 1 ? 'job' : 'jobs'}',
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
                if (plane.load.length <= _foldAboardOver)
                  for (final j in plane.load) _aboardRow(sim, load, city.id, j)
                else
                  for (final (cityId, jobs) in _byUnloadCity(plane.load)) ...[
                    _AboardCity(
                      key: Key('load.aboardCity.$cityId'),
                      name: world.city(cityId).name,
                      jobs: jobs,
                      bonusPct: _cityBonusPct(sim, load, cityId, jobs),
                      open: _openAboard.contains(cityId),
                      onTap: () => setState(
                        () => _openAboard.contains(cityId)
                            ? _openAboard.remove(cityId)
                            : _openAboard.add(cityId),
                      ),
                    ),
                    if (_openAboard.contains(cityId))
                      for (final j in jobs)
                        Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: _aboardRow(sim, load, city.id, j),
                        ),
                  ],
              ],
              _ListLabel(
                filterCity == null
                    ? 'Waiting here · $shownCount'
                          '${filter.fitsOnly ? ' that fit' : ''}'
                    : 'To ${world.city(filterCity).name} · $shownCount',
                trailing: filterCity == null || shownCount == 0
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
                        onPressed: () => _fillTo(filterCity),
                        child: Text('Fill to ${world.city(filterCity).name}'),
                      ),
              ),
              for (final (i, (group, jobs)) in groups.indexed)
                _CityGroupCard(
                  key: Key('load.group.${group.cityId}'),
                  group: group,
                  name: world.city(group.cityId).name,
                  selected: filterCity == group.cityId,
                  onHeader: () => setFilter(
                    (f) => f.copyWith(
                      cityId: () =>
                          f.cityId == group.cityId ? null : group.cityId,
                    ),
                  ),
                  hidden:
                      i == 0 ||
                          filterCity != null ||
                          _openWaiting.contains(group.cityId)
                      ? 0
                      : (jobs.length - _groupPreview).clamp(0, jobs.length),
                  onMore: () => setState(() => _openWaiting.add(group.cityId)),
                  rows: [
                    for (final j in jobs)
                      _waitingRow(sim, state, plane, city.id, view, j, now),
                  ],
                ),
              if (shownCount == 0)
                Padding(
                  key: const Key('load.empty'),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    filter.isEmpty
                        ? 'No jobs waiting here. Pay for new jobs or wait for '
                              'the next rotation.'
                        : 'Nothing matches your filter right now. It stays on '
                              'as new jobs arrive.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Board.muted),
                  ),
                ),
              if (cantTake.isNotEmpty) ...[
                _ListLabel("Can't go on this plane · ${cantTake.length}"),
                Opacity(
                  opacity: 0.5,
                  child: Column(
                    children: [
                      for (final j in cantTake)
                        _waitingRow(
                          sim,
                          state,
                          plane,
                          city.id,
                          view,
                          j,
                          now,
                          showCity: true,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: BoardChip(
                  key: const Key('load.store'),
                  icon: Icons.warehouse_outlined,
                  label: 'Park in hangar',
                  selected: false,
                  outline: Board.bad,
                  onTap: () => _park(config, plane, city.name, city.id),
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

  /// "6 to Nashville · 4 seats free" under a slot row, or null while it is
  /// empty.
  static String? _slotCaption(
    WorldData world,
    String? cityId,
    int count,
    int used,
    int free,
    String unit,
  ) {
    if (used == 0 || cityId == null) return null;
    final room = free <= 0
        ? 'full'
        : '$free ${free == 1 ? unit : '${unit}s'} free';
    return '$count to ${world.city(cityId).name} · $room';
  }

  /// The jobs aboard by where they get off, biggest share first.
  static List<(String, List<Job>)> _byUnloadCity(List<Job> load) {
    final by = <String, List<Job>>{};
    for (final j in load) {
      (by[j.unloadCityId] ??= []).add(j);
    }
    int size(List<Job> jobs) => jobs.fold(0, (sum, j) => sum + j.slots);
    return [for (final e in by.entries) (e.key, e.value)]
      ..sort((a, b) => size(b.$2).compareTo(size(a.$2)));
  }

  /// The bonus a folded on-board city line shows: the charter or full hold
  /// its jobs earn as the plane is loaded now.
  static double? _cityBonusPct(
    Simulation sim,
    LoadSummary load,
    String cityId,
    List<Job> jobs,
  ) {
    final jobsConfig = sim.rules.config.jobs;
    if (load.isCharter && load.charterCityId == cityId) {
      return jobsConfig.charterBonusPct;
    }
    if (load.isFullHold && load.holdCityId == cityId) {
      return jobsConfig.fullHoldBonusPct;
    }
    return null;
  }

  Widget _aboardRow(Simulation sim, LoadSummary load, String cityId, Job j) =>
      _JobRow(
        key: Key('load.aboard.${j.id}'),
        sim: sim,
        fromCityId: cityId,
        job: j,
        added: true,
        bonusPct: _loadBonusPct(sim, load, j),
        onTap: () => _report(
          _session.act(
            (sim, s, now) => sim.unloadJob(s, widget.planeId, j.id, now),
          ),
        ),
      );

  Widget _waitingRow(
    Simulation sim,
    GameState state,
    Plane plane,
    String cityId,
    LoadView view,
    Job j,
    DateTime now, {
    bool showCity = false,
  }) => _CompactJobRow(
    key: Key('load.job.${j.id}'),
    sim: sim,
    job: j,
    showCity: showCity,
    tooBig: view.tooBig.contains(j.id),
    leavesSoon: sim.boards.leavesSoon(state, j, now),
    onTap: () => _add(j),
    onLongPress: () => _connect(sim, state, plane, j),
    removeCityId: j.isConnecting ? cityId : null,
  );

  /// Opens the city picker and applies the city picked.
  Future<void> _pickCity(LoadView view, LoadFilter filter) async {
    final picked = await showModalBottomSheet<(String?,)>(
      context: context,
      backgroundColor: Board.panel,
      isScrollControlled: true,
      builder: (context) => _CityPicker(
        view: view,
        selected: filter.cityId,
        sort: _sort,
        onSort: (sort) => _sort = sort,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _filter = _filter.copyWith(cityId: () => picked.$1));
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

  /// Puts the plane in the hangar, freeing its gate, and goes back to the
  /// airport.
  Future<void> _park(
    GameConfig config,
    Plane plane,
    String cityName,
    String cityId,
  ) async {
    if (!await confirmParkPlane(context, ref, plane) || !mounted) return;
    final error = _session.act(
      (sim, s, now) => sim.storePlane(s, plane.id, now),
    );
    _report(error);
    if (error == null && mounted) {
      ref.read(uiProvider.notifier).open(AirportPanel(cityId));
      showToast(
        context,
        '${planeName(config, plane)} is in the hangar at $cityName. '
        'Bring it back from Fleet.',
        kind: ToastKind.done,
      );
    }
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

/// A row of seats or cargo slots on one line: those going to the main
/// city bright, the rest of the load dim, then the free ones, with
/// "6 to Nashville · 4 seats free" underneath.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.label,
    required this.used,
    required this.primary,
    required this.total,
    required this.color,
    this.caption,
    this.bonus,
    super.key,
  });

  /// The row's load bonus, on the right.
  final Widget? bonus;

  final String label;
  final int used;

  /// How many of [used] go to the city most of the load is going to.
  final int primary;
  final int total;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final count = total > used ? total : used;
    final gap = count > 16 ? 2.0 : 3.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Board.muted),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < count; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(
                      child: Container(
                        height: 18,
                        constraints: const BoxConstraints(maxWidth: 28),
                        decoration: BoxDecoration(
                          color: i < primary
                              ? color
                              : i < used
                              ? color.withValues(alpha: 0.35)
                              : null,
                          borderRadius: BorderRadius.circular(
                            count > 12 ? 4 : 6,
                          ),
                          border: i < used
                              ? null
                              : Border.all(
                                  color: Board.muted.withValues(alpha: 0.5),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (bonus != null) ...[const SizedBox(width: 6), bonus!],
          ],
        ),
        if (caption case final caption?)
          Padding(
            padding: const EdgeInsets.only(left: 74, top: 2),
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Board.muted),
            ),
          ),
      ],
    );
  }
}

/// The filters over the job list: the city button that opens the picker,
/// then quick Seats, Cargo and Fits toggles.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.cityLabel,
    required this.hasSeats,
    required this.hasCargo,
    required this.onCity,
    required this.onChange,
  });

  final LoadFilter filter;
  final String cityLabel;
  final bool hasSeats;
  final bool hasCargo;
  final VoidCallback onCity;
  final void Function(LoadFilter Function(LoadFilter)) onChange;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Material(
          color: Board.amber,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('load.cityPicker'),
            onTap: onCity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      cityLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Board.amberInk,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: Board.amberInk,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (hasSeats && hasCargo) ...[
        const SizedBox(width: 6),
        _Toggle(
          key: const Key('load.filter.seats'),
          icon: Icons.person_outline,
          label: 'Seats',
          on: filter.seatsOnly,
          onTap: () => onChange(
            (f) => f.copyWith(seatsOnly: !f.seatsOnly, cargoOnly: false),
          ),
        ),
        const SizedBox(width: 6),
        _Toggle(
          key: const Key('load.filter.cargo'),
          icon: Icons.inventory_2_outlined,
          label: 'Cargo',
          on: filter.cargoOnly,
          onTap: () => onChange(
            (f) => f.copyWith(cargoOnly: !f.cargoOnly, seatsOnly: false),
          ),
        ),
      ],
      const SizedBox(width: 6),
      _Toggle(
        key: const Key('load.filter.fits'),
        icon: Icons.check,
        label: 'Fits',
        on: filter.fitsOnly,
        onTap: () => onChange((f) => f.copyWith(fitsOnly: !f.fitsOnly)),
      ),
    ],
  );
}

/// A small on/off chip for the filter row, green while on.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Board.good : Board.ink;
    return Semantics(
      toggled: on,
      label: label,
      child: Material(
        color: on ? Board.good.withValues(alpha: 0.12) : Board.panel,
        shape: StadiumBorder(
          side: BorderSide(color: on ? Board.good : Board.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                // Narrow phones get just the icon.
                if (MediaQuery.sizeOf(context).width >= 360) ...[
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "✓ FILLS SEATS": what a city's waiting jobs could fill on their own.
class _FillTag extends StatelessWidget {
  const _FillTag(this.fill, {super.key});

  final CityFill fill;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Board.good),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check, size: 11, color: Board.good),
        const SizedBox(width: 3),
        Text(switch (fill) {
          CityFill.all => 'CAN FILL',
          CityFill.seats => 'FILLS SEATS',
          CityFill.hold => 'FILLS HOLD',
          CityFill.none => '',
        }, style: Board.flapStyle(size: 10, color: Board.good)),
      ],
    ),
  );
}

String _roomText(int seats, int slots) => [
  if (seats > 0) '$seats ${seats == 1 ? 'seat' : 'seats'}',
  if (slots > 0) '$slots ${slots == 1 ? 'slot' : 'slots'}',
].join(' · ');

/// One destination's waiting jobs: a header with what's waiting (tap to
/// filter to it) and compact rows below.
class _CityGroupCard extends StatelessWidget {
  const _CityGroupCard({
    required this.group,
    required this.name,
    required this.selected,
    required this.onHeader,
    required this.hidden,
    required this.onMore,
    required this.rows,
    super.key,
  });

  final CityGroup group;
  final String name;
  final bool selected;
  final VoidCallback onHeader;

  /// Rows held back behind "+ N more".
  final int hidden;
  final VoidCallback onMore;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final n = group.jobs.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Board.flap,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? Board.amber : Board.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Board.panel,
            child: InkWell(
              key: Key('load.groupHeader.${group.cityId}'),
              onTap: onHeader,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Board.ink,
                                  ),
                                ),
                                TextSpan(
                                  text: ' · ${formatKm(group.distanceKm)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Board.muted,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$n ${n == 1 ? 'job' : 'jobs'} · '
                            '${_roomText(group.seats, group.cargoSlots)} '
                            'waiting',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Board.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (group.fill != CityFill.none)
                      _FillTag(
                        group.fill,
                        key: Key('load.fill.${group.cityId}'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (final row in rows.take(rows.length - hidden)) row,
          if (hidden > 0)
            InkWell(
              key: Key('load.more.${group.cityId}'),
              onTap: onMore,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Board.line.withValues(alpha: 0.5)),
                  ),
                ),
                child: Text(
                  '+ $hidden more',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Board.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A waiting job inside its city's card: what it is ("Group of 4 ·
/// 52/seat") and its Board button. Faded when it is too big for the room
/// left; tapping it then offers the seat it needs.
class _CompactJobRow extends StatelessWidget {
  const _CompactJobRow({
    required this.sim,
    required this.job,
    required this.tooBig,
    required this.onTap,
    this.onLongPress,
    this.removeCityId,
    this.leavesSoon = false,
    this.showCity = false,
    super.key,
  });

  final Simulation sim;
  final Job job;
  final bool tooBig;
  final bool leavesSoon;

  /// Name the city too (for rows outside a city card).
  final bool showCity;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? removeCityId;

  @override
  Widget build(BuildContext context) {
    final world = sim.rules.world;
    final passenger = job.type == JobType.passenger;
    final kind = switch (job.kind) {
      JobKind.vip => 'VIP',
      JobKind.rush => 'Rush',
      JobKind.fragile => 'Fragile',
      JobKind.bulk => 'Bulk',
      JobKind.sightseeing => 'Tour, round trip',
      JobKind.partCrate => '⚙ Part crate',
      JobKind.standard => passenger ? 'Passenger' : 'Cargo',
    };
    final String title;
    if (job.slots > 1 && passenger) {
      title = job.kind == JobKind.standard
          ? 'Group of ${job.slots}'
          : '$kind, group of ${job.slots}';
    } else if (job.slots > 1) {
      title = '$kind, ${job.slots} slots';
    } else {
      title = kind;
    }
    final notes = [
      if (job.slots > 1 && job.kind != JobKind.partCrate)
        '${(job.payout / job.slots).round()}/${passenger ? 'seat' : 'slot'}',
      if (job.kind == JobKind.sightseeing) 'Barnstormer only',
      if (job.kind == JobKind.partCrate) 'a plane part',
      if (job.kind == JobKind.fragile) 'needs loadmaster',
      if (job.kind == JobKind.rush) 'next plane out',
      if (leavesSoon) 'leaves soon',
      if (tooBig) 'too big',
    ];
    final row = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Board.line.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              passenger ? Icons.person_outline : Icons.inventory_2_outlined,
              color: passenger ? Board.amber : Board.cargo,
              size: 18,
            ),
            const SizedBox(width: 8),
            if (job.isConnecting) ...[
              LayoverBadge(compact: true, key: Key('load.layover.${job.id}')),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (showCity)
                      TextSpan(
                        text: '${jobDestination(world, job)} · ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    TextSpan(text: title),
                    if (notes.isNotEmpty)
                      TextSpan(
                        text: ' · ${notes.join(' · ')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Board.muted,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Board.ink),
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
              added: false,
              compact: true,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
    return tooBig ? Opacity(opacity: 0.4, child: row) : row;
  }
}

/// One line for the jobs aboard bound for one city when the load is
/// folded ("▸ Nashville ×4 · 6 seats  472"). Tap to open its jobs.
class _AboardCity extends StatelessWidget {
  const _AboardCity({
    required this.name,
    required this.jobs,
    required this.open,
    required this.onTap,
    this.bonusPct,
    super.key,
  });

  final String name;
  final List<Job> jobs;
  final bool open;
  final VoidCallback onTap;
  final double? bonusPct;

  @override
  Widget build(BuildContext context) {
    int room(JobType type) =>
        jobs.where((j) => j.type == type).fold(0, (sum, j) => sum + j.slots);
    final pay = jobs.fold(0, (sum, j) => sum + j.payout);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Board.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Board.amber),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 9, 12, 9),
            child: Row(
              children: [
                Icon(
                  open ? Icons.arrow_drop_down : Icons.arrow_right,
                  color: Board.muted,
                  size: 20,
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Board.ink,
                          ),
                        ),
                        TextSpan(
                          text:
                              '  ×${jobs.length} · '
                              '${_roomText(room(JobType.passenger), room(JobType.cargo))}',
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Board.muted),
                  ),
                ),
                if (bonusPct case final pct?) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
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
                  const SizedBox(width: 8),
                ],
                Text(
                  formatCoins(pay),
                  style: Board.flapStyle(size: 13, color: Board.amber),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every destination on one screen: jobs and room waiting and what each
/// could fill, sorted by most room, best pay, nearest or name. Pops the
/// city picked, or (null,) for every city.
class _CityPicker extends StatefulWidget {
  const _CityPicker({
    required this.view,
    required this.selected,
    required this.sort,
    required this.onSort,
  });

  final LoadView view;
  final String? selected;
  final CitySort sort;
  final ValueChanged<CitySort> onSort;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  late CitySort _sort = widget.sort;

  @override
  Widget build(BuildContext context) {
    final world = ProviderScope.containerOf(context)
        .read(simulationProvider)
        .rules
        .world;
    String name(String id) => world.city(id).name;
    final cities = widget.view.sorted(_sort, name);
    Widget tile({
      required Key key,
      required String title,
      required String sub,
      required String jobs,
      required bool selected,
      required VoidCallback onTap,
      CityFill fill = CityFill.none,
    }) => Material(
      key: key,
      color: selected ? Board.amber.withValues(alpha: 0.14) : Board.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? Board.amber : Board.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 7, 6, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Board.ink,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Board.muted),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      jobs,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Board.muted,
                      ),
                    ),
                  ),
                  if (fill != CityFill.none) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.check, size: 11, color: Board.good),
                    Text(switch (fill) {
                      CityFill.all => 'FILL',
                      CityFill.seats => 'SEATS',
                      _ => 'HOLD',
                    }, style: Board.flapStyle(size: 10, color: Board.good)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('GOING TO', style: Board.flapStyle(size: 15)),
                  ),
                  Text(
                    '${cities.length} '
                    '${cities.length == 1 ? 'city' : 'cities'}',
                    style: const TextStyle(fontSize: 13, color: Board.muted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Board.ground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    for (final (sort, label) in const [
                      (CitySort.seats, 'Most room'),
                      (CitySort.pay, 'Best pay'),
                      (CitySort.nearest, 'Nearest'),
                      (CitySort.name, 'A–Z'),
                    ])
                      Expanded(
                        child: GestureDetector(
                          key: Key('load.pickSort.${sort.name}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() => _sort = sort);
                            widget.onSort(sort);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: _sort == sort ? Board.line : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _sort == sort ? Board.ink : Board.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              tile(
                key: const Key('load.pick.all'),
                title: 'All cities',
                sub: 'Every destination',
                jobs: '${widget.view.boardCount} jobs',
                selected: widget.selected == null,
                onTap: () => Navigator.of(context).pop((null,)),
              ),
              const SizedBox(height: 7),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  mainAxisExtent: 66,
                ),
                children: [
                  for (final g in cities)
                    tile(
                      key: Key('load.pick.${g.cityId}'),
                      title: name(g.cityId),
                      sub: _roomText(g.seats, g.cargoSlots),
                      jobs:
                          '${g.jobs.length} '
                          '${g.jobs.length == 1 ? 'job' : 'jobs'}',
                      fill: g.fill,
                      selected: widget.selected == g.cityId,
                      onTap: () => Navigator.of(context).pop((g.cityId,)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({
    required this.sim,
    required this.fromCityId,
    required this.job,
    required this.added,
    required this.onTap,
    this.bonusPct,
    super.key,
  });

  final Simulation sim;
  final String fromCityId;
  final Job job;
  final bool added;
  final VoidCallback onTap;

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
/// Add buttons, filled green with a tick once the load as it stands earns
/// it.
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
      color: earned ? Board.good : null,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: earned ? Board.good : Board.cargo, width: 1.5),
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
    this.compact = false,
    super.key,
  });

  final String label;
  final bool added;

  /// A slightly smaller button for rows inside a city card.
  final bool compact;
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
              constraints: BoxConstraints(
                minWidth: compact ? 112 : 132,
                minHeight: compact ? 30 : 34,
              ),
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
