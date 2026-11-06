import 'dart:math' as math;

import '../core/state/game_state.dart';
import 'economy.dart';
import 'rivals.dart';
import 'rng.dart';
import 'rules.dart';
import 'weather.dart';

/// Job boards: what appears on them, the 5-minute rotation and the paid
/// refresh.
class JobBoards {
  const JobBoards(this.rules);

  final Rules rules;

  Duration get _rotation => rules.config.jobs.boardRotation;

  /// Boards rotate together on fixed 5-minute marks; this numbers them.
  int rotationIndex(DateTime t) =>
      t.millisecondsSinceEpoch ~/ _rotation.inMilliseconds;

  DateTime rotationTime(int index) => DateTime.fromMillisecondsSinceEpoch(
    index * _rotation.inMilliseconds,
    isUtc: true,
  );

  /// When boards next rotate.
  DateTime nextRotationAt(GameState state) =>
      rotationTime(state.boardRotation + 1);

  /// How many passenger and cargo jobs [airport]'s board holds, not counting
  /// jobs waiting to connect.
  ({int passenger, int cargo}) boardSize(
    GameState state,
    AirportState airport,
  ) {
    final base =
        rules.config.airports.jobBoardSize(
          airport.level,
          rules.world.city(airport.cityId).size,
          airportsOwned: state.airports.length,
        ) +
        rules.crew.extraBoardSlots(state, airport.cityId) +
        Rivals(rules).extraBoardSlots(state, airport.cityId);
    final cargo = (base * rules.config.jobs.cargoShare).round();
    return (
      passenger:
          base -
          cargo +
          rules.pathEffect(airport, 'passengerBoardSlots').round(),
      cargo: cargo + rules.pathEffect(airport, 'cargoBoardSlots').round(),
    );
  }

  /// What a paid refresh costs at [cityId]. With [state], the terminal's
  /// Gates discount counts.
  int refreshCost(String cityId, [GameState? state]) {
    final full =
        rules.config.jobs.refreshCostPerCitySize *
        rules.world.city(cityId).size;
    if (state == null) return full;
    final pct = Rivals(rules).refreshCostPct(state, cityId);
    return (full * (1 + pct / 100)).round();
  }

  /// The longest leg any plane in the fleet can fly. Jobs to cities beyond
  /// it are connection jobs.
  double fleetReachKm(GameState state) {
    if (state.planes.isEmpty) return double.infinity;
    return state.planes
        .map((p) => PlaneStats.of(rules, state, p).rangeKm)
        .reduce(math.max);
  }

  /// How long a job waits on a board before it leaves (jobs waiting to
  /// connect have their own expiry).
  Duration get jobLifetime =>
      _rotation * rules.config.jobs.jobLifetimeRotations;

  /// When [job] leaves its board unless a plane takes it: the
  /// `jobLifetimeRotations`-th rotation mark after it appeared.
  DateTime expiresAt(Job job) => rotationTime(
    rotationIndex(job.createdAt) + rules.config.jobs.jobLifetimeRotations,
  );

  /// Whether [job] leaves its board at the next rotation after [t].
  bool leavesSoon(GameState state, Job job, DateTime t) =>
      !job.isConnecting &&
      rules.config.jobs.jobLifetimeRotations > 1 &&
      !expiresAt(job).isAfter(nextRotationAt(state)) &&
      expiresAt(job).isAfter(t);

  /// Rotates every board if a 5-minute mark has passed since the last
  /// rotation. Each missed mark brings its batch, as of that mark (only the
  /// marks recent enough for their jobs to still be waiting count).
  GameState rotateIfDue(GameState state, DateTime t) {
    final index = rotationIndex(t);
    if (index <= state.boardRotation) return state;
    final first = math.max(
      state.boardRotation + 1,
      index - rules.config.jobs.jobLifetimeRotations + 1,
    );
    var next = state;
    for (var r = first; r <= index; r++) {
      next = next.copyWith(boardRotation: r);
      for (final airport in state.airports) {
        next = rotate(next, airport.cityId, rotationTime(r));
      }
    }
    return next;
  }

  /// The next extra top-up after [after] at an airport whose board refills
  /// more than once per rotation (Local hero), or null if there is none.
  DateTime? nextRefillAt(GameState state, DateTime after) {
    DateTime? soonest;
    for (final airport in state.airports) {
      final n = rules.crew.boardRefillsPerRotation(state, airport.cityId);
      if (n <= 1) continue;
      final step = _rotation.inMilliseconds ~/ n;
      final at = DateTime.fromMillisecondsSinceEpoch(
        (after.millisecondsSinceEpoch ~/ step + 1) * step,
        isUtc: true,
      );
      if (soonest == null || at.isBefore(soonest)) soonest = at;
    }
    return soonest;
  }

  /// Brings an extra batch of jobs to the boards whose extra refill falls
  /// at [t] (between rotation marks; the rotation brings its own).
  GameState refillIfDue(GameState state, DateTime t) {
    final ms = t.millisecondsSinceEpoch;
    if (ms % _rotation.inMilliseconds == 0) return state;
    var next = state;
    for (final airport in state.airports) {
      final n = rules.crew.boardRefillsPerRotation(state, airport.cityId);
      if (n > 1 && ms % (_rotation.inMilliseconds ~/ n) == 0) {
        next = fill(next, airport.cityId, t, batch: true);
      }
    }
    return next;
  }

  /// A rotation: jobs that have waited their lifetime leave (and layover
  /// jobs that have waited too long), then a batch of new jobs arrives, up
  /// to the board's size. With [swap], every job except those waiting to
  /// connect leaves and the board fills right back up (a paid refresh, or
  /// a storm clearing).
  GameState rotate(
    GameState state,
    String cityId,
    DateTime t, {
    bool swap = false,
  }) {
    final airport = state.airport(cityId)!;
    final expiry = Duration(minutes: rules.config.jobs.connectionExpiryMinutes);
    final kept = [
      for (final job in airport.board)
        if (job.isConnecting
            ? t.difference(job.connectingSince!) < expiry
            : !swap && expiresAt(job).isAfter(t))
          job,
    ];
    final filled = fill(
      state.updateAirport(cityId, (a) => a.copyWith(board: kept)),
      cityId,
      t,
      batch: !swap,
    );
    return Rivals(rules)
        .premiumLounge(charterChance(filled, cityId, t), cityId, t);
  }

  /// The paid refresh: swaps out the board's jobs now instead of waiting for
  /// the rotation. Jobs waiting to connect stay.
  GameState refresh(GameState state, String cityId, DateTime t) {
    require(state.ownsAirport(cityId), RuleError.notOwned);
    final paid = Economy(rules).spend(state, refreshCost(cityId, state));
    return rotate(paid, cityId, t, swap: true);
  }

  /// How many new jobs of each type a rotation brings to [airport]: its
  /// board size spread over a job's lifetime, so a board nobody takes from
  /// stays full.
  ({int passenger, int cargo}) batchSize(
    GameState state,
    AirportState airport,
  ) {
    final size = boardSize(state, airport);
    final life = rules.config.jobs.jobLifetimeRotations;
    return (
      passenger: (size.passenger / life).ceil(),
      cargo: (size.cargo / life).ceil(),
    );
  }

  /// Adds fresh jobs to [cityId]'s board until it is full. With [batch],
  /// adds at most one rotation's batch. Otherwise the new jobs' ages are
  /// spread over a job's lifetime, so they don't all leave at once.
  GameState fill(
    GameState state,
    String cityId,
    DateTime t, {
    bool batch = false,
  }) {
    final airport = state.airport(cityId)!;
    final size = boardSize(state, airport);
    final perBatch = batchSize(state, airport);
    final life = rules.config.jobs.jobLifetimeRotations;
    var passengers = 0;
    var cargo = 0;
    for (final job in airport.board) {
      if (job.isConnecting) continue;
      if (job.type == JobType.passenger) {
        passengers++;
      } else {
        cargo++;
      }
    }
    final rng = GameRng(state.rngState);
    var nextId = state.nextId;
    final reach = fleetReachKm(state);
    final hot = hotDestinations(state, cityId);
    final seats = biggestSeats(state, airport);
    final hold = biggestHold(state, airport);
    final added = <Job>[];
    for (final (type, room, limit) in [
      (JobType.passenger, size.passenger - passengers, perBatch.passenger),
      (JobType.cargo, size.cargo - cargo, perBatch.cargo),
    ]) {
      final missing = batch ? math.min(room, limit) : room;
      for (var i = 0; i < missing; i++) {
        final job = generate(
          state,
          rng,
          airport,
          type,
          batch ? t : t.subtract(_rotation * (i % life)),
          'j$nextId',
          reach,
          hot: hot,
          groupSeats: seats,
          groupSlots: hold,
        );
        if (job == null) break;
        nextId++;
        added.add(job);
      }
    }
    if (added.isEmpty) return state.copyWith(rngState: rng.state);
    return state
        .copyWith(rngState: rng.state, nextId: nextId)
        .updateAirport(
          cityId,
          (a) => a.copyWith(board: [...a.board, ...added]),
        );
  }

  /// The airports [cityId]'s board can send jobs to.
  List<String> destinations(GameState state, String cityId) => [
    for (final a in state.airports)
      if (a.cityId != cityId &&
          rules.distanceKm(cityId, a.cityId) >=
              rules.config.jobs.minJobDistanceKm)
        a.cityId,
  ];

  /// How strongly [airport]'s board pulls jobs toward [cityId]: bigger
  /// cities, higher-level airports and nearer ones pull harder.
  double destinationWeight(
    GameState state,
    AirportState airport,
    String cityId,
  ) {
    final jobs = rules.config.jobs;
    final km = rules.distanceKm(airport.cityId, cityId);
    final level = state.airport(cityId)?.level ?? 1;
    var w =
        jobs.destinationWeightBySize[rules.world.city(cityId).size - 1] *
        jobs.destinationWeightByLevel[level - 1] /
        (1 + km / jobs.gravityKm);
    if (rules.pathEffect(airport, 'longHaul') > 0 &&
        rules.crossesRegions(airport.cityId, cityId)) {
      w *= rules.config.airports.longHaulJobWeight;
    }
    return w;
  }

  /// The cities planes are flying to right now on trips out of [cityId]
  /// (their next stop and the stops after it). A plane that just left
  /// with a full load has served that demand for now, so [cityId]'s board
  /// stops favouring those cities until it lands; otherwise a second plane
  /// parked here finds the same charter waiting and follows it.
  Set<String> servedDestinations(GameState state, String cityId) => {
    for (final plane in state.planes)
      if (!plane.onGround &&
          plane.leg != null &&
          plane.leg!.fromCityId == cityId) ...[
        plane.leg!.toCityId,
        ...plane.remainingStops,
      ],
  }..remove(cityId);

  /// The destinations [cityId]'s board favours this rotation. They change
  /// every `hotRotations` rotations (and when the network changes), and a
  /// paid refresh keeps them. Cities a plane is already flying to from
  /// here ([servedDestinations]) aren't picked.
  List<String> hotDestinations(GameState state, String cityId) {
    final jobs = rules.config.jobs;
    final airport = state.airport(cityId);
    if (airport == null) return const [];
    final pool = destinations(state, cityId);
    final count = (pool.length ~/ jobs.destinationsPerHot).clamp(
      1,
      jobs.hotDestinations,
    );
    final period = state.boardRotation ~/ jobs.hotRotations;
    var seed = period * 0x9E3779B1 ^ pool.length * 0x85EBCA6B;
    for (final unit in cityId.codeUnits) {
      seed = (seed * 31 + unit) & 0xFFFFFFFF;
    }
    final rng = GameRng(seed);
    final served = servedDestinations(state, cityId);
    final open = [
      for (final c in pool)
        if (!served.contains(c)) c,
    ];
    final hot = <String>[];
    while (hot.length < count && hot.length < open.length) {
      final pick = rng.weighted(
        open,
        (c) => hot.contains(c) ? 0 : destinationWeight(state, airport, c),
      );
      if (pick == null) break;
      hot.add(pick);
    }
    return hot;
  }

  /// Seats of the biggest passenger plane in the fleet that can use
  /// [airport].
  int biggestSeats(GameState state, AirportState airport) {
    var best = 0;
    for (final plane in state.planes) {
      final stats = PlaneStats.of(rules, state, plane);
      if (_fits(stats, airport)) best = math.max(best, stats.seats);
    }
    return best;
  }

  /// Cargo slots of the biggest hold in the fleet that can use [airport].
  int biggestHold(GameState state, AirportState airport) {
    var best = 0;
    for (final plane in state.planes) {
      final stats = PlaneStats.of(rules, state, plane);
      if (_fits(stats, airport)) best = math.max(best, stats.cargoSlots);
    }
    return best;
  }

  bool _fits(PlaneStats stats, AirportState airport) =>
      rules.fitsAirportLevel(stats.model, airport.level);

  /// Seats a group booking takes: 1 for most passenger jobs, 2 or more for
  /// a group, which bigger planes make more common.
  int _rollGroup(GameRng rng, int seats) {
    final jobs = rules.config.jobs;
    final maxSize = (1 + seats ~/ jobs.groupSeatsPerSize).clamp(
      2,
      jobs.groupMaxSize,
    );
    final chance = math.min(
      jobs.groupMaxChancePct,
      seats * jobs.groupChancePctPerSeat,
    );
    if (seats < 2 || chance <= 0 || !rng.chance(chance)) {
      return 1;
    }
    return rng.between(2, maxSize);
  }

  /// Slots a cargo lot takes: 1 for most cargo jobs, 2 or more for a lot,
  /// which bigger holds make more common.
  int _rollLot(GameRng rng, int slots) {
    final jobs = rules.config.jobs;
    if (jobs.lotMaxSize < 2) return 1;
    final maxSize = (1 + slots ~/ jobs.lotSlotsPerSize).clamp(
      2,
      jobs.lotMaxSize,
    );
    final chance = math.min(
      jobs.lotMaxChancePct,
      slots * jobs.lotChancePctPerSlot,
    );
    if (slots < 2 || chance <= 0 || !rng.chance(chance)) return 1;
    return rng.between(2, math.min(maxSize, slots));
  }

  /// Charter chance: sometimes a rotation tops up one hot destination with
  /// enough jobs to fill a plane that can use the airport (one parked here
  /// if there is one, else the fleet's biggest that fits), seats and hold.
  /// It skips cities a plane is already flying to from here.
  GameState charterChance(GameState state, String cityId, DateTime t) {
    final pct = rules.config.jobs.charterChancePct;
    if (pct <= 0) return state;
    final rng = GameRng(state.rngState);
    if (!rng.chance(pct)) {
      return state.copyWith(rngState: rng.state);
    }
    final airport = state.airport(cityId)!;
    PlaneStats? best;
    var bestParked = false;
    for (final plane in state.planes) {
      final stats = PlaneStats.of(rules, state, plane);
      if (!_fits(stats, airport)) continue;
      final parked =
          plane.status == PlaneStatus.parked && plane.cityId == cityId;
      final bigger =
          best == null ||
          stats.seats + stats.cargoSlots > best.seats + best.cargoSlots;
      if ((parked && !bestParked) || (parked == bestParked && bigger)) {
        best = stats;
        bestParked = parked;
      }
    }
    if (best == null) return state.copyWith(rngState: rng.state);
    final stats = best;
    bool flyable(String dest) {
      final to = state.airport(dest)!;
      return _fits(stats, to) &&
          rules.distanceKm(cityId, dest) <= stats.rangeFrom(rules, airport);
    }

    int seatsTo(String dest, JobType type) => airport.board
        .where((j) => j.type == type && j.unloadCityId == dest)
        .fold(0, (n, j) => n + j.slots);
    // Never a city a plane has just left for with its own load.
    final served = servedDestinations(state, cityId);
    var options = hotDestinations(state, cityId).where(flyable).toList();
    if (options.isEmpty) {
      options = destinations(
        state,
        cityId,
      ).where((d) => flyable(d) && !served.contains(d)).toList();
    }
    if (options.isEmpty) return state.copyWith(rngState: rng.state);
    double have(String d) =>
        seatsTo(d, JobType.passenger) / math.max(1, stats.seats) +
        seatsTo(d, JobType.cargo) / math.max(1, stats.cargoSlots);
    options.sort((a, b) => have(b).compareTo(have(a)));
    final dest = options.first;

    var nextId = state.nextId;
    final reach = fleetReachKm(state);
    final added = <Job>[];
    for (final (type, capacity) in [
      (JobType.passenger, stats.seats),
      (JobType.cargo, stats.cargoSlots),
    ]) {
      var missing = capacity - seatsTo(dest, type);
      while (missing > 0) {
        final job = generate(
          state,
          rng,
          airport,
          type,
          t,
          'j$nextId',
          reach,
          toCityId: dest,
          maxSlots: missing,
          groupSeats: stats.seats,
          groupSlots: stats.cargoSlots,
        );
        if (job == null) break;
        nextId++;
        missing -= job.slots;
        added.add(job);
      }
    }
    if (added.isEmpty) return state.copyWith(rngState: rng.state);
    return state
        .copyWith(rngState: rng.state, nextId: nextId)
        .updateAirport(
          cityId,
          (a) => a.copyWith(board: [...a.board, ...added]),
        );
  }

  /// Rolls one job of [type] leaving [airport], or null if there is nowhere
  /// for it to go. [hot] destinations get `hotShare` of the jobs. With
  /// [toCityId], the job goes there, is a standard job (or group) and takes
  /// at most [maxSlots] seats or slots.
  Job? generate(
    GameState state,
    GameRng rng,
    AirportState airport,
    JobType type,
    DateTime t,
    String id,
    double reachKm, {
    List<String> hot = const [],
    String? toCityId,
    int? maxSlots,
    int? groupSeats,
    int? groupSlots,
  }) {
    final jobs = rules.config.jobs;
    final origin = rules.world.city(airport.cityId);
    if (type == JobType.passenger && toCityId == null) {
      final tour = _sightseeing(state, rng, airport, t, id);
      if (tour != null) return tour;
    }
    final farWeight = rules.crew.favoursConnections(state, origin.id);
    double km(String cityId) => rules.distanceKm(origin.id, cityId);
    double weight(String cityId) {
      var w = destinationWeight(state, airport, cityId);
      if (farWeight && km(cityId) > reachKm) w *= 2;
      return w;
    }

    final all = destinations(state, origin.id);
    final hotHere = [
      for (final c in hot)
        if (all.contains(c)) c,
    ];
    final String? dest;
    if (toCityId != null) {
      dest = toCityId;
    } else if (hotHere.isNotEmpty &&
        jobs.hotShare > 0 &&
        rng.chance(jobs.hotShare * 100)) {
      dest = rng.weighted(hotHere, weight);
    } else {
      dest = rng.weighted(all, weight);
    }
    if (dest == null) return null;

    final kind = toCityId != null
        ? JobKind.standard
        : _rollKind(state, rng, airport, type);
    final special = kind == JobKind.standard ? null : jobs.special[kind.name];
    final group = kind != JobKind.standard
        ? 1
        : math.min(
            type == JobType.passenger
                ? _rollGroup(rng, groupSeats ?? biggestSeats(state, airport))
                : _rollLot(rng, groupSlots ?? biggestHold(state, airport)),
            maxSlots ?? 1 << 20,
          );
    final longHaulPct = rules.pathEffect(airport, 'longHaul');
    final cross = rules.crossesRegions(origin.id, dest);
    final pct =
        rules.pathEffect(
          airport,
          type == JobType.passenger ? 'passengerPayPct' : 'cargoPayPct',
        ) +
        (cross ? rules.world.crossRegionPayPct + longHaulPct : 0) +
        WeatherRules(rules).jobPayPct(state, origin.id, type, t) +
        rules.crew.boardPayPct(state, origin.id, type);
    final rate = type == JobType.passenger
        ? rules.config.economy.passengerRatePerKm
        : rules.config.economy.cargoRatePerKm;
    final outbound = cross
        ? rules.world.region(origin.regionId).outboundPayMultiplier
        : 1.0;
    final payout =
        rate *
        group *
        km(dest) *
        (special?.payMultiplier ?? 1) *
        outbound *
        (1 + pct / 100);
    return Job(
      id: id,
      type: type,
      kind: kind,
      originCityId: origin.id,
      destCityId: dest,
      // Part crates pay with the part inside.
      payout: kind == JobKind.partCrate ? 0 : math.max(1, payout.round()),
      createdAt: t,
      slots: special?.slots ?? group,
      deadline: special?.deadlineMinutes == null
          ? null
          : t.add(Duration(minutes: special!.deadlineMinutes!)),
    );
  }

  /// A sightseeing tour, while the fleet has the plane that flies them: a
  /// round trip back to [airport] paying like a passenger job of
  /// `extras.sightseeing.tourKm`.
  Job? _sightseeing(
    GameState state,
    GameRng rng,
    AirportState airport,
    DateTime t,
    String id,
  ) {
    final special = rules.config.jobs.special['sightseeing']!;
    final model = special.requiresModel;
    if (model != null && !state.planes.any((p) => p.modelId == model)) {
      return null;
    }
    if (!rng.chance(special.chancePct)) return null;
    final pct =
        rules.pathEffect(airport, 'passengerPayPct') +
        WeatherRules(rules)
            .jobPayPct(state, airport.cityId, JobType.passenger, t) +
        rules.crew.boardPayPct(state, airport.cityId, JobType.passenger);
    final payout =
        rules.config.economy.passengerRatePerKm *
        rules.config.extras.sightseeingTourKm *
        special.payMultiplier *
        (1 + pct / 100);
    return Job(
      id: id,
      type: JobType.passenger,
      kind: JobKind.sightseeing,
      originCityId: airport.cityId,
      destCityId: airport.cityId,
      payout: math.max(1, payout.round()),
      createdAt: t,
    );
  }

  /// Special jobs appear from the special-jobs unlock level (VIP lounges and
  /// freight yards bring theirs from the start). Part crates appear from
  /// their own unlock level; sightseeing tours are rolled by [_sightseeing].
  JobKind _rollKind(
    GameState state,
    GameRng rng,
    AirportState airport,
    JobType type,
  ) {
    final special = rules.config.jobs.special;
    final unlocked = rules.config.progression.isUnlocked(
      'specialJobs',
      state.player.level,
    );
    double crew(JobKind kind) =>
        rules.crew.specialChancePct(state, airport.cityId, kind);
    if (type == JobType.passenger) {
      final lounge = rules.hasPathEffect(airport, 'vipLounge');
      final crewVip = crew(JobKind.vip);
      if ((unlocked || lounge || crewVip > 0) &&
          rng.chance(special['vip']!.chancePct * (lounge ? 5 : 1) + crewVip)) {
        return JobKind.vip;
      }
    } else {
      if (rules.config.progression.isUnlocked(
            'partCrates',
            state.player.level,
          ) &&
          rng.chance(100 / rules.config.jobs.partCrateOneIn)) {
        return JobKind.partCrate;
      }
      if (rules.hasPathEffect(airport, 'freightYard') &&
          rng.chance(special['bulk']!.chancePct)) {
        return JobKind.bulk;
      }
      if (unlocked &&
          rng.chance(special['fragile']!.chancePct + crew(JobKind.fragile))) {
        return JobKind.fragile;
      }
    }
    if (unlocked && rng.chance(special['rush']!.chancePct)) {
      return JobKind.rush;
    }
    return JobKind.standard;
  }
}
