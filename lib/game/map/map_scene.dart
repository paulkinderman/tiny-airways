import 'dart:ui';

/// Everything the world map shows that changes during play, built by the
/// screens from the game state. The map only draws it; tapping reports back
/// through callbacks and never changes game state itself.
///
/// Positions in time (flights, weather) are timestamps, and the map reads the
/// [Clock] every frame, so planes move and countdowns tick without a new
/// scene.
class MapScene {
  const MapScene({
    this.airports = const [],
    this.flights = const [],
    this.weather = const [],
    this.lockedRegionIds = const {},
    this.routePicker,
    this.selectedCityId,
    this.selectedPlaneId,
  });

  /// The player's airports.
  final List<MapAirport> airports;

  /// Planes in the air, the player's and rivals'.
  final List<MapFlight> flights;

  /// Weather events, forecast or active.
  final List<MapWeather> weather;

  /// Regions the player has no license for yet; their land is drawn muted.
  final Set<String> lockedRegionIds;

  /// Set while the player is choosing where a plane goes.
  final MapRoutePicker? routePicker;

  final String? selectedCityId;
  final String? selectedPlaneId;

  MapScene copyWith({
    List<MapAirport>? airports,
    List<MapFlight>? flights,
    List<MapWeather>? weather,
    Set<String>? lockedRegionIds,
    MapRoutePicker? Function()? routePicker,
    String? Function()? selectedCityId,
    String? Function()? selectedPlaneId,
  }) => MapScene(
    airports: airports ?? this.airports,
    flights: flights ?? this.flights,
    weather: weather ?? this.weather,
    lockedRegionIds: lockedRegionIds ?? this.lockedRegionIds,
    routePicker: routePicker != null ? routePicker() : this.routePicker,
    selectedCityId: selectedCityId != null
        ? selectedCityId()
        : this.selectedCityId,
    selectedPlaneId: selectedPlaneId != null
        ? selectedPlaneId()
        : this.selectedPlaneId,
  );
}

/// An airport the player owns.
class MapAirport {
  const MapAirport({
    required this.cityId,
    required this.level,
    this.waitingPlanes = 0,
    this.badgeColor,
  });

  final String cityId;

  /// 1 to 5; bigger levels get bigger pins.
  final int level;

  /// Planes parked here waiting to be dispatched.
  final int waitingPlanes;

  /// The colour of the airport's top upgrade path, shown as a small badge.
  final Color? badgeColor;
}

/// A plane flying one leg.
class MapFlight {
  const MapFlight({
    required this.planeId,
    required this.fromCityId,
    required this.toCityId,
    required this.departAt,
    required this.arriveAt,
    this.laterStops = const [],
    this.livery,
    this.isRival = false,
  });

  final String planeId;
  final String fromCityId;
  final String toCityId;
  final DateTime departAt;
  final DateTime arriveAt;

  /// Cities queued after [toCityId], drawn as a dotted trail.
  final List<String> laterStops;

  /// Wing colour; defaults to the player's orange.
  final Color? livery;

  /// Rival planes are smaller, have no countdown and can't be selected.
  final bool isRival;
}

/// Where a weather event sits.
sealed class WeatherArea {
  const WeatherArea();
}

/// Over one airport (thunderstorm, fog).
class WeatherAtCity extends WeatherArea {
  const WeatherAtCity(this.cityId);
  final String cityId;
}

/// A circle of cities (snowstorm, heat wave).
class WeatherCluster extends WeatherArea {
  const WeatherCluster({
    required this.lat,
    required this.lon,
    required this.radiusKm,
  });
  final double lat;
  final double lon;
  final double radiusKm;
}

/// A band of latitude right round the world (jet stream).
class WeatherBand extends WeatherArea {
  const WeatherBand({
    required this.lat,
    required this.halfWidthDeg,
    this.eastward = true,
  });
  final double lat;
  final double halfWidthDeg;

  /// Which way the wind blows.
  final bool eastward;
}

/// A weather event. Before [startsAt] it shows as a forecast with a
/// countdown; from [startsAt] to [endsAt] it is active.
class MapWeather {
  const MapWeather({
    required this.id,
    required this.eventId,
    required this.area,
    required this.startsAt,
    required this.endsAt,
  });

  final String id;

  /// The id from `config/weather.json`: thunderstorm, fog, snowstorm,
  /// heat_wave or jet_stream.
  final String eventId;
  final WeatherArea area;
  final DateTime startsAt;
  final DateTime endsAt;

  bool isForecastAt(DateTime now) => now.isBefore(startsAt);
  bool isOverAt(DateTime now) => !now.isBefore(endsAt);
}

/// The route picker: the plane's range from its last stop, the airports it
/// can reach, and the stops picked so far.
class MapRoutePicker {
  const MapRoutePicker({
    required this.originCityId,
    required this.rangeKm,
    this.stops = const [],
    this.reachableCityIds = const {},
  });

  final String originCityId;

  /// Stops picked so far, in order.
  final List<String> stops;

  /// The plane's range, drawn as a ring round the last stop.
  final double rangeKm;

  /// Airports the next stop can be (worked out by the rules, not the map).
  final Set<String> reachableCityIds;

  String get rangeCentreCityId => stops.isEmpty ? originCityId : stops.last;
}

/// What a tap on the map landed on.
sealed class MapHit {
  const MapHit();
}

class PlaneHit extends MapHit {
  const PlaneHit(this.planeId);
  final String planeId;
}

class CityHit extends MapHit {
  const CityHit(this.cityId);
  final String cityId;
}

class WeatherHit extends MapHit {
  const WeatherHit(this.weatherId);
  final String weatherId;
}
