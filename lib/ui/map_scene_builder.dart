import 'dart:ui';

import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../game/map/map_scene.dart';
import '../logic/simulation.dart';
import 'growth_sheets.dart';
import 'ui_state.dart';

/// Builds what the world map shows from the game state and the open panel.
MapScene buildMapScene({
  required Simulation sim,
  required GameState state,
  required UiState ui,
  required DateTime now,
}) {
  final config = sim.rules.config;
  final panel = ui.tab == HomeTab.map ? ui.panel : const NoPanel();
  final waiting = <String, int>{};
  for (final p in state.planes) {
    if (p.status == PlaneStatus.parked) {
      waiting[p.cityId] = (waiting[p.cityId] ?? 0) + 1;
    }
  }
  final licensed = sim.growth.licensedRegions(state);
  return MapScene(
    airports: [
      for (final a in state.airports)
        MapAirport(
          cityId: a.cityId,
          level: a.level,
          waitingPlanes: waiting[a.cityId] ?? 0,
          badgeColor: switch (sim.growth.topPath(a)) {
            final String path => pathColor(path),
            null => null,
          },
        ),
    ],
    flights: [
      for (final f in sim.rivals.flights(state, now)) rivalFlight(config, f),
      for (final p in state.planes)
        if (p.status != PlaneStatus.parked && p.leg != null) mapFlight(p),
    ],
    cityFlags: cityFlags(sim, state),
    weather: [for (final e in state.weather.events) mapWeather(config, e)],
    lockedRegionIds: state.hasStarted
        ? {
            for (final r in config.world.regions)
              if (!licensed.contains(r.id)) r.id,
          }
        : const {},
    routePicker: switch (panel) {
      RoutePanel(:final planeId, :final stops)
          when state.plane(planeId) != null =>
        routePicker(sim, state, state.plane(planeId)!, stops, now),
      _ => null,
    },
    selectedCityId: switch (panel) {
      AirportPanel(:final cityId) || CityPanel(:final cityId) => cityId,
      LoadingPanel(:final planeId) => state.plane(planeId)?.cityId,
      _ => null,
    },
    selectedPlaneId: switch (panel) {
      PlanePanel(:final planeId) => planeId,
      _ => null,
    },
  );
}

MapFlight mapFlight(Plane plane) {
  final leg = plane.leg!;
  return MapFlight(
    planeId: plane.id,
    fromCityId: leg.fromCityId,
    toCityId: leg.toCityId,
    departAt: leg.departAt,
    arriveAt: leg.arriveAt,
    laterStops: plane.remainingStops,
  );
}

/// A rival plane in its airline's livery.
MapFlight rivalFlight(GameConfig config, RivalFlight f) => MapFlight(
  planeId: f.planeId,
  fromCityId: f.fromCityId,
  toCityId: f.toCityId,
  departAt: f.departAt,
  arriveAt: f.arriveAt,
  livery: liveryColor(config.rivals.rival(f.rivalId).color),
  isRival: true,
);

/// The player's flag colour on the map, matching their planes' wings.
const playerFlagColor = Color(0xFFFF9F43);

/// `#RRGGBB` as a colour.
Color liveryColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// The leader's flag for every city someone leads.
Map<String, Color> cityFlags(Simulation sim, GameState state) {
  final rivals = sim.rivals.rules.config.rivals;
  return {
    for (final cityId in state.rivals.cities.keys)
      if (sim.rivals.leaderOf(state, cityId) case final leader?)
        cityId: leader == playerAirlineId
            ? playerFlagColor
            : liveryColor(rivals.rival(leader).color),
  };
}

MapWeather mapWeather(GameConfig config, WeatherEvent e) {
  final type = config.weather.events.firstWhere((t) => t.id == e.typeId);
  final WeatherArea area = switch (type.area) {
    'band' => WeatherBand(
      lat: e.bandLat ?? 0,
      halfWidthDeg: config.weather.bandHalfWidthDeg,
      eastward: e.eastbound ?? true,
    ),
    'cluster' => WeatherCluster(
      lat: config.world.city(e.cityId!).lat,
      lon: config.world.city(e.cityId!).lon,
      radiusKm: config.weather.clusterRadiusKm.toDouble(),
    ),
    _ => WeatherAtCity(e.cityId!),
  };
  return MapWeather(
    id: e.id,
    eventId: e.typeId,
    area: area,
    startsAt: e.startsAt,
    endsAt: e.endsAt,
  );
}

/// Owned airports [plane] can fly to next, after [stops] picked so far.
Set<String> nextStopOptions(
  Simulation sim,
  GameState state,
  Plane plane,
  List<String> stops,
  DateTime now,
) {
  final from = stops.isEmpty ? plane.cityId : stops.last;
  return {
    for (final a in state.airports)
      if (sim.flights.legProblem(state, plane, from, a.cityId, now) == null)
        a.cityId,
  };
}

MapRoutePicker routePicker(
  Simulation sim,
  GameState state,
  Plane plane,
  List<String> stops,
  DateTime now,
) {
  final from = stops.isEmpty ? plane.cityId : stops.last;
  final stats = PlaneStats.of(sim.rules, state, plane);
  return MapRoutePicker(
    originCityId: plane.cityId,
    stops: stops,
    rangeKm: stats.rangeFrom(sim.rules, state.airport(from)),
    reachableCityIds: nextStopOptions(sim, state, plane, stops, now),
  );
}

/// A short fingerprint of what the map draws, so the home screen only hands
/// the map a new scene when something visible changed (a new scene makes
/// the map rebuild its caches).
String sceneKey(MapScene s) {
  final b = StringBuffer();
  for (final a in s.airports) {
    b.write('a${a.cityId}${a.level}/${a.waitingPlanes}${a.badgeColor};');
  }
  for (final f in s.flights) {
    b.write(
      'f${f.planeId}${f.fromCityId}>${f.toCityId}'
      '${f.arriveAt.millisecondsSinceEpoch}${f.laterStops};',
    );
  }
  for (final w in s.weather) {
    b.write('w${w.id}${w.endsAt.millisecondsSinceEpoch};');
  }
  final r = s.routePicker;
  if (r != null) {
    b.write('r${r.originCityId}${r.stops}${r.rangeKm.round()}');
    b.write((r.reachableCityIds.toList()..sort()).join(','));
  }
  b.write('|${(s.lockedRegionIds.toList()..sort()).join(',')}');
  final flags = s.cityFlags.keys.toList()..sort();
  for (final c in flags) {
    b.write('|$c${s.cityFlags[c]!.toARGB32()}');
  }
  b.write('|${s.selectedCityId}|${s.selectedPlaneId}');
  return b.toString();
}
