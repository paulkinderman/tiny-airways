import 'config_reader.dart';

/// `extras.json`: plane parts, sightseeing tours, challenges and milestones.
class ExtrasConfig {
  const ExtrasConfig({
    required this.partKinds,
    required this.duplicatePartSellPrice,
    required this.partBuiltPlanes,
    required this.newPartChancePct,
    required this.sightseeingTourKm,
    required this.challenges,
    required this.milestones,
  });

  factory ExtrasConfig.fromConfig(ConfigReader c) {
    final parts = c.child('parts');
    final milestones = [
      for (final m in c.children('milestones')) MilestoneDef.fromConfig(m),
    ];
    final config = ExtrasConfig(
      partKinds: parts.list<String>('kinds'),
      duplicatePartSellPrice: parts.integer('duplicateSellPrice'),
      partBuiltPlanes: parts.list<String>('specialPlanes'),
      newPartChancePct: parts.number('newPartChancePct'),
      sightseeingTourKm: c.child('sightseeing').number('tourKm'),
      challenges: ChallengesConfig.fromConfig(c.child('challenges')),
      milestones: milestones,
    );
    c.check(
      config.newPartChancePct >= 0 && config.newPartChancePct <= 100,
      'parts.newPartChancePct',
      'should be 0 to 100',
    );
    c.check(
      config.sightseeingTourKm > 0,
      'sightseeing.tourKm',
      'should be above 0',
    );
    final ids = <String>{};
    for (final m in milestones) {
      c.check(ids.add(m.id), 'milestones', 'has the id "${m.id}" twice');
    }
    return config;
  }

  /// One of each builds a special plane.
  final List<String> partKinds;
  final int duplicatePartSellPrice;

  /// Special plane model ids built from parts.
  final List<String> partBuiltPlanes;

  /// Chance a crate holds a part the player is still missing.
  final double newPartChancePct;

  /// A sightseeing job pays like a passenger job this long.
  final double sightseeingTourKm;
  final ChallengesConfig challenges;
  final List<MilestoneDef> milestones;

  /// Every part id, such as `barnstormer.engine`, in collection order.
  List<String> get partIds => [
    for (final plane in partBuiltPlanes)
      for (final kind in partKinds) partId(plane, kind),
  ];

  /// Every metric a challenge or milestone can count. Counted ones are
  /// added up as things happen; the rest are read from the state.
  static const countedMetrics = {
    'cargoDelivered',
    'passengersDelivered',
    'jobsDelivered',
    'charters',
    'fullHolds',
    'badWeatherLandings',
    'connections',
    'multiStopTrips',
    'crossRegionDeliveries',
    'specialDeliveries',
    'vipDeliveries',
    'sightseeingTours',
    'landings',
    'kmFlown',
    'moneyEarned',
    'partsCollected',
    'dailiesClaimed',
    'weekliesClaimed',
    // Recorded by rivals (package 11).
    'terminalsBuilt',
    'terminalsTakenFromJumbos',
    'contractsWon',
  };

  /// Metrics where the best single value counts, not the total.
  static const bestMetrics = {'bestLandingPay', 'topCrewLevel'};

  /// Metrics read from the state when checked.
  static const stateMetrics = {
    'airlineLevel',
    'airportsOwned',
    'continentsOwned',
    'topAirportLevel',
    'planesOwned',
    'specialPlanesBuilt',
  };

  static bool isMetric(String id) =>
      countedMetrics.contains(id) ||
      bestMetrics.contains(id) ||
      stateMetrics.contains(id);

  static String partId(String planeId, String kind) => '$planeId.$kind';

  /// The special plane a part id belongs to.
  static String planeOfPart(String partId) => partId.split('.').first;

  static String kindOfPart(String partId) => partId.split('.').last;

  MilestoneDef? milestone(String id) {
    for (final m in milestones) {
      if (m.id == id) return m;
    }
    return null;
  }
}

class ChallengesConfig {
  const ChallengesConfig({
    required this.dailyCount,
    required this.dailyFreeRerolls,
    required this.dailyXpFractionOfLevel,
    required this.dailyMoneyPerLevel,
    required this.weeklyMultiplier,
    required this.milestoneMultiplier,
    required this.weeklyCrewXp,
    required this.badWeather,
    required this.daily,
    required this.weekly,
  });

  factory ChallengesConfig.fromConfig(ConfigReader c) {
    final config = ChallengesConfig(
      dailyCount: c.integer('dailyCount'),
      dailyFreeRerolls: c.integer('dailyFreeRerolls'),
      dailyXpFractionOfLevel: c.number('dailyXpFractionOfLevel'),
      dailyMoneyPerLevel: c.integer('dailyMoneyPerLevel'),
      weeklyMultiplier: c.number('weeklyMultiplier'),
      milestoneMultiplier: c.number('milestoneMultiplier'),
      weeklyCrewXp: c.integer('weeklyCrewXp'),
      badWeather: c.list<String>('badWeather'),
      daily: [for (final d in c.children('daily')) ChallengeDef.fromConfig(d)],
      weekly: [
        for (final d in c.children('weekly')) ChallengeDef.fromConfig(d),
      ],
    );
    c.check(
      config.daily.length > config.dailyCount,
      'daily',
      'needs more challenges than dailyCount, so a finished one can be '
          'replaced',
    );
    c.check(config.weekly.isNotEmpty, 'weekly', 'is empty');
    final ids = <String>{};
    for (final d in [...config.daily, ...config.weekly]) {
      c.check(ids.add(d.id), 'daily', 'has the id "${d.id}" twice');
    }
    return config;
  }

  final int dailyCount;
  final int dailyFreeRerolls;

  /// A daily pays this fraction of the current level's XP bar.
  final double dailyXpFractionOfLevel;
  final int dailyMoneyPerLevel;

  /// Weekly and milestone rewards are this many dailies.
  final double weeklyMultiplier;
  final double milestoneMultiplier;

  /// Crew XP for the whole roster from a weekly before part crates unlock.
  final int weeklyCrewXp;

  /// Weather types a landing counts as "in bad weather" under.
  final List<String> badWeather;
  final List<ChallengeDef> daily;
  final List<ChallengeDef> weekly;

  ChallengeDef? def(String id) {
    for (final d in [...daily, ...weekly]) {
      if (d.id == id) return d;
    }
    return null;
  }
}

/// A daily or weekly challenge in the pool.
class ChallengeDef {
  const ChallengeDef({
    required this.id,
    required this.text,
    required this.metric,
    required this.target,
    this.targetPerLevel = 0,
    this.requiresFeature,
    this.requiresPlane,
    this.requiresAirportsInRegions = 0,
  });

  factory ChallengeDef.fromConfig(ConfigReader c) {
    final def = ChallengeDef(
      id: c.string('id'),
      text: c.string('text'),
      metric: c.string('metric'),
      target: c.number('target'),
      targetPerLevel: c.has('targetPerLevel') ? c.number('targetPerLevel') : 0,
      requiresFeature: c.has('requiresFeature')
          ? c.string('requiresFeature')
          : null,
      requiresPlane: c.has('requiresPlane') ? c.string('requiresPlane') : null,
      requiresAirportsInRegions: c.has('requiresAirportsInRegions')
          ? c.integer('requiresAirportsInRegions')
          : 0,
    );
    c.check(def.target > 0, 'target', 'should be above 0');
    return def;
  }

  final String id;

  /// What the board shows; `{n}` becomes the target.
  final String text;

  /// What it counts (see docs/extras.md).
  final String metric;
  final double target;
  final double targetPerLevel;

  /// Only rolled once this feature is unlocked.
  final String? requiresFeature;

  /// Only rolled while the player owns this plane model.
  final String? requiresPlane;

  /// Only rolled once the player has airports on this many continents.
  final int requiresAirportsInRegions;
}

/// A one-off goal, tracked from the start.
class MilestoneDef {
  const MilestoneDef({
    required this.id,
    required this.text,
    required this.metric,
    required this.target,
    this.unlock,
  });

  factory MilestoneDef.fromConfig(ConfigReader c) {
    final def = MilestoneDef(
      id: c.string('id'),
      text: c.string('text'),
      metric: c.string('metric'),
      target: c.integer('target'),
      unlock: c.has('unlock') ? c.string('unlock') : null,
    );
    c.check(def.target > 0, 'target', 'should be above 0');
    return def;
  }

  final String id;
  final String text;
  final String metric;
  final int target;

  /// What else it gives: `badge:<name>`, `livery:<name>` or `veteran` (a
  /// named veteran on the hire shelf). Later packages read these from
  /// `ExtrasState.unlocks`.
  final String? unlock;
}
