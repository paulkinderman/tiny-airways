import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/crew_desk.dart';
import '../logic/rules.dart';
import 'format.dart';
import 'map_scene_builder.dart';
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// The most stops a route can have.
const maxRouteStops = 3;

/// Adds [cityId] as the next stop, or takes it off if it is the last one.
/// Returns why it can't be a stop, or null.
String? toggleRouteStop(WidgetRef ref, RoutePanel panel, String cityId) {
  final ui = ref.read(uiProvider.notifier);
  final stops = panel.stops;
  if (stops.isNotEmpty && stops.last == cityId) {
    ui.open(
      RoutePanel(panel.planeId, stops: stops.sublist(0, stops.length - 1)),
    );
    return null;
  }
  final state = ref.read(gameSessionProvider);
  final sim = ref.read(simulationProvider);
  final plane = state.plane(panel.planeId);
  if (plane == null) return null;
  final world = sim.rules.world;
  if (stops.length >= maxRouteStops) {
    return 'Up to $maxRouteStops stops. Tap the last stop to take it off.';
  }
  final from = stops.isEmpty ? plane.cityId : stops.last;
  final problem = sim.flights.legProblem(
    state,
    plane,
    from,
    cityId,
    ref.read(clockProvider).now(),
  );
  if (problem != null) {
    return '${world.city(cityId).name}: ${ruleErrorText(problem)}';
  }
  ui.open(RoutePanel(panel.planeId, stops: [...stops, cityId]));
  return null;
}

/// The header shown over the map while choosing a route.
class RouteHeader extends ConsumerWidget {
  const RouteHeader({required this.panel, super.key});

  final RoutePanel panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SheetHeader(
    title: 'Choose route',
    subtitle: 'Tap airports in order · up to $maxRouteStops stops',
    onBack: () =>
        ref.read(uiProvider.notifier).open(LoadingPanel(panel.planeId)),
  );
}

/// The route picker's bottom panel: next-stop choices, the legs picked so
/// far with time, payout, fuel and profit, and Depart.
class RoutePanelView extends ConsumerWidget {
  const RoutePanelView({
    required this.panel,
    required this.onDeparted,
    super.key,
  });

  final RoutePanel panel;
  final void Function(String planeId) onDeparted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final world = sim.rules.world;
    final plane = state.plane(panel.planeId);
    if (plane == null || plane.status != PlaneStatus.parked) {
      return const SizedBox.shrink();
    }
    final now = ref.read(clockProvider).now();
    final quote = sim.quote(state, plane.id, panel.stops, now);
    final options =
        nextStopOptions(sim, state, plane, panel.stops, now).toList()
          ..sort((a, b) => world.city(a).name.compareTo(world.city(b).name));
    final problems = [
      for (final p in quote.problems)
        if (p != RuleError.noStops) p,
    ];
    final profit = quote.expectedPayout - quote.fuel;
    final autopilot = sim.crew.effects.hasAutopilot(state, plane);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: Board.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Board.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (panel.stops.length < maxRouteStops) ...[
            Text(
              options.isEmpty
                  ? 'No airport in range from here.'
                  : panel.stops.isEmpty
                  ? 'Fly to'
                  : 'Then on to',
              style: const TextStyle(fontSize: 13, color: Board.muted),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final id in options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: BoardChip(
                        key: Key('route.option.$id'),
                        label: world.city(id).name,
                        selected: false,
                        onTap: () {
                          final error = toggleRouteStop(ref, panel, id);
                          if (error != null) showToast(context, error);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final (i, leg) in quote.legs.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Board.amber,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Board.amberInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${world.city(leg.fromCityId).name} to '
                      '${world.city(leg.toCityId).name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Board.ink,
                      ),
                    ),
                  ),
                  Text(
                    '${formatKm(leg.distanceKm)} · '
                    '${formatCountdown(leg.duration)}',
                    style: const TextStyle(fontSize: 12, color: Board.muted),
                  ),
                ],
              ),
            ),
          if (quote.legs.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Board.flap,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _Figure('Time', formatCountdown(quote.duration)),
                  _Figure('Payout', formatCoins(quote.expectedPayout)),
                  _Figure('Fuel', '−${formatCoins(quote.fuel)}'),
                  _Figure(
                    'Profit',
                    formatCoins(profit),
                    key: const Key('route.profit'),
                    color: profit >= 0 ? Board.good : Board.bad,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                ruleErrorText(problems.first),
                key: const Key('route.problem'),
                style: const TextStyle(color: Board.bad),
              ),
            ),
          if (quote.legs.isNotEmpty && plane.load.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Nothing aboard: this flight only repositions the plane.',
                style: TextStyle(fontSize: 13, color: Board.muted),
              ),
            ),
          if (autopilot)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AmberButton(
                key: const Key('route.autopilot'),
                label: 'Repeat on autopilot (70% pay)',
                height: 44,
                outlined: true,
                onPressed: panel.stops.isEmpty
                    ? null
                    : () {
                        final error = ref
                            .read(gameSessionProvider.notifier)
                            .act(
                              (sim, s, now) => sim.startAutopilot(
                                s,
                                plane.id,
                                panel.stops,
                                now,
                              ),
                            );
                        if (error != null) {
                          showToast(context, ruleErrorText(error));
                        } else {
                          showToast(
                            context,
                            'On autopilot: it loops this route until you '
                            'stop it.',
                          );
                          onDeparted(plane.id);
                        }
                      },
              ),
            ),
          Row(
            children: [
              AmberButton(
                key: const Key('route.clear'),
                label: 'Clear',
                height: 52,
                onPressed: panel.stops.isEmpty
                    ? null
                    : () => ref
                          .read(uiProvider.notifier)
                          .open(RoutePanel(panel.planeId)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AmberButton(
                  key: const Key('route.depart'),
                  label: 'Depart',
                  height: 52,
                  onPressed: quote.canDepart
                      ? () {
                          final error = ref
                              .read(gameSessionProvider.notifier)
                              .act(
                                (sim, s, now) =>
                                    sim.depart(s, plane.id, panel.stops, now),
                              );
                          if (error != null) {
                            showToast(context, ruleErrorText(error));
                          } else {
                            onDeparted(plane.id);
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color = Board.ink, super.key});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Board.muted)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}
