import 'config_reader.dart';

/// Every tunable number in the game, loaded from `assets/config/*.json`.
///
/// To add a config file: drop `<name>.json` into `assets/config/`, add its
/// name to [files], and give it a typed class built in [GameConfig.fromFiles].
/// Game code reads typed fields, never raw JSON.
class GameConfig {
  const GameConfig({required this.economy});

  /// Config files to load, by name (without `.json`).
  static const files = ['economy'];

  final EconomyConfig economy;

  factory GameConfig.fromFiles(Map<String, ConfigReader> files) =>
      GameConfig(economy: EconomyConfig.fromConfig(files['economy']!));
}

/// Starting values and pay rates (design doc, Economy section).
class EconomyConfig {
  const EconomyConfig({
    required this.startingMoney,
    required this.startingPlaneModelId,
    required this.homeAirportStartLevel,
    required this.freeNearbyAirports,
    required this.passengerRatePerKm,
    required this.cargoRatePerKm,
    required this.smallCityAirportPrice,
    required this.megaCityAirportPrice,
  });

  final int startingMoney;
  final String startingPlaneModelId;
  final int homeAirportStartLevel;
  final int freeNearbyAirports;
  final double passengerRatePerKm;
  final double cargoRatePerKm;
  final int smallCityAirportPrice;
  final int megaCityAirportPrice;

  factory EconomyConfig.fromConfig(ConfigReader c) {
    final rates = c.child('rates');
    final airportPrice = c.child('airportPrice');
    return EconomyConfig(
      startingMoney: c.integer('startingMoney'),
      startingPlaneModelId: c.string('startingPlaneModelId'),
      homeAirportStartLevel: c.integer('homeAirportStartLevel'),
      freeNearbyAirports: c.integer('freeNearbyAirports'),
      passengerRatePerKm: rates.number('passengerPerKm'),
      cargoRatePerKm: rates.number('cargoPerKm'),
      smallCityAirportPrice: airportPrice.integer('smallCity'),
      megaCityAirportPrice: airportPrice.integer('megaCity'),
    );
  }
}
