import 'dart:math' as math;

import 'config_reader.dart';

/// A continent. The player starts on one and buys licenses for the rest.
class Region {
  const Region({
    required this.id,
    required this.name,
    required this.startLabel,
    required this.outboundPayMultiplier,
    required this.hardMode,
  });

  factory Region.fromConfig(ConfigReader c) => Region(
    id: c.string('id'),
    name: c.string('name'),
    startLabel: c.string('startLabel'),
    outboundPayMultiplier: c.number('outboundPayMultiplier'),
    hardMode: c.boolean('hardMode'),
  );

  final String id;
  final String name;

  /// Shown on the starting continent picker ("Easy", "Hard", ...).
  final String startLabel;

  /// Pay multiplier for legs that leave this region (Antarctica pays big).
  final double outboundPayMultiplier;

  /// Starting here shifts every rival up one tier.
  final bool hardMode;
}

/// A real city on the world map (`assets/data/cities.json`).
class City {
  const City({
    required this.id,
    required this.name,
    required this.country,
    required this.regionId,
    required this.lat,
    required this.lon,
    required this.size,
    required this.population,
  });

  factory City.fromConfig(ConfigReader c) {
    final city = City(
      id: c.string('id'),
      name: c.string('name'),
      country: c.string('country'),
      regionId: c.string('regionId'),
      lat: c.number('lat'),
      lon: c.number('lon'),
      size: c.integer('size'),
      population: c.integer('population'),
    );
    c.check(city.lat >= -90 && city.lat <= 90, 'lat', 'should be -90 to 90');
    c.check(
      city.lon >= -180 && city.lon <= 180,
      'lon',
      'should be -180 to 180',
    );
    c.check(city.size >= 1 && city.size <= 5, 'size', 'should be 1 to 5');
    c.check(city.population > 0, 'population', 'should be above 0');
    return city;
  }

  final String id;
  final String name;

  /// ISO 3166 alpha-2 code ("AQ" for Antarctic stations).
  final String country;
  final String regionId;
  final double lat;
  final double lon;

  /// 1 (small) to 5 (mega).
  final int size;

  /// Metro population; drives how many jobs the city generates.
  final int population;
}

/// Every region and city, with lookups and distances.
class WorldData {
  WorldData({
    required this.regions,
    required this.cities,
    required this.crossRegionPayPct,
  }) : _regions = {for (final r in regions) r.id: r},
       _cities = {for (final c in cities) c.id: c};

  final List<Region> regions;
  final List<City> cities;

  /// Distance bonus for legs between two regions.
  final double crossRegionPayPct;
  final Map<String, Region> _regions;
  final Map<String, City> _cities;

  static const earthRadiusKm = 6371.0;

  Region region(String id) =>
      _regions[id] ?? (throw ArgumentError.value(id, 'id', 'unknown region'));

  City city(String id) =>
      _cities[id] ?? (throw ArgumentError.value(id, 'id', 'unknown city'));

  bool hasRegion(String id) => _regions.containsKey(id);

  bool hasCity(String id) => _cities.containsKey(id);

  List<City> citiesIn(String regionId) => [
    for (final c in cities)
      if (c.regionId == regionId) c,
  ];

  /// Great-circle ("straight-line") distance in km, used for pay, fuel,
  /// range and flight time.
  static double distanceKm(City a, City b) {
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(b.lat - a.lat);
    final dLon = rad(b.lon - a.lon);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.lat)) *
            math.cos(rad(b.lat)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.sqrt(h));
  }

  /// Other cities in [city]'s region within [km], nearest first.
  List<City> neighboursWithin(City city, double km) {
    final near = [
      for (final c in citiesIn(city.regionId))
        if (c.id != city.id && distanceKm(city, c) <= km) c,
    ]..sort((a, b) => distanceKm(city, a).compareTo(distanceKm(city, b)));
    return near;
  }
}
