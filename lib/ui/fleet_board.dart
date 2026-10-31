import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import 'format.dart';
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// Planes parked at a gate, in fleet order.
List<Plane> readyPlanes(GameState state) => [
  for (final p in state.planes)
    if (p.status == PlaneStatus.parked) p,
];

/// One row of the departures board: flight number, where it's going (or
/// parked), ETA and status.
class PlaneBoardRow extends ConsumerWidget {
  const PlaneBoardRow({
    required this.plane,
    required this.now,
    this.onLoad,
    this.onTap,
    this.showEta = true,
    super.key,
  });

  final Plane plane;
  final DateTime now;
  final VoidCallback? onLoad;
  final VoidCallback? onTap;
  final bool showEta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(gameConfigProvider);
    final parked = plane.status == PlaneStatus.parked;
    final cityId = parked ? plane.cityId : plane.leg!.toCityId;
    final model = config.planes.model(plane.modelId).name;
    final name = planeName(config, plane);
    final jobs = plane.load.length;
    final subtitle = [
      name == model ? model : '$name · $model',
      if (parked && jobs > 0) '$jobs aboard',
    ].join(' · ');
    final number = flightNumber(plane).split(' ');

    return InkWell(
      key: Key('board.plane.${plane.id}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Board.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: Board.raised,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  Text(number.first, style: Board.flapStyle(size: 12)),
                  Text(number.last, style: Board.flapStyle(size: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FlapText(config.world.city(cityId).name, size: 13),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Board.muted),
                  ),
                ],
              ),
            ),
            if (showEta) ...[
              const SizedBox(width: 8),
              FlapText(
                parked ? '--:--' : formatClock(plane.leg!.arriveAt),
                size: 13,
                color: Board.ink,
              ),
            ],
            const SizedBox(width: 8),
            SizedBox(
              width: 86,
              child: Align(
                alignment: Alignment.centerRight,
                child: switch (plane.status) {
                  PlaneStatus.parked => AmberButton(
                    key: Key('board.load.${plane.id}'),
                    label: 'Load',
                    mono: true,
                    height: 36,
                    onPressed: onLoad,
                  ),
                  PlaneStatus.flying => Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FlapText(
                        plane.leg!.diverted ? 'Diverted' : 'En route',
                        size: 11,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatCountdown(plane.leg!.arriveAt.difference(now)),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Board.muted,
                        ),
                      ),
                    ],
                  ),
                  PlaneStatus.holding => const FlapText(
                    'Holding',
                    size: 11,
                    color: Board.bad,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The map's bottom panel: planes ready at a gate, with Load buttons.
class GatePanel extends ConsumerWidget {
  const GatePanel({required this.onLoad, required this.onShowPlane, super.key});

  /// Tallest it gets; it shrinks to fit two rows or a short message.
  static const maxHeight = 196.0;

  final void Function(String planeId) onLoad;
  final void Function(String planeId) onShowPlane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final ready = readyPlanes(state);
    final flying = ref.read(simulationProvider).flights.inTheAir(state);
    return TickBuilder(
      builder: (context, now) => Container(
        constraints: const BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Board.flap,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Board.amber, width: 1.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'READY AT GATE',
                      style: Board.flapStyle(size: 15),
                    ),
                  ),
                  Text(
                    '${ready.length} OF ${state.planes.length}',
                    style: Board.flapStyle(size: 12, color: Board.muted),
                  ),
                ],
              ),
            ),
            if (ready.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  flying.isEmpty
                      ? 'No planes yet.'
                      : 'Every plane is in the air. Next lands in '
                            '${formatCountdown(flying.first.leg!.arriveAt.difference(now))}.',
                  key: const Key('gate.empty'),
                  style: const TextStyle(fontSize: 14, color: Board.muted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final p in ready)
                      PlaneBoardRow(
                        plane: p,
                        now: now,
                        showEta: false,
                        onLoad: () => onLoad(p.id),
                        onTap: () => onShowPlane(p.id),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The departures board: every plane, ready ones first, then those in the
/// air, soonest landing first.
class FleetScreen extends ConsumerWidget {
  const FleetScreen({
    required this.onLoad,
    required this.onShowPlane,
    super.key,
  });

  final void Function(String planeId) onLoad;
  final void Function(String planeId) onShowPlane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final ready = readyPlanes(state);
    final flying = ref.read(simulationProvider).flights.inTheAir(state);
    return TickBuilder(
      builder: (context, now) => ColoredBox(
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
              child: Row(
                children: [
                  Expanded(
                    child: Text('FLEET', style: Board.flapStyle(size: 20)),
                  ),
                  FlapText(formatClock(now), size: 18, color: Board.ink),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  BoardSection(
                    title: 'Ready at gate',
                    trailing: const Icon(
                      Icons.send_rounded,
                      color: Board.amber,
                      size: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BoardHeadings(),
                        if (ready.isEmpty)
                          const _EmptyRow('No planes at a gate.'),
                        for (final p in ready)
                          PlaneBoardRow(
                            plane: p,
                            now: now,
                            onLoad: () => onLoad(p.id),
                            onTap: () => onShowPlane(p.id),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  BoardSection(
                    title: 'In the air',
                    trailing: const Icon(
                      Icons.flight_takeoff,
                      color: Board.amber,
                      size: 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BoardHeadings(),
                        if (flying.isEmpty)
                          const _EmptyRow('Nothing in the air right now.'),
                        for (final p in flying)
                          PlaneBoardRow(
                            plane: p,
                            now: now,
                            onTap: () => onShowPlane(p.id),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Board.line, width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('fleet.toHangar'),
                      onTap: () =>
                          ref.read(uiProvider.notifier).showTab(HomeTab.hangar),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        child: Text(
                          'BUY MORE PLANES IN THE HANGAR',
                          style: Board.flapStyle(size: 13, color: Board.muted),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardHeadings extends StatelessWidget {
  const _BoardHeadings();

  @override
  Widget build(BuildContext context) {
    TextStyle style() =>
        Board.flapStyle(size: 10, color: Board.muted, weight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          SizedBox(width: 54, child: Text('FLIGHT', style: style())),
          Expanded(child: Text('TO', style: style())),
          SizedBox(width: 60, child: Text('ETA', style: style())),
          SizedBox(
            width: 86,
            child: Text('STATUS', textAlign: TextAlign.right, style: style()),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Board.line)),
    ),
    child: Text(text, style: const TextStyle(color: Board.muted)),
  );
}
