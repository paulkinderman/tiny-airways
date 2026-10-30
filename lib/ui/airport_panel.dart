import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// An owned airport: gates, the job board and the planes parked here, with
/// the way into the loading sheet.
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
    final level = config.airports.level(airport.level);
    final parked = [
      for (final p in state.planes)
        if (p.status == PlaneStatus.parked && p.cityId == city.id) p,
    ];
    final selected =
        parked.where((p) => p.id == panel.planeId).firstOrNull ??
        parked.firstOrNull;
    final size = sim.boards.boardSize(state, airport);
    final fresh = airport.board.where((j) => !j.isConnecting).length;
    final ui = ref.read(uiProvider.notifier);
    final paths = [
      for (final p in config.airports.paths)
        if (airport.tier(p.id) > 0) '${p.name} ${airport.tier(p.id)}',
    ];

    return TickBuilder(
      builder: (context, now) {
        final weather = [
          for (final e in state.weather.events)
            if (sim.weather.covers(e, city.id) && e.endsAt.isAfter(now)) e,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: city.name,
              subtitle:
                  '${citySizeLabel(city.size)} · Airport Lv ${airport.level}'
                  '${state.homeCityId == city.id ? ' · Home' : ''}',
              onBack: ui.close,
              trailing: paths.isEmpty
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Board.cargoChip,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        paths.join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Board.cargoInk,
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Gates',
                          value: '${parked.length} / ${level.gates}',
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
                  for (final e in weather) ...[
                    const SizedBox(height: 10),
                    _WeatherLine(event: e, now: now),
                  ],
                  const SizedBox(height: 14),
                  _GateRow(
                    parked: parked,
                    selectedId: selected?.id,
                    onSelect: (id) =>
                        ui.open(AirportPanel(city.id, planeId: id)),
                  ),
                  const SizedBox(height: 14),
                  _JobBoard(
                    sim: sim,
                    state: state,
                    airport: airport,
                    plane: selected,
                    onLoad: selected == null
                        ? null
                        : () => ui.open(LoadingPanel(selected.id)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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

class _JobBoard extends StatelessWidget {
  const _JobBoard({
    required this.sim,
    required this.state,
    required this.airport,
    required this.plane,
    required this.onLoad,
  });

  final Simulation sim;
  final GameState state;
  final AirportState airport;
  final Plane? plane;
  final VoidCallback? onLoad;

  @override
  Widget build(BuildContext context) {
    final world = sim.rules.world;
    final jobs = [...airport.board]
      ..sort((a, b) => b.payout.compareTo(a.payout));
    TextStyle heading() =>
        Board.flapStyle(size: 10, color: Board.muted, weight: FontWeight.w500);
    return BoardSection(
      title: 'Job board',
      trailing: plane == null
          ? null
          : AmberButton(
              key: const Key('airport.load'),
              label: 'Load ${planeName(sim.rules.config, plane!)}',
              mono: true,
              height: 34,
              onPressed: onLoad,
            ),
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
              ],
            ),
          ),
          if (jobs.isEmpty)
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
                      child: FlapText(
                        j.isConnecting
                            ? '${jobDestination(world, j)} ⇄'
                            : jobDestination(world, j),
                        size: 13,
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}
