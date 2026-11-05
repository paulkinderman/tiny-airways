import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'airport_panel.dart';
import 'airports_screen.dart';
import 'fleet_board.dart' show parkPlane;
import 'format.dart';
import 'growth_sheets.dart';
import 'plane_art.dart';
import 'rivals_screens.dart';
import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// A small card over the bottom of the map, for a plane, a weather event or
/// a city the player doesn't own.
class _InfoCard extends ConsumerWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.lines,
    this.action,
    this.art,
    this.onRename,
    this.nav,
    this.footer,
  });

  /// Shown above the title (the plane card's flight switcher).
  final Widget? nav;

  /// Shown under [lines] (the plane card's trip profit).
  final Widget? footer;

  final IconData icon;

  /// Shows a pencil beside the title that calls this (planes only).
  final VoidCallback? onRename;

  /// A picture shown in place of [icon] (the plane's art).
  final Widget? art;
  final String title;
  final List<String> lines;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
    decoration: const BoxDecoration(
      color: Board.flap,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      border: Border(top: BorderSide(color: Board.amber, width: 1.5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: art ?? Icon(icon, color: Board.amber, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (nav != null) nav! else const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title.toUpperCase(),
                      style: Board.flapStyle(size: 16),
                    ),
                  ),
                  if (onRename != null)
                    InkResponse(
                      key: const Key('card.rename'),
                      onTap: onRename,
                      radius: 18,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: Board.muted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l,
                    style: const TextStyle(fontSize: 14, color: Board.ink),
                  ),
                ),
              if (footer != null) ...[const SizedBox(height: 8), footer!],
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
        IconButton(
          key: const Key('card.close'),
          tooltip: 'Close',
          onPressed: ref.read(uiProvider.notifier).close,
          icon: const Icon(Icons.close, color: Board.muted),
        ),
      ],
    ),
  );
}

class PlaneCard extends ConsumerWidget {
  const PlaneCard({required this.planeId, super.key});

  final String planeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final plane = state.plane(planeId);
    if (plane == null) return const SizedBox.shrink();
    final world = config.world;
    final model = config.planes.model(plane.modelId).name;
    final autopilot = state.crew.autopilot[plane.id];
    final flights = ref.read(simulationProvider).flights;
    final activateProblem = plane.isStored
        ? flights.activateProblem(state, plane)
        : null;
    final session = ref.read(gameSessionProvider.notifier);
    return TickBuilder(
      builder: (context, now) {
        final leg = plane.leg;
        final lines = <String>[
          '$model · ${flightNumber(plane)}',
          if (plane.status == PlaneStatus.parked)
            'At the gate in ${world.city(plane.cityId).name}'
          else if (plane.isStored) ...[
            'In the hangar at ${world.city(plane.cityId).name}, not using a '
                'gate',
            if (activateProblem == RuleError.noFreeGate)
              'Every gate there is taken. Free one to bring it out.',
          ] else if (leg != null && leg.isDelivery)
            'Just delivered: circling ${world.city(plane.cityId).name} '
                'until a gate frees up'
          else if (leg != null) ...[
            '${world.city(leg.fromCityId).name} to ${world.city(leg.toCityId).name}'
                '${leg.diverted ? ' (diverted)' : ''}',
            if (plane.status == PlaneStatus.holding)
              'Holding over ${world.city(plane.cityId).name}, waiting to land'
            else
              'Lands in ${formatCountdown(leg.arriveAt.difference(now))} '
                  '(${formatClock(leg.arriveAt)})',
            if (plane.remainingStops.isNotEmpty)
              'Then ${plane.remainingStops.map((c) => world.city(c).name).join(', ')}',
          ],
          if (!plane.isStored)
            '${plane.load.length} ${plane.load.length == 1 ? 'job' : 'jobs'} aboard',
          if (autopilot != null)
            'On autopilot: ${autopilot.stops.map((c) => world.city(c).name).join(' → ')}, round and round',
        ];
        final flying = plane.onGround
            ? const <Plane>[]
            : flights.inTheAir(state);
        final delivery = leg != null && leg.isDelivery;
        return _InfoCard(
          icon: Icons.flight,
          art: PlaneArt(plane.modelId, height: 44),
          title: planeName(config, plane),
          onRename: () => showRenamePlaneDialog(context, ref, plane.id),
          lines: lines,
          nav: flying.length > 1 ? _FlightSwitcher(plane.id, flying) : null,
          footer: plane.onGround || delivery
              ? null
              : _TripProfitRow(flights.tripProfit(state, plane, now)),
          action: autopilot != null
              ? AmberButton(
                  key: const Key('plane.stopAutopilot'),
                  label: 'Stop autopilot',
                  mono: true,
                  height: 40,
                  outlined: true,
                  onPressed: () => ref
                      .read(gameSessionProvider.notifier)
                      .act(
                        (sim, s, now) => sim.stopAutopilot(s, plane.id, now),
                      ),
                )
              : plane.status == PlaneStatus.parked
              ? Row(
                  children: [
                    Expanded(
                      child: AmberButton(
                        key: const Key('plane.store'),
                        label: 'Park in hangar',
                        mono: true,
                        height: 40,
                        outlined: true,
                        onPressed: () => parkPlane(context, ref, plane),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AmberButton(
                        label: 'Load',
                        mono: true,
                        height: 40,
                        onPressed: () => ref
                            .read(uiProvider.notifier)
                            .open(LoadingPanel(plane.id)),
                      ),
                    ),
                  ],
                )
              : plane.isStored
              ? AmberButton(
                  key: const Key('plane.activate'),
                  label: 'Bring to gate',
                  mono: true,
                  height: 40,
                  onPressed: activateProblem == null
                      ? () => session.act(
                          (sim, s, now) => sim.activatePlane(s, plane.id, now),
                        )
                      : null,
                )
              : null,
        );
      },
    );
  }
}

/// "‹ FLIGHT 2 OF 5 ›" over a plane in the air: steps through every plane
/// in the air, soonest landing first, and the map follows.
class _FlightSwitcher extends ConsumerWidget {
  const _FlightSwitcher(this.planeId, this.flying);

  final String planeId;
  final List<Plane> flying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = flying.indexWhere((p) => p.id == planeId);
    void go(int step) {
      final next = flying[(i + step) % flying.length];
      ref.read(uiProvider.notifier).open(PlanePanel(next.id));
    }

    Widget arrow(IconData icon, String key, String tip, int step) =>
        InkResponse(
          key: Key(key),
          onTap: () => go(step),
          radius: 20,
          child: Tooltip(
            message: tip,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, color: Board.amber, size: 22),
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.chevron_left, 'plane.prevFlight', 'Previous flight', -1),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'FLIGHT ${i + 1} OF ${flying.length}',
              key: const Key('plane.flightIndex'),
              style: Board.flapStyle(size: 11, color: Board.muted),
            ),
          ),
        ),
        arrow(Icons.chevron_right, 'plane.nextFlight', 'Next flight', 1),
      ],
    );
  }
}

/// What the trip in the air should make: payout (earned plus still to
/// come) less the fuel paid at departure.
class _TripProfitRow extends StatelessWidget {
  const _TripProfitRow(this.trip);

  final TripProfit trip;

  @override
  Widget build(BuildContext context) {
    final profit = trip.profit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Board.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _figure('Payout', formatCoins(trip.payout)),
          _figure('Fuel', '−${formatCoins(trip.fuel)}'),
          _figure(
            'Profit',
            formatCoins(profit),
            key: const Key('plane.profit'),
            color: profit >= 0 ? Board.good : Board.bad,
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value, {Key? key, Color? color}) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(fontSize: 12, color: Board.muted),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                key: key,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color ?? Board.ink,
                ),
              ),
            ),
          ],
        ),
      );
}

class WeatherCard extends ConsumerWidget {
  const WeatherCard({required this.weatherId, super.key});

  final String weatherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final event = state.weather.events
        .where((e) => e.id == weatherId)
        .firstOrNull;
    if (event == null) return const SizedBox.shrink();
    final type = config.weather.events.firstWhere((t) => t.id == event.typeId);
    final world = config.world;
    final where = event.bandLat != null
        ? 'A band round the world near ${event.bandLat!.round().abs()}°'
              '${event.bandLat! >= 0 ? 'N' : 'S'}, blowing '
              '${event.eastbound ?? true ? 'east' : 'west'}'
        : type.area == 'cluster'
        ? 'Within ${config.weather.clusterRadiusKm} km of '
              '${world.city(event.cityId!).name}'
        : 'Over ${world.city(event.cityId!).name}';
    return TickBuilder(
      builder: (context, now) => _InfoCard(
        icon: weatherIcon(event.typeId),
        title: type.name,
        lines: [
          where,
          event.activeAt(now)
              ? 'Clears in ${formatCountdown(event.endsAt.difference(now))}'
              : now.isBefore(event.startsAt)
              ? 'Starts in ${formatCountdown(event.startsAt.difference(now))}'
              : 'Cleared',
          weatherEffectText(config, event.typeId),
        ],
      ),
    );
  }
}

/// What a weather event does, from its numbers in `config/weather.json`.
String weatherEffectText(GameConfig config, String typeId) {
  final e = config.weather.events.firstWhere((t) => t.id == typeId).effects;
  String n(String key) => (e[key] ?? 0).abs().round().toString();
  return switch (typeId) {
    'thunderstorm' =>
      'No landings or departures; planes divert to your nearest airport. '
          'When it clears, jobs here pay +${n('afterClearPayPct')}% for '
          '${n('afterClearMinutes')} minutes.',
    'fog' =>
      'Only captains of level ${n('minCaptainLevel')} or more can land. '
          'Jobs here pay +${n('payPct')}%.',
    'snowstorm' =>
      'Departures burn ${n('departureFuelPct')}% more fuel; jobs leaving '
          'pay +${n('outboundPayPct')}%.',
    'heat_wave' =>
      'Large planes carry ${n('largePlaneSeatPenalty')} fewer passengers; '
          'cargo jobs pay +${n('cargoPayPct')}%.',
    'jet_stream' =>
      'Flights with the wind burn ${n('withFuelPct')}% less fuel, against '
          'it ${n('againstFuelPct')}% more.',
    _ => '',
  };
}

class CityCard extends ConsumerWidget {
  const CityCard({required this.cityId, super.key});

  final String cityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final world = sim.rules.world;
    final city = world.city(cityId);
    final home = state.homeCityId;
    final growth = sim.growth;
    final price = growth.airportPrice(state, cityId);
    final problem = growth.buyAirportProblem(state, cityId);
    final region = world.region(city.regionId).name;
    return _InfoCard(
      icon: Icons.location_city,
      title: city.name,
      lines: [
        '${citySizeLabel(city.size)} · $region',
        if (home != null && home != cityId)
          '${formatKm(sim.rules.distanceKm(home, cityId))} from '
              '${world.city(home).name}',
        problem == RuleError.regionLocked
            ? 'Buy a $region license in Airports to fly here.'
            : 'Not one of your airports yet.',
      ],
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CityShareLine(cityId: cityId),
          if (problem != RuleError.regionLocked &&
              problem != RuleError.alreadyOwned) ...[
            const SizedBox(height: 8),
            AmberButton(
              key: const Key('city.buy'),
              height: 40,
              label: problem == null
                  ? 'Buy airport · ${formatCoins(price)}'
                  : priceLabel(problem, price, verb: 'Buy airport'),
              onPressed: problem == null
                  ? () {
                      if (buyAirport(context, ref, cityId)) {
                        ref
                            .read(uiProvider.notifier)
                            .open(AirportPanel(cityId));
                      }
                    }
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// The welcome-back summary after time away.
class WelcomeBackDialog extends ConsumerWidget {
  const WelcomeBackDialog({required this.summary, super.key});

  final WelcomeBack summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final config = ref.watch(gameConfigProvider);
    final world = config.world;
    final r = summary.report;
    final waiting = state.planes
        .where((p) => p.status == PlaneStatus.parked)
        .toList();
    final weather = [
      for (final id in r.newWeatherIds)
        ...state.weather.events.where((e) => e.id == id),
    ];
    final lines = <(IconData, String)>[
      if (r.moneyEarned > 0)
        (Icons.payments_outlined, 'Earned ${formatCoins(r.moneyEarned)} coins'),
      if (r.jobsDelivered > 0)
        (
          Icons.check_circle_outline,
          '${r.jobsDelivered} ${r.jobsDelivered == 1 ? 'job' : 'jobs'} delivered',
        ),
      if (r.jobsPickedUp > 0)
        (
          Icons.add_circle_outline,
          '${r.jobsPickedUp} ${r.jobsPickedUp == 1 ? 'job' : 'jobs'} '
              'picked up at stops',
        ),
      if (r.jobsLate > 0)
        (Icons.timer_off_outlined, '${r.jobsLate} late, paid nothing'),
      if (r.levelsGained > 0)
        (Icons.trending_up, 'Airline reached level ${state.player.level}'),
      if (r.autopilotEarned > 0)
        (
          Icons.autorenew,
          'Autopilot flights earned ${formatCoins(r.autopilotEarned)}',
        ),
      for (final id in r.autopilotStoppedIds)
        if (state.plane(id) != null)
          (
            Icons.pause_circle_outline,
            '${planeName(config, state.plane(id)!)} came off autopilot: '
                'its route was blocked',
          ),
      for (final d in r.diversions)
        (
          Icons.alt_route,
          '${planeName(config, state.plane(d.planeId)!)} diverted from '
              '${world.city(d.fromCityId).name} to ${world.city(d.toCityId).name}',
        ),
      for (final e in weather)
        (
          weatherIcon(e.typeId),
          '${config.weather.events.firstWhere((t) => t.id == e.typeId).name}'
              '${e.cityId == null ? '' : ' near ${world.city(e.cityId!).name}'}',
        ),
      (
        Icons.flight_land,
        waiting.isEmpty
            ? 'Every plane is still in the air'
            : '${waiting.length} ${waiting.length == 1 ? 'plane' : 'planes'} '
                  'waiting at the gate',
      ),
    ];
    return Dialog(
      backgroundColor: Board.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Board.amber, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('WELCOME BACK', style: Board.flapStyle(size: 20)),
            const SizedBox(height: 4),
            Text(
              'While you were away (${formatAway(summary.away)}):',
              style: const TextStyle(color: Board.muted),
            ),
            const SizedBox(height: 14),
            for (final (icon, text) in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: Board.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(fontSize: 15, color: Board.ink),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            AmberButton(
              key: const Key('welcomeBack.ok'),
              label: 'Back to work',
              height: 50,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
