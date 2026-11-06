import '../core/state/game_state.dart';
import 'economy.dart';
import 'rivals.dart';
import 'rules.dart';
import 'weather.dart';

/// How full a plane is, and how close it is to a charter or full hold.
class LoadSummary {
  const LoadSummary({
    required this.seats,
    required this.seatsUsed,
    required this.cargoSlots,
    required this.cargoSlotsUsed,
    required this.charterCityId,
    required this.charterCount,
    required this.holdCityId,
    required this.holdCount,
    this.holdSlack = 0,
    this.anyCity = false,
  });

  /// Seats available here and now (a heat wave takes some from Large planes).
  final int seats;
  final int seatsUsed;
  final int cargoSlots;
  final int cargoSlotsUsed;

  /// The city most passengers aboard are going to, and how many seats they
  /// fill ("4 of 6 seats to New York").
  final String? charterCityId;
  final int charterCount;

  /// The same for cargo slots.
  final String? holdCityId;
  final int holdCount;

  /// Empty slots a hold may have and still count as full (Tight ship).
  final int holdSlack;

  /// A full cabin or hold counts whatever its destinations (Combi role).
  final bool anyCity;

  int get freeSeats => seats - seatsUsed;
  int get freeCargoSlots => cargoSlots - cargoSlotsUsed;

  /// Every seat filled, all to one city (any cities on a Combi).
  bool get isCharter =>
      seats > 0 && seatsUsed == seats && (anyCity || charterCount == seats);

  /// Every cargo slot filled, all to one city (any cities on a Combi).
  bool get isFullHold =>
      cargoSlotsUsed > 0 &&
      cargoSlotsUsed >= cargoSlots - holdSlack &&
      (anyCity || holdCount == cargoSlotsUsed);
}

/// Moving jobs between a parked plane and its airport's board.
class Loading {
  const Loading(this.rules);

  final Rules rules;

  LoadSummary summary(GameState state, Plane plane, DateTime t) {
    final stats = PlaneStats.of(rules, state, plane);
    final penalty = WeatherRules(rules)
        .seatPenalty(state, plane.cityId, stats.planeClass.id, t);
    final seats = (stats.seats - penalty).clamp(0, stats.seats);
    final byCity = {
      JobType.passenger: <String, int>{},
      JobType.cargo: <String, int>{},
    };
    var seatsUsed = 0;
    var slotsUsed = 0;
    for (final job in plane.load) {
      final slots = rules.crew.jobSlots(state, plane, job);
      if (job.type == JobType.passenger) {
        seatsUsed += slots;
      } else {
        slotsUsed += slots;
      }
      final counts = byCity[job.type]!;
      counts[job.unloadCityId] = (counts[job.unloadCityId] ?? 0) + slots;
    }
    (String?, int) top(Map<String, int> counts) {
      String? best;
      var n = 0;
      for (final e in counts.entries) {
        if (e.value > n) (best, n) = (e.key, e.value);
      }
      return (best, n);
    }

    final charter = top(byCity[JobType.passenger]!);
    final hold = top(byCity[JobType.cargo]!);
    return LoadSummary(
      seats: seats,
      seatsUsed: seatsUsed,
      cargoSlots: stats.cargoSlots,
      cargoSlotsUsed: slotsUsed,
      charterCityId: charter.$1,
      charterCount: charter.$2,
      holdCityId: hold.$1,
      holdCount: hold.$2,
      holdSlack: rules.crew.fullHoldSlack(state, plane),
      anyCity: rules.config.planes.roleEffect(stats.model, 'anyCityBonus') > 0,
    );
  }

  Plane _parked(GameState state, String planeId) {
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    require(plane!.status == PlaneStatus.parked, RuleError.planeNotParked);
    return plane;
  }

  // Layovers -------------------------------------------------------------

  /// How many seats or slots of layover jobs [cityId] can hold: the
  /// airport level's base plus the Layovers path.
  int layoverSlots(GameState state, String cityId) {
    final airport = state.airport(cityId);
    if (airport == null) return 0;
    return rules.config.airports.level(airport.level).layoverSlots +
        rules.pathEffect(airport, 'layoverSlots').round();
  }

  /// Layover slots taken at [cityId]: jobs waiting on its board, plus jobs
  /// aboard planes that will be dropped there (their slot is held).
  int layoversUsed(GameState state, String cityId) {
    var used = 0;
    for (final j in state.airport(cityId)?.board ?? const <Job>[]) {
      if (j.isConnecting) used += j.slots;
    }
    for (final p in state.planes) {
      for (final j in p.load) {
        if (j.dropAtCityId == cityId) used += j.slots;
      }
    }
    return used;
  }

  /// Free layover slots at [cityId] (never below 0).
  int freeLayoverSlots(GameState state, String cityId) {
    final free = layoverSlots(state, cityId) - layoversUsed(state, cityId);
    return free < 0 ? 0 : free;
  }

  /// Throws away layover [jobId] waiting on [cityId]'s board: it leaves
  /// without paying and frees its layover slot. Only layover jobs can go;
  /// the airport's own jobs leave with the board rotation.
  GameState removeLayover(GameState state, String cityId, String jobId) {
    final airport = state.airport(cityId);
    require(airport != null, RuleError.notOwned);
    final job = airport!.board.where((j) => j.id == jobId).firstOrNull;
    require(job != null && job.isConnecting, RuleError.jobNotHere);
    return state.updateAirport(
      cityId,
      (a) => a.copyWith(
        board: [
          for (final j in a.board)
            if (j.id != jobId) j,
        ],
      ),
    );
  }

  /// Why [job] can't go on [plane] right now, or null if it can.
  RuleError? loadProblem(
    GameState state,
    Plane plane,
    Job job,
    DateTime t, {
    String? dropAtCityId,
  }) {
    if (Rivals(rules).isHeld(state, job, t)) return RuleError.rivalFirstLook;
    final load = summary(state, plane, t);
    final free = job.type == JobType.passenger
        ? load.freeSeats
        : load.freeCargoSlots;
    if (rules.crew.jobSlots(state, plane, job) > free) return RuleError.noRoom;
    final special = rules.config.jobs.special[job.kind.name];
    final role = special?.requiresRole;
    if (role != null && !rules.crew.hasRole(state, plane, role)) {
      return RuleError.fragileNeedsLoadmaster;
    }
    final model = special?.requiresModel;
    if (model != null && plane.modelId != model) {
      return RuleError.wrongPlaneForJob;
    }
    if (dropAtCityId != null &&
        (!state.ownsAirport(dropAtCityId) ||
            dropAtCityId == plane.cityId ||
            job.kind == JobKind.sightseeing)) {
      return RuleError.badDropCity;
    }
    if (dropAtCityId != null &&
        freeLayoverSlots(state, dropAtCityId) < job.slots) {
      return RuleError.layoverFull;
    }
    return null;
  }

  /// Moves [jobId] from the board where [planeId] is parked into a free seat
  /// or slot. With [dropAtCityId], it will be dropped there to connect
  /// instead of riding to its destination.
  GameState load(
    GameState state,
    String planeId,
    String jobId,
    DateTime t, {
    String? dropAtCityId,
  }) {
    final plane = _parked(state, planeId);
    final airport = state.airport(plane.cityId)!;
    final job = airport.board.where((j) => j.id == jobId).firstOrNull;
    require(job != null, RuleError.jobNotHere);
    require(!Rivals(rules).isHeld(state, job!, t), RuleError.rivalFirstLook);
    final drop = dropAtCityId == job.destCityId ? null : dropAtCityId;
    final problem = loadProblem(state, plane, job, t, dropAtCityId: drop);
    if (problem != null) throw RuleException(problem);
    final aboard = job.copyWith(
      dropAtCityId: () => drop,
      connectingSince: () => null,
    );
    return state
        .updateAirport(
          airport.cityId,
          (a) => a.copyWith(
            board: [
              for (final j in a.board)
                if (j.id != jobId) j,
            ],
          ),
        )
        .updatePlane(planeId, (p) => p.copyWith(load: [...p.load, aboard]));
  }

  /// Takes [jobId] off a parked plane and puts it back on the board. A job
  /// that started somewhere else waits here on a layover, which needs a
  /// free layover slot unless [checkRoom] is false (autopilot clearing a
  /// plane).
  GameState unload(
    GameState state,
    String planeId,
    String jobId,
    DateTime t, {
    bool checkRoom = true,
  }) {
    final plane = _parked(state, planeId);
    final job = plane.load.where((j) => j.id == jobId).firstOrNull;
    require(job != null, RuleError.unknownJob);
    final layover = job!.originCityId != plane.cityId;
    if (checkRoom && layover) {
      require(
        freeLayoverSlots(state, plane.cityId) >= job.slots,
        RuleError.layoverFull,
      );
    }
    final onBoard = job.copyWith(
      dropAtCityId: () => null,
      connectingSince: () => layover ? t : null,
    );
    return state
        .updatePlane(
          planeId,
          (p) => p.copyWith(
            load: [
              for (final j in p.load)
                if (j.id != jobId) j,
            ],
          ),
        )
        .updateAirport(
          plane.cityId,
          (a) => a.copyWith(board: [...a.board, onBoard]),
        );
  }

  /// "Unload all": takes everything off parked [planeId]. Jobs that started
  /// here go back on the board; the rest wait here on a layover, as many
  /// as there are free layover slots (best-paying first). The rest stay
  /// aboard. Throws [RuleError.layoverFull] if nothing could come off.
  GameState unloadAll(GameState state, String planeId, DateTime t) {
    final plane = _parked(state, planeId);
    if (plane.load.isEmpty) return state;
    final jobs = [...plane.load]..sort((a, b) => b.payout.compareTo(a.payout));
    var next = state;
    for (final job in jobs) {
      final layover = job.originCityId != plane.cityId;
      if (layover && freeLayoverSlots(next, plane.cityId) < job.slots) {
        continue;
      }
      next = unload(next, planeId, job.id, t);
    }
    require(
      next.plane(planeId)!.load.length < plane.load.length,
      RuleError.layoverFull,
    );
    return next;
  }

  /// "Fill to": loads the jobs on the board bound for [destCityId] that
  /// earn the most, counting the charter (seats) and full-hold (cargo)
  /// bonus when the pick fills the plane for that city. A full plane of
  /// cheaper jobs beats a half-empty one of pricier jobs only when the
  /// bonus makes it pay more.
  GameState fillTo(
    GameState state,
    String planeId,
    String destCityId,
    DateTime t,
  ) {
    final plan = planFill(state, planeId, destCityId, t);
    var next = state;
    for (final job in plan.jobs) {
      if (loadProblem(next, next.plane(planeId)!, job, t) == null) {
        next = load(next, planeId, job.id, t);
      }
    }
    return next;
  }

  /// The destination whose [planFill] earns the plane the most, counting
  /// what is aboard already; null when nothing on the board fits.
  FillPlan? bestFill(GameState state, String planeId, DateTime t) {
    final plane = _parked(state, planeId);
    final cities = {
      for (final j in state.airport(plane.cityId)!.board)
        if (!Rivals(rules).isHeld(state, j, t)) j.destCityId,
    }..remove(plane.cityId);
    FillPlan? best;
    for (final city in cities) {
      final plan = planFill(state, planeId, city, t);
      if (plan.jobs.isEmpty) continue;
      if (best == null ||
          plan.value > best.value ||
          (plan.value == best.value && plan.slots > best.slots)) {
        best = plan;
      }
    }
    return best;
  }

  /// What "fill to" [destCityId] would load on parked [planeId]: the
  /// best-earning set of jobs for each of seats and cargo, found exactly
  /// (a small knapsack over the free room) rather than best-first, so
  /// multi-seat bookings don't crowd out a full charter.
  FillPlan planFill(
    GameState state,
    String planeId,
    String destCityId,
    DateTime t,
  ) {
    final plane = _parked(state, planeId);
    final load = summary(state, plane, t);
    final jobs = rules.config.jobs;
    final eligible = [
      for (final j in state.airport(plane.cityId)!.board)
        if (j.destCityId == destCityId && _fitsIgnoringRoom(state, plane, j, t))
          j,
    ];
    final picked = <Job>[];
    var value = 0.0;
    var gain = 0.0;
    var slots = 0;
    var charter = false;
    var fullHold = false;
    for (final type in JobType.values) {
      final passenger = type == JobType.passenger;
      final capacity = passenger ? load.seats : load.cargoSlots;
      if (capacity <= 0) continue;
      final aboard = [
        for (final j in plane.load)
          if (j.type == type) j,
      ];
      final used = passenger ? load.seatsUsed : load.cargoSlotsUsed;
      final free = capacity - used;
      final aboardPay = aboard.fold(0, (sum, j) => sum + j.payout);
      final allToDest = aboard.every((j) => j.unloadCityId == destCityId);
      final bonusPct = passenger ? jobs.charterBonusPct : jobs.fullHoldBonusPct;
      bool earnsBonus(int total) =>
          allToDest &&
          total > 0 &&
          (passenger ? total == capacity : total >= capacity - load.holdSlack);

      final items = [
        for (final j in eligible)
          if (j.type == type) j,
      ];
      // best[c]: the most pay from board jobs taking exactly c slots.
      final best = List<int?>.filled(free < 0 ? 1 : free + 1, null);
      final chosen = List<List<Job>>.generate(best.length, (_) => const []);
      best[0] = 0;
      for (final job in items) {
        final size = rules.crew.jobSlots(state, plane, job);
        for (var c = best.length - 1; c >= size; c--) {
          final prev = best[c - size];
          if (prev == null) continue;
          final pay = prev + job.payout;
          if (best[c] == null || pay > best[c]!) {
            best[c] = pay;
            chosen[c] = [...chosen[c - size], job];
          }
        }
      }
      var bestValue = -1.0;
      var bestC = 0;
      for (var c = 0; c < best.length; c++) {
        final pay = best[c];
        if (pay == null) continue;
        final total = aboardPay + pay;
        final v = earnsBonus(used + c)
            ? total * (1 + bonusPct / 100)
            : total.toDouble();
        if (v > bestValue || (v == bestValue && c > bestC)) {
          bestValue = v;
          bestC = c;
        }
      }
      picked.addAll(chosen[bestC]);
      value += bestValue;
      gain +=
          bestValue -
          (earnsBonus(used) ? aboardPay * (1 + bonusPct / 100) : aboardPay);
      slots += bestC;
      if (earnsBonus(used + bestC)) {
        if (passenger) {
          charter = true;
        } else {
          fullHold = true;
        }
      }
    }
    return FillPlan(
      cityId: destCityId,
      jobs: picked,
      slots: slots,
      value: value.round(),
      gain: gain.round(),
      charter: charter,
      fullHold: fullHold,
    );
  }

  /// [loadProblem] without the room check: could [job] ride on [plane] if
  /// there were space.
  bool _fitsIgnoringRoom(GameState state, Plane plane, Job job, DateTime t) {
    final problem = loadProblem(state, plane.copyWith(load: const []), job, t);
    return problem == null;
  }
}

/// A planned "fill to": which board jobs to load toward [cityId] and what
/// the plane would then earn.
class FillPlan {
  const FillPlan({
    required this.cityId,
    required this.jobs,
    required this.slots,
    required this.value,
    required this.gain,
    required this.charter,
    required this.fullHold,
  });

  final String cityId;
  final List<Job> jobs;

  /// Seats and slots the new jobs take.
  final int slots;

  /// The whole load's base pay afterwards, with any charter or full-hold
  /// bonus (an estimate: crew and weather bonuses come on top).
  final int value;

  /// How much [value] grows over the load as it is now.
  final int gain;

  /// Whether the seats end up a charter, and the hold a full hold.
  final bool charter;
  final bool fullHold;
}
