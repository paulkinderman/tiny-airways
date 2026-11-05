import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'growth_sheets.dart';
import 'owned_airports.dart';
import 'rivals_screens.dart';
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// An owned airport: gates, the job board and the planes parked here. Tapping
/// a parked plane opens its loading sheet.
class AirportPanelView extends ConsumerWidget {
  const AirportPanelView({required this.panel, super.key});

  final AirportPanel panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final config = sim.rules.config;
    final airport = state.airport(panel.cityId);
    if (airport == null) return const SizedBox.shrink();
    final city = config.world.city(panel.cityId);
    final parked = [
      for (final p in state.planes)
        if (p.status == PlaneStatus.parked && p.cityId == city.id) p,
    ];
    final stored = [
      for (final p in state.planes)
        if (p.isStored && p.cityId == city.id) p,
    ];
    final size = sim.boards.boardSize(state, airport);
    final fresh = airport.board.where((j) => !j.isConnecting).length;
    final ui = ref.read(uiProvider.notifier);

    return TickBuilder(
      builder: (context, now) {
        final weather = [
          for (final e in state.weather.events)
            if (sim.weather.covers(e, city.id) && e.endsAt.isAfter(now)) e,
        ];
        return GestureDetector(
          key: const Key('airport.swipe'),
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 300) return;
            stepAirport(ref, city.id, now, v < 0 ? 1 : -1);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: city.name,
                subtitle:
                    '${citySizeLabel(city.size)} · Airport Lv ${airport.level}'
                    '${state.homeCityId == city.id ? ' · Home' : ''}',
                onBack: ui.close,
                trailing: _AirportStepper(cityId: city.id, now: now),
              ),
              _AirportStrip(cityId: city.id, now: now),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                            label: 'Gates',
                            value:
                                '${parked.length} / ${sim.flights.gates(airport)}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            label: 'Jobs',
                            value: '$fresh / ${size.passenger + size.cargo}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatTile(
                            key: const Key('airport.rotation'),
                            label: 'New jobs in',
                            value: formatMinSec(
                              sim.boards.nextRotationAt(state).difference(now),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      key: const Key('airport.layovers'),
                      children: [
                        const LayoverBadge(compact: true),
                        const SizedBox(width: 6),
                        Text(
                          'Layover slots '
                          '${sim.loading.layoversUsed(state, city.id)} / '
                          '${sim.loading.layoverSlots(state, city.id)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Board.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CityShareLine(cityId: city.id),
                    for (final e in weather) ...[
                      const SizedBox(height: 10),
                      _WeatherLine(event: e, now: now),
                    ],
                    const SizedBox(height: 14),
                    AirportGrowth(cityId: city.id),
                    const SizedBox(height: 14),
                    _GateRow(
                      parked: parked,
                      selectedId: panel.planeId,
                      onSelect: (id) => ui.open(LoadingPanel(id)),
                    ),
                    if (stored.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _HangarRow(
                        stored: stored,
                        canActivate: sim.flights.freeGates(state, city.id) > 0,
                        onSelect: (id) => ui.open(PlanePanel(id)),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _JobBoard(sim: sim, state: state, airport: airport),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Opens the owned airport [delta] places from [cityId] in the Airports
/// tab's order, wrapping around.
void stepAirport(WidgetRef ref, String cityId, DateTime now, int delta) {
  final order = ownedAirports(
    ref.read(gameSessionProvider),
    ref.read(simulationProvider),
    now,
    ref.read(airportSortProvider),
  );
  if (order.length < 2) return;
  final i = order.indexWhere((a) => a.cityId == cityId);
  final next = order[(i + delta) % order.length];
  ref.read(uiProvider.notifier).open(AirportPanel(next.cityId));
}

/// ◀ 2 / 9 ▶ in the airport panel's header.
class _AirportStepper extends ConsumerWidget {
  const _AirportStepper({required this.cityId, required this.now});

  final String cityId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    ref.watch(airportSortProvider);
    final n = state.airports.length;
    if (n < 2) return const SizedBox.shrink();
    final order = ownedAirports(
      state,
      ref.read(simulationProvider),
      now,
      ref.read(airportSortProvider),
    );
    final i = order.indexWhere((a) => a.cityId == cityId);
    Widget button(String key, IconData icon, int delta, String tip) => SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: Board.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Board.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key(key),
          onTap: () => stepAirport(ref, cityId, now, delta),
          child: Tooltip(
            message: tip,
            child: Icon(icon, size: 20, color: Board.ink),
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('airport.prev', Icons.chevron_left, -1, 'Previous airport'),
        SizedBox(
          width: 52,
          child: Text(
            '${i + 1} / $n',
            key: const Key('airport.position'),
            textAlign: TextAlign.center,
            style: Board.flapStyle(size: 12).copyWith(color: Board.muted),
          ),
        ),
        button('airport.next', Icons.chevron_right, 1, 'Next airport'),
      ],
    );
  }
}

/// Every owned airport in the Airports tab's order, as a strip of names
/// with a dot for the share race; tap one to jump to it.
class _AirportStrip extends ConsumerStatefulWidget {
  const _AirportStrip({required this.cityId, required this.now});

  final String cityId;
  final DateTime now;

  @override
  ConsumerState<_AirportStrip> createState() => _AirportStripState();
}

class _AirportStripState extends ConsumerState<_AirportStrip> {
  final _current = GlobalKey();
  String? _shownFor;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final sort = ref.watch(airportSortProvider);
    if (state.airports.length < 2) return const SizedBox.shrink();
    final order = ownedAirports(
      state,
      ref.read(simulationProvider),
      widget.now,
      sort,
    );
    if (_shownFor != widget.cityId) {
      _shownFor = widget.cityId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _current.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }
    return SizedBox(
      height: 48,
      child: ListView(
        key: const Key('airport.strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        children: [
          for (final a in order) ...[
            _StripPill(
              key: a.cityId == widget.cityId
                  ? _current
                  : Key('airport.strip.${a.cityId}'),
              info: a,
              current: a.cityId == widget.cityId,
              onTap: () =>
                  ref.read(uiProvider.notifier).open(AirportPanel(a.cityId)),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _StripPill extends StatelessWidget {
  const _StripPill({
    required this.info,
    required this.current,
    required this.onTap,
    super.key,
  });

  final OwnedAirportInfo info;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dot = switch (info.standing) {
      ShareStanding.lead => Board.good,
      ShareStanding.leadClose => Board.amber,
      ShareStanding.rivalLeads => Board.bad,
      _ => info.parked > 0 ? Board.pax : Board.muted,
    };
    return Material(
      color: Board.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: current ? Board.amber : Board.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: current ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                info.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  color: current ? Board.amber : Board.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeatherLine extends ConsumerWidget {
  const _WeatherLine({required this.event, required this.now});

  final WeatherEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final name = config.weather.events
        .firstWhere((t) => t.id == event.typeId)
        .name;
    final text = event.activeAt(now)
        ? '$name now · clears in ${formatCountdown(event.endsAt.difference(now))}'
        : '$name in ${formatCountdown(event.startsAt.difference(now))}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Board.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Board.line),
      ),
      child: Row(
        children: [
          Icon(weatherIcon(event.typeId), color: Board.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Board.ink)),
          ),
        ],
      ),
    );
  }
}

IconData weatherIcon(String typeId) => switch (typeId) {
  'thunderstorm' => Icons.thunderstorm,
  'fog' => Icons.foggy,
  'snowstorm' => Icons.ac_unit,
  'heat_wave' => Icons.wb_sunny,
  _ => Icons.air,
};

class _GateRow extends ConsumerWidget {
  const _GateRow({
    required this.parked,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Plane> parked;
  final String? selectedId;
  final void Function(String planeId) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    if (parked.isEmpty) {
      return const Text(
        'No planes at the gate. Planes that land here show up to load.',
        style: TextStyle(color: Board.muted),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in parked)
          BoardChip(
            key: Key('airport.plane.${p.id}'),
            icon: Icons.flight,
            label: planeName(config, p),
            selected: p.id == selectedId,
            onTap: () => onSelect(p.id),
          ),
      ],
    );
  }
}

/// Planes stored in this airport's hangar: off the gates, not flying.
class _HangarRow extends ConsumerWidget {
  const _HangarRow({
    required this.stored,
    required this.canActivate,
    required this.onSelect,
  });

  final List<Plane> stored;
  final bool canActivate;
  final void Function(String planeId) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    return Column(
      key: const Key('airport.hangar'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In the hangar · ${stored.length} (no gate used)',
          style: const TextStyle(fontSize: 13, color: Board.muted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in stored)
              BoardChip(
                key: Key('airport.stored.${p.id}'),
                icon: Icons.warehouse_outlined,
                label: planeName(config, p),
                selected: false,
                onTap: () => onSelect(p.id),
              ),
          ],
        ),
        if (!canActivate)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Every gate is taken. Free one to bring a plane out.',
              style: TextStyle(fontSize: 12, color: Board.muted),
            ),
          ),
      ],
    );
  }
}

class _JobBoard extends StatelessWidget {
  const _JobBoard({
    required this.sim,
    required this.state,
    required this.airport,
  });

  final Simulation sim;
  final GameState state;
  final AirportState airport;

  @override
  Widget build(BuildContext context) {
    final world = sim.rules.world;
    final firstLook = firstLookNote(sim, state, airport, state.simulatedTo);
    final jobs = visibleBoard(sim, state, airport, state.simulatedTo)
      ..sort((a, b) => b.payout.compareTo(a.payout));
    final hasLayovers = jobs.any((j) => j.isConnecting);
    TextStyle heading() =>
        Board.flapStyle(size: 10, color: Board.muted, weight: FontWeight.w500);
    return BoardSection(
      title: 'Job board',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                SizedBox(width: 52, child: Text('TYPE', style: heading())),
                Expanded(child: Text('DESTINATION', style: heading())),
                SizedBox(
                  width: 64,
                  child: Text(
                    'KM',
                    textAlign: TextAlign.right,
                    style: heading(),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    'PAY',
                    textAlign: TextAlign.right,
                    style: heading(),
                  ),
                ),
                if (hasLayovers) const SizedBox(width: 30),
              ],
            ),
          ),
          if (firstLook != null)
            Padding(
              key: const Key('airport.firstLook'),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                firstLook,
                style: const TextStyle(fontSize: 13, color: Board.muted),
              ),
            ),
          if (jobs.isEmpty && firstLook == null)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'The board is empty. New jobs arrive with the next rotation.',
                style: TextStyle(color: Board.muted),
              ),
            ),
          for (final j in jobs)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Board.line)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FlapText(
                        j.type == JobType.passenger ? 'Pax' : 'Crg',
                        size: 12,
                        color: j.type == JobType.passenger
                            ? Board.pax
                            : Board.cargo,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (j.isConnecting) ...[
                            LayoverBadge(
                              compact: true,
                              key: Key('airport.layover.${j.id}'),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: FlapText(jobDestination(world, j), size: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      formatCoins(
                        sim.rules
                            .distanceKm(airport.cityId, j.destCityId)
                            .round(),
                      ),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13, color: Board.muted),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FlapText(
                        jobPayLabel(j),
                        size: 13,
                        color: Board.ink,
                      ),
                    ),
                  ),
                  if (hasLayovers)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: j.isConnecting
                          ? RemoveLayoverButton(cityId: airport.cityId, job: j)
                          : const SizedBox(width: 28),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The airport's level with the next level's upgrade, and its upgrade
/// paths, which open the paths sheet.
class AirportGrowth extends ConsumerWidget {
  const AirportGrowth({required this.cityId, super.key});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final growth = sim.growth;
    final config = sim.rules.config;
    final airport = state.airport(cityId);
    if (airport == null) return const SizedBox.shrink();
    final max = config.airports.maxLevel;
    final size = config.world.city(cityId).size;
    final cost = growth.airportUpgradeCost(airport);
    final problem = growth.upgradeAirportProblem(state, cityId);
    final String next;
    if (cost == null) {
      next = 'Top level: ${config.airports.gates(max, size)} gates';
    } else {
      final now = config.airports.level(airport.level);
      final up = config.airports.level(airport.level + 1);
      final classes = {for (final c in config.planes.classes) c.id: c.name};
      next = [
        'Lv ${up.level}: ${config.airports.gates(up.level, size)} gates',
        '${config.airports.jobBoardSize(up.level, size, airportsOwned: state.airports.length)} jobs',
        if (up.maxPlaneClass != now.maxPlaneClass)
          '${classes[up.maxPlaneClass]} planes',
      ].join(', ');
    }
    final unlockAt = config.progression.airportMaxLevel
        .where((s) => s.value > airport.level)
        .firstOrNull
        ?.airlineLevel;
    final paths = [
      for (final p in config.airports.paths)
        if (airport.tier(p.id) > 0) '${p.name} ${airport.tier(p.id)}',
    ];
    final nextTier = [
      for (final p in config.airports.paths)
        ?growth.pathTierCost(airport, p.id),
    ].fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    return BoardSection(
      title: 'Airport level',
      trailing: FlapText('Lv ${airport.level} of $max', size: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GrowthRow(
            title: next,
            subtitle: problem == RuleError.levelTooLow && unlockAt != null
                ? 'Needs airline Lv $unlockAt'
                : cost == null
                ? 'Fully upgraded'
                : 'Costs scale with city size',
            button: cost == null
                ? null
                : AmberButton(
                    key: const Key('airport.upgrade'),
                    mono: true,
                    height: 34,
                    label: problem == RuleError.levelTooLow
                        ? 'Locked'
                        : priceLabel(problem, cost, verb: 'Up'),
                    onPressed: problem == null
                        ? () => actOrExplain(
                            context,
                            ref,
                            (sim, s, now) => sim.upgradeAirport(s, cityId, now),
                          )
                        : null,
                  ),
          ),
          GrowthRow(
            key: const Key('airport.paths'),
            title: paths.isEmpty
                ? 'Upgrade paths'
                : 'Upgrades: ${paths.join(' · ')}',
            subtitle: nextTier == null
                ? 'Every path maxed'
                : 'Buy with coins · from ${formatCoins(nextTier)}',
            onTap: () => showBoardSheet(context, PathsSheet(cityId: cityId)),
            button: const Icon(Icons.chevron_right, color: Board.muted),
          ),
        ],
      ),
    );
  }
}
