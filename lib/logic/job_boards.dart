import 'dart:math' as math;

import '../core/state/game_state.dart';
import 'economy.dart';
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
        rules.config.airports.level(airport.level).jobBoardSize +
        rules.crew.extraBoardSlots(state, airport.cityId);
    final cargo = (base * rules.config.jobs.cargoShare).round();
    return (
      passenger:
          base -
          cargo +
          rules.pathEffect(airport, 'passengerBoardSlots').round(),
      cargo: cargo + rules.pathEffect(airport, 'cargoBoardSlots').round(),
    );
  }

  /// What a paid refresh costs at [cityId].
  int refreshCost(String cityId) =>
      rules.config.jobs.refreshCostPerCitySize * rules.world.city(cityId).size;

  /// The longest leg any plane in the fleet can fly. Jobs to cities beyond
  /// it are connection jobs.
  double fleetReachKm(GameState state) {
    if (state.planes.isEmpty) return double.infinity;
    return state.planes
        .map((p) => PlaneStats.of(rules, state, p).rangeKm)
        .reduce(math.max);
  }

  /// Rotates every board if a 5-minute mark has passed since the last
  /// rotation. However many marks were missed, boards rotate once, as of the
  /// latest mark.
  GameState rotateIfDue(GameState state, DateTime t) {
    final index = rotationIndex(t);
    if (index <= state.boardRotation) return state;
    final at = rotationTime(index);
    var next = state.copyWith(boardRotation: index);
    for (final airport in state.airports) {
      next = rotate(next, airport.cityId, at);
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

  /// Tops up the boards whose extra refill falls at [t] (between rotation
  /// marks; the rotation itself refills every board).
  GameState refillIfDue(GameState state, DateTime t) {
    final ms = t.millisecondsSinceEpoch;
    if (ms % _rotation.inMilliseconds == 0) return state;
    var next = state;
    for (final airport in state.airports) {
      final n = rules.crew.boardRefillsPerRotation(state, airport.cityId);
      if (n > 1 && ms % (_rotation.inMilliseconds ~/ n) == 0) {
        next = fill(next, airport.cityId, t);
      }
    }
    return next;
  }

  /// Replaces every job on [cityId]'s board except those waiting to connect,
  /// then fills it back up. Connecting jobs that have waited too long go too,
  /// unless the airport has Codeshare.
  GameState rotate(GameState state, String cityId, DateTime t) {
    final airport = state.airport(cityId)!;
    final expiry = Duration(minutes: rules.config.jobs.connectionExpiryMinutes);
    final keepsForever = rules.hasPathEffect(airport, 'codeshare');
    final kept = [
      for (final job in airport.board)
        if (job.isConnecting &&
            (keepsForever || t.difference(job.connectingSince!) < expiry))
          job,
    ];
    return fill(
      state.updateAirport(cityId, (a) => a.copyWith(board: kept)),
      cityId,
      t,
    );
  }

  /// The paid refresh: swaps out the board's jobs now instead of waiting for
  /// the rotation. Jobs waiting to connect stay.
  GameState refresh(GameState state, String cityId, DateTime t) {
    require(state.ownsAirport(cityId), RuleError.notOwned);
    final paid = Economy(rules).spend(state, refreshCost(cityId));
    return rotate(paid, cityId, t);
  }

  /// Adds fresh jobs to [cityId]'s board until it is full.
  GameState fill(GameState state, String cityId, DateTime t) {
    final airport = state.airport(cityId)!;
    final size = boardSize(state, airport);
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
    final added = <Job>[];
    for (final (type, missing) in [
      (JobType.passenger, size.passenger - passengers),
      (JobType.cargo, size.cargo - cargo),
    ]) {
      for (var i = 0; i < missing; i++) {
        final job = generate(state, rng, airport, type, t, 'j$nextId', reach);
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

  /// Rolls one job of [type] leaving [airport], or null if there is nowhere
  /// for it to go.
  Job? generate(
    GameState state,
    GameRng rng,
    AirportState airport,
    JobType type,
    DateTime t,
    String id,
    double reachKm,
  ) {
    final jobs = rules.config.jobs;
    final origin = rules.world.city(airport.cityId);
    final longHaulPct = rules.pathEffect(airport, 'longHaul');
    final connectionPct = rules.pathEffect(airport, 'connectionJobs');
    final farWeight =
        connectionPct > 0 || rules.crew.favoursConnections(state, origin.id);
    double km(String cityId) => rules.distanceKm(origin.id, cityId);
    final destinations = [
      for (final a in state.airports)
        if (a.cityId != origin.id && km(a.cityId) >= jobs.minJobDistanceKm)
          a.cityId,
    ];
    final dest = rng.weighted(destinations, (cityId) {
      var w = jobs.destinationWeightBySize[rules.world.city(cityId).size - 1];
      if (longHaulPct > 0 && rules.crossesRegions(origin.id, cityId)) {
        w *= rules.config.airports.longHaulJobWeight;
      }
      if (farWeight && km(cityId) > reachKm) w *= 2;
      return w;
    });
    if (dest == null) return null;

    final kind = _rollKind(state, rng, airport, type);
    final special = kind == JobKind.standard ? null : jobs.special[kind.name];
    final cross = rules.crossesRegions(origin.id, dest);
    final pct =
        rules.pathEffect(
          airport,
          type == JobType.passenger ? 'passengerPayPct' : 'cargoPayPct',
        ) +
        (cross ? rules.world.crossRegionPayPct + longHaulPct : 0) +
        (connectionPct > 0 && km(dest) > reachKm ? connectionPct : 0) +
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
      payout: math.max(1, payout.round()),
      createdAt: t,
      slots: special?.slots ?? 1,
      deadline: special?.deadlineMinutes == null
          ? null
          : t.add(Duration(minutes: special!.deadlineMinutes!)),
    );
  }

  /// Special jobs appear from the special-jobs unlock level (VIP lounges and
  /// freight yards bring theirs from the start). Sightseeing jobs and part
  /// crates are rolled by package 10.
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
