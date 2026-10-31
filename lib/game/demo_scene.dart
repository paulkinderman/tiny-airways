import 'dart:ui';

import 'map/map_scene.dart';

/// A busy example scene: a North American network, 20 of the player's
/// planes in the air (two across the Pacific), six rival planes and one of
/// each kind of weather. Used by the map's tests, the performance check and
/// for screenshots; the real scene comes from the game state.
MapScene demoScene(DateTime now) {
  DateTime at(int minutes) => now.add(Duration(minutes: minutes));
  MapFlight flight(
    String id,
    String from,
    String to, {
    required int left,
    int total = 20,
    List<String> later = const [],
    Color? livery,
    bool rival = false,
  }) => MapFlight(
    planeId: id,
    fromCityId: from,
    toCityId: to,
    departAt: at(left - total),
    arriveAt: at(left),
    laterStops: later,
    livery: livery,
    isRival: rival,
  );

  return MapScene(
    lockedRegionIds: const {'south_america', 'africa', 'oceania', 'antarctica'},
    airports: const [
      MapAirport(cityId: 'chicago', level: 4, waitingPlanes: 2),
      MapAirport(cityId: 'new_york', level: 3, badgeColor: Color(0xFF3FB27F)),
      MapAirport(cityId: 'toronto', level: 2),
      MapAirport(cityId: 'denver', level: 1),
      MapAirport(cityId: 'atlanta', level: 1, waitingPlanes: 1),
      MapAirport(cityId: 'los_angeles', level: 2),
      MapAirport(cityId: 'london', level: 2),
      MapAirport(cityId: 'tokyo', level: 1),
    ],
    flights: [
      flight('p1', 'chicago', 'new_york', left: 4, later: ['boston']),
      flight('p2', 'denver', 'chicago', left: 11),
      flight('p3', 'atlanta', 'miami', left: 2),
      flight('p4', 'toronto', 'montreal', left: 7, total: 9),
      flight('p5', 'los_angeles', 'tokyo', left: 14, total: 30),
      flight('p6', 'honolulu', 'sydney', left: 20, total: 30),
      flight('p7', 'seattle', 'vancouver', left: 3, total: 5),
      flight('p8', 'houston', 'dallas', left: 5, total: 8),
      flight('p9', 'new_york', 'london', left: 18, total: 28),
      flight('p10', 'london', 'paris', left: 3, total: 6),
      flight('p11', 'chicago', 'minneapolis', left: 6, total: 9),
      flight('p12', 'phoenix', 'las_vegas', left: 1, total: 5),
      flight('p13', 'washington', 'atlanta', left: 8, total: 12),
      flight('p14', 'mexico_city', 'havana', left: 9, total: 14),
      flight('p15', 'tokyo', 'seoul', left: 4, total: 10),
      flight('p16', 'calgary', 'anchorage', left: 15, total: 20),
      flight('p17', 'boston', 'halifax', left: 6, total: 8),
      flight('p18', 'nashville', 'new_orleans', left: 2, total: 7),
      flight('p19', 'san_francisco', 'denver', left: 10, total: 14),
      flight('p20', 'monterrey', 'cancun', left: 12, total: 15),
      for (final (i, (from, to)) in const [
        ('dallas', 'chicago'),
        ('miami', 'washington'),
        ('seattle', 'san_francisco'),
        ('madrid', 'rome'),
        ('toronto', 'new_york'),
        ('berlin', 'stockholm'),
      ].indexed)
        flight(
          'r$i',
          from,
          to,
          left: 3 + i * 2,
          total: 16,
          livery: const Color(0xFFE5484D),
          rival: true,
        ),
    ],
    weather: [
      MapWeather(
        id: 'w1',
        eventId: 'thunderstorm',
        area: const WeatherAtCity('miami'),
        startsAt: at(-5),
        endsAt: at(25),
      ),
      MapWeather(
        id: 'w2',
        eventId: 'fog',
        area: const WeatherAtCity('seattle'),
        startsAt: at(8),
        endsAt: at(38),
      ),
      MapWeather(
        id: 'w3',
        eventId: 'snowstorm',
        area: const WeatherCluster(lat: 46, lon: -99, radiusKm: 800),
        startsAt: at(-10),
        endsAt: at(35),
      ),
      MapWeather(
        id: 'w4',
        eventId: 'heat_wave',
        area: const WeatherCluster(lat: 40, lon: -3.7, radiusKm: 800),
        startsAt: at(6),
        endsAt: at(66),
      ),
      MapWeather(
        id: 'w5',
        eventId: 'jet_stream',
        area: const WeatherBand(lat: 52, halfWidthDeg: 6),
        startsAt: at(-30),
        endsAt: at(90),
      ),
    ],
  );
}

/// The demo network with the route picker open at Chicago, Toronto picked
/// as the first stop and New York as the second.
MapScene demoRouteScene(DateTime now) => demoScene(now).copyWith(
  flights: const [],
  weather: const [],
  routePicker: () => const MapRoutePicker(
    originCityId: 'chicago',
    stops: ['toronto', 'new_york'],
    rangeKm: 1200,
    reachableCityIds: {
      'boston',
      'washington',
      'montreal',
      'chicago',
      'toronto',
      'halifax',
    },
  ),
);
