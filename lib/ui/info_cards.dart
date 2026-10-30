import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'airport_panel.dart';
import 'format.dart';
import 'plane_art.dart';
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
  });

  final IconData icon;

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
              const SizedBox(height: 8),
              Text(title.toUpperCase(), style: Board.flapStyle(size: 16)),
              const SizedBox(height: 4),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l,
                    style: const TextStyle(fontSize: 14, color: Board.ink),
                  ),
                ),
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
    return TickBuilder(
      builder: (context, now) {
        final leg = plane.leg;
        final lines = <String>[
          '$model · ${flightNumber(plane)}',
          if (plane.status == PlaneStatus.parked)
            'At the gate in ${world.city(plane.cityId).name}'
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
          '${plane.load.length} ${plane.load.length == 1 ? 'job' : 'jobs'} aboard',
        ];
        return _InfoCard(
          icon: Icons.flight,
          art: PlaneArt(plane.modelId, height: 44),
          title: planeName(config, plane),
          lines: lines,
          action: plane.status == PlaneStatus.parked
              ? AmberButton(
                  label: 'Load',
                  mono: true,
                  height: 40,
                  onPressed: () => ref
                      .read(uiProvider.notifier)
                      .open(LoadingPanel(plane.id)),
                )
              : null,
        );
      },
    );
  }
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
    return _InfoCard(
      icon: Icons.location_city,
      title: city.name,
      lines: [
        '${citySizeLabel(city.size)} · ${world.region(city.regionId).name}',
        if (home != null && home != cityId)
          '${formatKm(sim.rules.distanceKm(home, cityId))} from '
              '${world.city(home).name}',
        'Not one of your airports yet.',
      ],
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
      if (r.jobsLate > 0)
        (Icons.timer_off_outlined, '${r.jobsLate} late, paid nothing'),
      if (r.levelsGained > 0)
        (Icons.trending_up, 'Airline reached level ${state.player.level}'),
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
