import 'config_reader.dart';

/// One kind of weather event, such as a thunderstorm.
class WeatherEventConfig {
  const WeatherEventConfig({
    required this.id,
    required this.name,
    required this.area,
    required this.minMinutes,
    required this.maxMinutes,
    required this.effects,
    this.weight = 1,
  });

  factory WeatherEventConfig.fromConfig(ConfigReader c) {
    final event = WeatherEventConfig(
      id: c.string('id'),
      name: c.string('name'),
      area: c.oneOf('area', areas),
      minMinutes: c.integer('minMinutes'),
      maxMinutes: c.integer('maxMinutes'),
      effects: c.numberMap('effects'),
      weight: c.has('weight') ? c.number('weight') : 1,
    );
    c.check(
      event.minMinutes > 0 && event.minMinutes <= event.maxMinutes,
      'minMinutes',
      'should be above 0 and at most maxMinutes',
    );
    c.check(event.weight > 0, 'weight', 'should be above 0');
    return event;
  }

  /// One airport, a cluster of nearby cities, or a band across a continent.
  static const areas = ['airport', 'cluster', 'band'];

  final String id;
  final String name;
  final String area;
  final int minMinutes;
  final int maxMinutes;

  /// Numbers the weather rules read by key, such as `minCaptainLevel`.
  final Map<String, double> effects;

  /// How likely this event is to be rolled, relative to the other events'
  /// weights. Defaults to 1.
  final double weight;

  bool get closesAirport => (effects['closesAirport'] ?? 0) > 0;
}

/// `weather.json`.
class WeatherConfig {
  const WeatherConfig({
    required this.minIntervalMinutes,
    required this.maxIntervalMinutes,
    required this.forecastMinutes,
    required this.events,
    required this.clusterRadiusKm,
    required this.bandHalfWidthDeg,
  });

  factory WeatherConfig.fromConfig(ConfigReader c) => WeatherConfig(
    minIntervalMinutes: c.integer('minIntervalMinutes'),
    maxIntervalMinutes: c.integer('maxIntervalMinutes'),
    forecastMinutes: c.integer('forecastMinutes'),
    events: [
      for (final r in c.children('events')) WeatherEventConfig.fromConfig(r),
    ],
    clusterRadiusKm: c.integer('clusterRadiusKm'),
    bandHalfWidthDeg: c.number('bandHalfWidthDeg'),
  );

  final int minIntervalMinutes;
  final int maxIntervalMinutes;
  final int forecastMinutes;
  final List<WeatherEventConfig> events;
  final int clusterRadiusKm;

  /// The share of rolled events that close an airport, from 0 to 1.
  double get closureShare {
    final total = events.fold(0.0, (sum, e) => sum + e.weight);
    final closing = events
        .where((e) => e.closesAirport)
        .fold(0.0, (sum, e) => sum + e.weight);
    return closing / total;
  }

  /// Average minutes between airport closures on one continent.
  double get averageMinutesBetweenClosures =>
      (minIntervalMinutes + maxIntervalMinutes) / 2 / closureShare;
  final double bandHalfWidthDeg;
}
