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
    required this.jobLifetimeRotations,
    required this.refreshCostPerCitySize,
    required this.cargoShare,
    required this.destinationWeightBySize,
    required this.destinationWeightByLevel,
    required this.minJobDistanceKm,
    required this.gravityKm,
    required this.hotDestinations,
    required this.destinationsPerHot,
    required this.hotShare,
    required this.hotRotations,
    required this.groupChancePctPerSeat,
    required this.groupMaxChancePct,
    required this.groupSeatsPerSize,
    required this.groupMaxSize,
    required this.charterChancePct,
    required this.connectionExpiryMinutes,
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
      jobLifetimeRotations: c.integer('jobLifetimeRotations'),
      refreshCostPerCitySize: c.integer('refreshCostPerCitySize'),
      cargoShare: c.number('cargoShare'),
      destinationWeightBySize: c.numbers('destinationWeightBySize'),
      destinationWeightByLevel: c.numbers('destinationWeightByLevel'),
      minJobDistanceKm: c.integer('minJobDistanceKm'),
      gravityKm: c.number('gravityKm'),
      hotDestinations: c.integer('hotDestinations'),
      destinationsPerHot: c.integer('destinationsPerHot'),
      hotShare: c.number('hotShare'),
      hotRotations: c.integer('hotRotations'),
      groupChancePctPerSeat: c.number('groupChancePctPerSeat'),
      groupMaxChancePct: c.number('groupMaxChancePct'),
      groupSeatsPerSize: c.integer('groupSeatsPerSize'),
      groupMaxSize: c.integer('groupMaxSize'),
      charterChancePct: c.number('charterChancePct'),
      connectionExpiryMinutes: c.integer('connectionExpiryMinutes'),
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
      config.jobLifetimeRotations >= 1,
      'jobLifetimeRotations',
      'should be at least 1',
    );
    c.check(
      config.destinationWeightByLevel.length == 5,
      'destinationWeightByLevel',
      'should have 5 entries, one per airport level',
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

  /// Rotations a job waits on a board before it leaves. Each rotation brings
  /// a batch of about 1 / this of the board's size.
  final int jobLifetimeRotations;

  /// Paid refresh costs this x city size.
  final int refreshCostPerCitySize;

  /// Fraction of generated jobs that are cargo.
  final double cargoShare;

  /// How likely each city size is to be a job's destination; index 0 is
  /// size 1.
  final List<double> destinationWeightBySize;

  /// How much more likely a destination is for each level of its airport;
  /// index 0 is level 1.
  final List<double> destinationWeightByLevel;
  final int minJobDistanceKm;

  /// Distance at which a destination's pull halves: nearer cities get more
  /// jobs, like real air traffic.
  final double gravityKm;

  /// Most hot destinations a board has at once.
  final int hotDestinations;

  /// A board gets one hot destination per this many destinations it can
  /// send jobs to (at least 1, at most [hotDestinations]).
  final int destinationsPerHot;

  /// Share of a board's jobs that go to its hot destinations.
  final double hotShare;

  /// Hot destinations stay hot for this many rotations.
  final int hotRotations;

  /// Chance a passenger job is a group booking, per seat of the biggest
  /// passenger plane that can use the airport.
  final double groupChancePctPerSeat;

  /// Cap on that chance.
  final double groupMaxChancePct;

  /// Groups can be one seat bigger per this many seats of that plane.
  final int groupSeatsPerSize;

  /// Biggest group booking.
  final int groupMaxSize;

  /// Chance a rotation tops up one hot destination with enough jobs to fill
  /// a plane that can use the airport, seats and hold.
  final double charterChancePct;

  /// Jobs waiting on a board to connect are dropped after this long, unless
  /// the airport has the Codeshare tier.
  final int connectionExpiryMinutes;
  final double charterBonusPct;
  final double fullHoldBonusPct;

  /// Airline XP per coin of delivered payout.
  final double airlineXpPerCoin;
  final Map<String, SpecialJobConfig> special;

  /// About 1 in this many cargo jobs is a part crate (from the unlock level).
  final int partCrateOneIn;

  Duration get boardRotation => Duration(minutes: boardRotationMinutes);
}
