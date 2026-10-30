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
    required this.upgradePoints,
    required this.staffSlots,
  });

  factory AirportLevel.fromConfig(ConfigReader c) => AirportLevel(
    level: c.integer('level'),
    gates: c.integer('gates'),
    jobBoardSize: c.integer('jobBoardSize'),
    maxPlaneClass: c.oneOf('maxPlaneClass', PlaneClass.ids),
    upgradeCost: c.integer('upgradeCost'),
    upgradePoints: c.integer('upgradePoints'),
    staffSlots: c.integer('staffSlots'),
  );

  final int level;

  /// Planes that can be parked or loading at once.
  final int gates;
  final int jobBoardSize;
  final String maxPlaneClass;

  /// Cost to upgrade to this level at a size 3 city (0 for level 1).
  final int upgradeCost;

  /// Total upgrade points an airport of this level has.
  final int upgradePoints;
  final int staffSlots;
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
    required this.levels,
    required this.pathTierCosts,
    required this.pathTierPointCost,
    required this.pathSellRefund,
    required this.paths,
    required this.longHaulJobWeight,
    required this.codeshareTransferXp,
  });

  factory AirportsConfig.fromConfig(ConfigReader c) {
    final config = AirportsConfig(
      purchasePriceBySize: c.integers('purchasePriceBySize'),
      purchaseNetworkGrowthPerAirport: c.number(
        'purchaseNetworkGrowthPerAirport',
      ),
      citySizeCostMultiplier: c.numbers('citySizeCostMultiplier'),
      levels: [
        for (final r in c.children('levels')) AirportLevel.fromConfig(r),
      ],
      pathTierCosts: c.integers('pathTierCosts'),
      pathTierPointCost: c.integer('pathTierPointCost'),
      pathSellRefund: c.number('pathSellRefund'),
      paths: [for (final r in c.children('paths')) UpgradePath.fromConfig(r)],
      longHaulJobWeight: c.number('longHaulJobWeight'),
      codeshareTransferXp: c.integer('codeshareTransferXp'),
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
  final List<AirportLevel> levels;
  final List<int> pathTierCosts;
  final int pathTierPointCost;
  final double pathSellRefund;
  final List<UpgradePath> paths;

  /// How much more often Long-haul airports roll cross-region jobs.
  final double longHaulJobWeight;

  /// Bonus crew XP per transfer at a Codeshare airport.
  final int codeshareTransferXp;

  int get maxLevel => levels.length;

  AirportLevel level(int level) => levels[level - 1];

  /// `base(size) x (1 + growth x airportsOwned)`.
  int purchasePrice({required int citySize, required int airportsOwned}) =>
      (purchasePriceBySize[citySize - 1] *
              (1 + purchaseNetworkGrowthPerAirport * airportsOwned))
          .round();

  /// Scales a size-3 cost to a city of [citySize].
  int scaledCost(int baseCost, int citySize) =>
      (baseCost * citySizeCostMultiplier[citySize - 1]).round();
}
