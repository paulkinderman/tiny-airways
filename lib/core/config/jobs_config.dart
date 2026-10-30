import 'config_reader.dart';

/// A job type with a twist: VIP, fragile, rush, sightseeing or bulk.
class SpecialJobConfig {
  const SpecialJobConfig({
    required this.payMultiplier,
    required this.chancePct,
    this.deadlineMinutes,
    this.requiresRole,
    this.requiresModel,
    this.slots = 1,
  });

  factory SpecialJobConfig.fromConfig(ConfigReader c) => SpecialJobConfig(
    payMultiplier: c.number('payMultiplier'),
    chancePct: c.number('chancePct'),
    deadlineMinutes: c.has('deadlineMinutes')
        ? c.integer('deadlineMinutes')
        : null,
    requiresRole: c.has('requiresRole') ? c.string('requiresRole') : null,
    requiresModel: c.has('requiresModel') ? c.string('requiresModel') : null,
    slots: c.has('slots') ? c.integer('slots') : 1,
  );

  final double payMultiplier;

  /// Chance that a newly rolled job is this kind, where it can appear.
  final double chancePct;
  final int? deadlineMinutes;
  final String? requiresRole;
  final String? requiresModel;

  /// Seats or cargo slots one job takes.
  final int slots;
}

/// `jobs.json`: job boards, loading bonuses and special jobs.
class JobsConfig {
  const JobsConfig({
    required this.boardRotationMinutes,
    required this.refreshCostPerCitySize,
    required this.cargoShare,
    required this.destinationWeightBySize,
    required this.minJobDistanceKm,
    required this.charterBonusPct,
    required this.fullHoldBonusPct,
    required this.airlineXpPerCoin,
    required this.special,
    required this.partCrateOneIn,
  });

  factory JobsConfig.fromConfig(ConfigReader c) {
    final special = c.child('special');
    final config = JobsConfig(
      boardRotationMinutes: c.integer('boardRotationMinutes'),
      refreshCostPerCitySize: c.integer('refreshCostPerCitySize'),
      cargoShare: c.number('cargoShare'),
      destinationWeightBySize: c.numbers('destinationWeightBySize'),
      minJobDistanceKm: c.integer('minJobDistanceKm'),
      charterBonusPct: c.number('charterBonusPct'),
      fullHoldBonusPct: c.number('fullHoldBonusPct'),
      airlineXpPerCoin: c.number('airlineXpPerCoin'),
      special: {
        for (final kind in specialKinds)
          kind: SpecialJobConfig.fromConfig(special.child(kind)),
      },
      partCrateOneIn: c.integer('partCrateOneIn'),
    );
    c.check(
      config.cargoShare >= 0 && config.cargoShare <= 1,
      'cargoShare',
      'should be 0 to 1',
    );
    c.check(
      config.destinationWeightBySize.length == 5,
      'destinationWeightBySize',
      'should have 5 entries, one per city size',
    );
    return config;
  }

  static const specialKinds = ['vip', 'fragile', 'rush', 'sightseeing', 'bulk'];

  final int boardRotationMinutes;

  /// Paid refresh costs this x city size.
  final int refreshCostPerCitySize;

  /// Fraction of generated jobs that are cargo.
  final double cargoShare;

  /// How likely each city size is to be a job's destination; index 0 is
  /// size 1.
  final List<double> destinationWeightBySize;
  final int minJobDistanceKm;
  final double charterBonusPct;
  final double fullHoldBonusPct;

  /// Airline XP per coin of delivered payout.
  final double airlineXpPerCoin;
  final Map<String, SpecialJobConfig> special;

  /// About 1 in this many cargo jobs is a part crate (from the unlock level).
  final int partCrateOneIn;

  Duration get boardRotation => Duration(minutes: boardRotationMinutes);
}
