import 'dart:math' as math;

import 'config_reader.dart';
import 'effect.dart';
import 'planes_config.dart';

/// What an airport of one level offers and what it costs to reach.
class AirportLevel {
  const AirportLevel({
    required this.level,
    required this.gates,
    required this.jobBoardSize,
    required this.maxPlaneClass,
    required this.upgradeCost,
    required this.staffSlots,
    required this.layoverSlots,
  });

  factory AirportLevel.fromConfig(ConfigReader c) => AirportLevel(
    level: c.integer('level'),
    gates: c.integer('gates'),
    jobBoardSize: c.integer('jobBoardSize'),
    maxPlaneClass: c.oneOf('maxPlaneClass', PlaneClass.ids),
    upgradeCost: c.integer('upgradeCost'),
    staffSlots: c.integer('staffSlots'),
    layoverSlots: c.integer('layoverSlots'),
  );

  final int level;

  /// Planes that can be parked or loading at once.
  final int gates;
  final int jobBoardSize;
  final String maxPlaneClass;

  /// Cost to upgrade to this level at a size 3 city (0 for level 1).
  final int upgradeCost;

  final int staffSlots;

  /// Jobs (counted in seats or slots) that can wait here on a layover
  /// before the Layovers path adds more.
  final int layoverSlots;
}

/// One of the four airport upgrade paths, with 3 tiers bought in order.
class UpgradePath {
  const UpgradePath({
    required this.id,
    required this.name,
    required this.tiers,
  });

  factory UpgradePath.fromConfig(ConfigReader c) => UpgradePath(
    id: c.string('id'),
    name: c.string('name'),
    tiers: [for (final t in c.children('tiers')) Effect.fromConfig(t)],
  );

  final String id;
  final String name;
  final List<Effect> tiers;
}

/// `airports.json`: buying airports, airport levels and upgrade paths.
class AirportsConfig {
  const AirportsConfig({
    required this.purchasePriceBySize,
    required this.purchaseNetworkGrowthPerAirport,
    required this.citySizeCostMultiplier,
    required this.extraGatesBySize,
    required this.jobBoardScaleBySize,
    required this.networkJobsPerAirport,
    required this.levels,
    required this.pathTierCosts,
    required this.pathSellRefund,
    required this.airportSellRefund,
    required this.paths,
    required this.longHaulJobWeight,
  });

  factory AirportsConfig.fromConfig(ConfigReader c) {
    final config = AirportsConfig(
      purchasePriceBySize: c.integers('purchasePriceBySize'),
      purchaseNetworkGrowthPerAirport: c.number(
        'purchaseNetworkGrowthPerAirport',
      ),
      citySizeCostMultiplier: c.numbers('citySizeCostMultiplier'),
      extraGatesBySize: c.integers('extraGatesBySize'),
      jobBoardScaleBySize: c.numbers('jobBoardScaleBySize'),
      networkJobsPerAirport: c.number('networkJobsPerAirport'),
      levels: [
        for (final r in c.children('levels')) AirportLevel.fromConfig(r),
      ],
      pathTierCosts: c.integers('pathTierCosts'),
      pathSellRefund: c.number('pathSellRefund'),
      airportSellRefund: c.number('airportSellRefund'),
      paths: [for (final r in c.children('paths')) UpgradePath.fromConfig(r)],
      longHaulJobWeight: c.number('longHaulJobWeight'),
    );
    c.check(
      config.purchasePriceBySize.length == 5,
      'purchasePriceBySize',
      'should have 5 entries, one per city size',
    );
    c.check(
      config.citySizeCostMultiplier.length == 5,
      'citySizeCostMultiplier',
      'should have 5 entries, one per city size',
    );
    c.check(
      config.extraGatesBySize.length == 5,
      'extraGatesBySize',
      'should have 5 entries, one per city size',
    );
    c.check(
      config.jobBoardScaleBySize.length == 5 &&
          config.jobBoardScaleBySize.every((x) => x > 0),
      'jobBoardScaleBySize',
      'should have 5 entries above 0, one per city size',
    );
    for (var i = 0; i < config.levels.length; i++) {
      c.check(
        config.levels[i].level == i + 1,
        'levels[$i].level',
        'should be ${i + 1}',
      );
    }
    for (final path in config.paths) {
      c.check(
        path.tiers.length == config.pathTierCosts.length,
        'paths.${path.id}.tiers',
        'should have ${config.pathTierCosts.length} tiers',
      );
    }
    return config;
  }

  /// Base price by city size; index 0 is size 1.
  final List<int> purchasePriceBySize;

  /// Price grows by this fraction for each airport already owned.
  final double purchaseNetworkGrowthPerAirport;

  /// Upgrade, path and staff costs scale by city size; index 0 is size 1.
  final List<double> citySizeCostMultiplier;

  /// Gates a bigger city adds on top of its airport level's; index 0 is
  /// size 1.
  final List<int> extraGatesBySize;

  /// A level's job board size is multiplied by this for the airport's city
  /// size, so bigger cities have more jobs; index 0 is size 1.
  final List<double> jobBoardScaleBySize;

  /// Jobs every board gains for each airport owned beyond the first (rounded
  /// down, before the city size scale), so boards keep up as jobs spread
  /// across more destinations.
  final double networkJobsPerAirport;
  final List<AirportLevel> levels;
  final List<int> pathTierCosts;
  final double pathSellRefund;

  /// The share of what an airport cost (its purchase price, level upgrades
  /// and path tiers) that selling it pays back.
  final double airportSellRefund;
  final List<UpgradePath> paths;

  /// How much more often Long-haul airports roll cross-region jobs.
  final double longHaulJobWeight;

  int get maxLevel => levels.length;

  AirportLevel level(int level) => levels[level - 1];

  /// `base(size) x (1 + growth x airportsOwned)`.
  int purchasePrice({required int citySize, required int airportsOwned}) =>
      (purchasePriceBySize[citySize - 1] *
              (1 + purchaseNetworkGrowthPerAirport * airportsOwned))
          .round();

  /// Gates at an airport of [level] in a city of [citySize].
  int gates(int level, int citySize) =>
      this.level(level).gates + extraGatesBySize[citySize - 1];

  /// Jobs on the board of an airport of [level] in a city of [citySize] in
  /// a network of [airportsOwned], before crew, rivals and upgrade paths add
  /// theirs. Always at least 1.
  int jobBoardSize(int level, int citySize, {int airportsOwned = 1}) =>
      math.max(
        1,
        ((this.level(level).jobBoardSize +
                    (networkJobsPerAirport * math.max(0, airportsOwned - 1))
                        .floor()) *
                jobBoardScaleBySize[citySize - 1])
            .round(),
      );

  /// Scales a size-3 cost to a city of [citySize].
  int scaledCost(int baseCost, int citySize) =>
      (baseCost * citySizeCostMultiplier[citySize - 1]).round();
}
