import 'config_reader.dart';

/// `extras.json`: plane parts and challenge rewards.
class ExtrasConfig {
  const ExtrasConfig({
    required this.partKinds,
    required this.duplicatePartSellPrice,
    required this.partBuiltPlanes,
    required this.challenges,
  });

  factory ExtrasConfig.fromConfig(ConfigReader c) {
    final parts = c.child('parts');
    return ExtrasConfig(
      partKinds: parts.list<String>('kinds'),
      duplicatePartSellPrice: parts.integer('duplicateSellPrice'),
      partBuiltPlanes: parts.list<String>('specialPlanes'),
      challenges: ChallengesConfig.fromConfig(c.child('challenges')),
    );
  }

  /// One of each builds a special plane.
  final List<String> partKinds;
  final int duplicatePartSellPrice;

  /// Special plane model ids built from parts.
  final List<String> partBuiltPlanes;
  final ChallengesConfig challenges;
}

class ChallengesConfig {
  const ChallengesConfig({
    required this.dailyCount,
    required this.dailyFreeRerolls,
    required this.dailyXpFractionOfLevel,
    required this.dailyMoneyPerLevel,
    required this.weeklyMultiplier,
    required this.milestoneMultiplier,
  });

  factory ChallengesConfig.fromConfig(ConfigReader c) => ChallengesConfig(
    dailyCount: c.integer('dailyCount'),
    dailyFreeRerolls: c.integer('dailyFreeRerolls'),
    dailyXpFractionOfLevel: c.number('dailyXpFractionOfLevel'),
    dailyMoneyPerLevel: c.integer('dailyMoneyPerLevel'),
    weeklyMultiplier: c.number('weeklyMultiplier'),
    milestoneMultiplier: c.number('milestoneMultiplier'),
  );

  final int dailyCount;
  final int dailyFreeRerolls;

  /// A daily pays this fraction of the current level's XP bar.
  final double dailyXpFractionOfLevel;
  final int dailyMoneyPerLevel;

  /// Weekly and milestone rewards are this many dailies.
  final double weeklyMultiplier;
  final double milestoneMultiplier;
}
