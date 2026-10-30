import '../core/state/game_state.dart';
import 'economy.dart';
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

  int get freeSeats => seats - seatsUsed;
  int get freeCargoSlots => cargoSlots - cargoSlotsUsed;

  /// Every seat filled, all to one city.
  bool get isCharter =>
      seats > 0 && seatsUsed == seats && charterCount == seats;

  /// Every cargo slot filled, all to one city.
  bool get isFullHold =>
      cargoSlotsUsed > 0 &&
      cargoSlotsUsed >= cargoSlots - holdSlack &&
      holdCount == cargoSlotsUsed;
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
    );
  }

  Plane _parked(GameState state, String planeId) {
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    require(plane!.status == PlaneStatus.parked, RuleError.planeNotParked);
    return plane;
  }

  /// Why [job] can't go on [plane] right now, or null if it can.
  RuleError? loadProblem(
    GameState state,
    Plane plane,
    Job job,
    DateTime t, {
    String? dropAtCityId,
  }) {
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
    final drop = dropAtCityId == job!.destCityId ? null : dropAtCityId;
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
  /// that started somewhere else waits here to connect.
  GameState unload(GameState state, String planeId, String jobId, DateTime t) {
    final plane = _parked(state, planeId);
    final job = plane.load.where((j) => j.id == jobId).firstOrNull;
    require(job != null, RuleError.unknownJob);
    final onBoard = job!.copyWith(
      dropAtCityId: () => null,
      connectingSince: () => job.originCityId == plane.cityId ? null : t,
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

  /// "Fill to": loads every job on the board bound for [destCityId] that
  /// fits, best-paying first.
  GameState fillTo(
    GameState state,
    String planeId,
    String destCityId,
    DateTime t,
  ) {
    final plane = _parked(state, planeId);
    final candidates = [
      for (final j in state.airport(plane.cityId)!.board)
        if (j.destCityId == destCityId) j,
    ]..sort((a, b) => b.payout.compareTo(a.payout));
    var next = state;
    for (final job in candidates) {
      if (loadProblem(next, next.plane(planeId)!, job, t) == null) {
        next = load(next, planeId, job.id, t);
      }
    }
    return next;
  }
}
