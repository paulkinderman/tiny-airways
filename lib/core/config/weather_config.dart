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
  });

  factory WeatherEventConfig.fromConfig(ConfigReader c) {
    final event = WeatherEventConfig(
      id: c.string('id'),
      name: c.string('name'),
      area: c.oneOf('area', areas),
      minMinutes: c.integer('minMinutes'),
      maxMinutes: c.integer('maxMinutes'),
      effects: c.numberMap('effects'),
    );
    c.check(
      event.minMinutes > 0 && event.minMinutes <= event.maxMinutes,
      'minMinutes',
      'should be above 0 and at most maxMinutes',
    );
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
  final double bandHalfWidthDeg;
}
