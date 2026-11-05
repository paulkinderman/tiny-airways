import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/world.dart';
import '../core/state/game_state.dart';
import '../logic/crew_desk.dart';
import '../logic/flights.dart';
import '../logic/rules.dart';
import 'format.dart';
import 'map_scene_builder.dart';
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// The most stops a route can have.
const maxRouteStops = 5;

/// Adds [cityId] as the next stop, or takes it off if it is the last one.
/// Returns why it can't be a stop, or null.
String? toggleRouteStop(WidgetRef ref, RoutePanel panel, String cityId) {
  final ui = ref.read(uiProvider.notifier);
  final stops = panel.stops;
  if (stops.isNotEmpty && stops.last == cityId) {
    ui.open(panel.withStops(stops.sublist(0, stops.length - 1)));
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
  ui.open(panel.withStops([...stops, cityId]));
  return null;
}

/// Takes the stop at [index] off the route. The legs either side join up;
/// if that leg can't be flown, the route panel says why.
void removeRouteStop(WidgetRef ref, RoutePanel panel, int index) {
  final stops = [...panel.stops]..removeAt(index);
  // Two stops in a row at the same airport would be a leg to nowhere.
  final joined = [
    for (final (i, c) in stops.indexed)
      if (i == 0 || stops[i - 1] != c) c,
  ];
  ref.read(uiProvider.notifier).open(panel.withStops(joined));
}

/// The header shown over the map while choosing a route.
class RouteHeader extends ConsumerWidget {
  const RouteHeader({required this.panel, super.key});

  final RoutePanel panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SheetHeader(
    title: 'Choose route',
    subtitle: 'Tap airports in order to add stops · up to $maxRouteStops',
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
    final quote = sim.quote(
      state,
      plane.id,
      panel.stops,
      now,
      pickUp: panel.pickUp,
    );
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
                          if (error != null) {
                            showToast(context, error, kind: ToastKind.error);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 128),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, leg) in quote.legs.indexed)
                    _legRow(context, ref, world, quote, i, leg),
                ],
              ),
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
          if (panel.stops.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      quote.pickups > 0
                          ? 'Pick up jobs at stops '
                                '(${quote.pickups} waiting now)'
                          : 'Pick up jobs at stops',
                      style: const TextStyle(fontSize: 14, color: Board.ink),
                    ),
                  ),
                  Switch(
                    key: const Key('route.pickUp'),
                    value: panel.pickUp,
                    activeThumbColor: Board.amber,
                    onChanged: (v) => ref
                        .read(uiProvider.notifier)
                        .open(
                          RoutePanel(
                            panel.planeId,
                            stops: panel.stops,
                            pickUp: v,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                ruleErrorText(problems.first),
                key: const Key('route.problem'),
                style: const TextStyle(color: Board.bad),
              ),
            ),
          if (quote.legs.isNotEmpty && plane.load.isEmpty && quote.pickups == 0)
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
                          showToast(
                            context,
                            ruleErrorText(error),
                            kind: ToastKind.error,
                          );
                        } else {
                          showToast(
                            context,
                            'On autopilot: it loops this route until you '
                            'stop it.',
                            kind: ToastKind.done,
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
                          .open(panel.withStops(const [])),
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
                                (sim, s, now) => sim.depart(
                                  s,
                                  plane.id,
                                  panel.stops,
                                  now,
                                  pickUp: panel.pickUp,
                                ),
                              );
                          if (error != null) {
                            showToast(
                              context,
                              ruleErrorText(error),
                              kind: ToastKind.error,
                            );
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

/// One leg: its number, where it goes, distance and time, what the plane
/// picks up at its airport, and a button to take that stop off.
Widget _legRow(
  BuildContext context,
  WidgetRef ref,
  WorldData world,
  RouteQuote quote,
  int i,
  LegQuote leg,
) {
  final panel = ref.read(uiProvider).panel;
  final pickups = i < quote.pickupsAt.length ? quote.pickupsAt[i] : 0;
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
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
              if (pickups > 0)
                Text(
                  '+$pickups to pick up here',
                  key: Key('route.pickups.$i'),
                  style: const TextStyle(fontSize: 12, color: Board.amber),
                ),
            ],
          ),
        ),
        Text(
          '${formatKm(leg.distanceKm)} · '
          '${formatCountdown(leg.duration)}',
          style: const TextStyle(fontSize: 12, color: Board.muted),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            key: Key('route.remove.$i'),
            padding: EdgeInsets.zero,
            iconSize: 18,
            tooltip: 'Remove stop',
            icon: const Icon(Icons.close, color: Board.muted),
            onPressed: panel is RoutePanel
                ? () => removeRouteStop(ref, panel, i)
                : null,
          ),
        ),
      ],
    ),
  );
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
