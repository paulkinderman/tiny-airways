import 'config_reader.dart';

/// `flights.json`: how game distances turn into real flight time.
class FlightsConfig {
  const FlightsConfig({
    required this.timeCompression,
    required this.minFlightSeconds,
    required this.routeCurveFactor,
    required this.holdingPatternCheckSeconds,
  });

  factory FlightsConfig.fromConfig(ConfigReader c) {
    final config = FlightsConfig(
      timeCompression: c.number('timeCompression'),
      minFlightSeconds: c.integer('minFlightSeconds'),
      routeCurveFactor: c.number('routeCurveFactor'),
      holdingPatternCheckSeconds: c.integer('holdingPatternCheckSeconds'),
    );
    c.check(config.timeCompression > 0, 'timeCompression', 'should be above 0');
    return config;
  }

  /// Scheduled flight hours per real hour.
  final double timeCompression;
  final int minFlightSeconds;

  /// How far the drawn route bows away from a straight line, as a fraction
  /// of its length.
  final double routeCurveFactor;
  final int holdingPatternCheckSeconds;

  /// Scheduled hours for a leg, before any speed bonuses.
  double scheduledHours(double distanceKm, double speedKmh) =>
      distanceKm / speedKmh;

  /// Real time the leg takes on the clock.
  Duration realDuration(double distanceKm, double speedKmh) {
    final seconds =
        scheduledHours(distanceKm, speedKmh) * 3600 / timeCompression;
    return Duration(
      seconds: seconds < minFlightSeconds ? minFlightSeconds : seconds.round(),
    );
  }
}
