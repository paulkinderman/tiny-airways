import '../core/state/game_state.dart';
import 'economy.dart';
import 'extras.dart';
import 'loading.dart';
import 'rules.dart';
import 'weather.dart';

/// One leg of a planned route, as the route picker shows it.
class LegQuote {
  const LegQuote({
    required this.fromCityId,
    required this.toCityId,
    required this.distanceKm,
    required this.duration,
    required this.fuel,
    required this.departAt,
  });

  final String fromCityId;
  final String toCityId;
  final double distanceKm;

  /// Real time on the clock.
  final Duration duration;
  final int fuel;
  final DateTime departAt;

  DateTime get arriveAt => departAt.add(duration);
}

/// A planned route: its legs, total fuel, what the jobs aboard should pay,
/// and anything that stops it departing.
class RouteQuote {
  const RouteQuote({
    required this.legs,
    required this.fuel,
    required this.expectedPayout,
    required this.problems,
  });

  final List<LegQuote> legs;
  final int fuel;
  final int expectedPayout;
  final List<RuleError> problems;

  bool get canDepart => problems.isEmpty;
  Duration get duration =>
      legs.fold(Duration.zero, (sum, leg) => sum + leg.duration);
}

/// What happened while the simulation ran: the welcome-back summary.
class SimReport {
  int moneyEarned = 0;
  int jobsDelivered = 0;
  int jobsLate = 0;
  int levelsGained = 0;

  /// Planes that finished their trip and are now parked, waiting.
  final List<String> landedPlaneIds = [];
  final List<({String planeId, String fromCityId, String toCityId})>
  diversions = [];

  /// Weather events forecast during the run.
  final List<String> newWeatherIds = [];

  bool get isEmpty =>
      moneyEarned == 0 &&
      jobsDelivered == 0 &&
      landedPlaneIds.isEmpty &&
      diversions.isEmpty &&
      newWeatherIds.isEmpty;
}

/// Routes, departures, landings, transfers, gates and diversions.
class Flights {
  const Flights(this.rules);

  final Rules rules;

  WeatherRules get _weather => WeatherRules(rules);

  /// Gates at [cityId] not taken by parked planes.
  int freeGates(GameState state, String cityId) {
    final airport = state.airport(cityId)!;
    final parked = state.planes
        .where((p) => p.status == PlaneStatus.parked && p.cityId == cityId)
        .length;
    return rules.config.airports.level(airport.level).gates - parked;
  }

  bool _fitsAirport(PlaneStats stats, AirportState airport) {
    final maxClass = rules.config.planes.planeClass(
      rules.config.airports.level(airport.level).maxPlaneClass,
    );
    return stats.planeClass.rank <= maxClass.rank;
  }

  /// Why a leg from [fromCityId] to [toCityId] can't be flown by [plane]
  /// at [t], or null if it can.
  RuleError? legProblem(
    GameState state,
    Plane plane,
    String fromCityId,
    String toCityId,
    DateTime t,
  ) {
    if (!rules.world.hasCity(toCityId)) return RuleError.unknownCity;
    final to = state.airport(toCityId);
    if (to == null) return RuleError.notOwned;
    if (toCityId == fromCityId) return RuleError.sameCity;
    final stats = PlaneStats.of(rules, state, plane);
    if (rules.distanceKm(fromCityId, toCityId) >
        stats.rangeFrom(rules, state.airport(fromCityId))) {
      return RuleError.outOfRange;
    }
    if (!_fitsAirport(stats, to)) return RuleError.planeTooBig;
    if (_weather.isClosed(state, toCityId, t)) return RuleError.airportClosed;
    return null;
  }

  /// Owned airports [plane] can fly to in one leg from where it is parked.
  List<String> reachable(GameState state, String planeId, DateTime t) {
    final plane = state.plane(planeId)!;
    return [
      for (final a in state.airports)
        if (legProblem(state, plane, plane.cityId, a.cityId, t) == null)
          a.cityId,
    ];
  }

  /// Plans flying [planeId] through [stops] in order, leaving at [t].
  RouteQuote quote(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime t,
  ) {
    final plane = state.plane(planeId);
    if (plane == null) {
      return const RouteQuote(
        legs: [],
        fuel: 0,
        expectedPayout: 0,
        problems: [RuleError.unknownPlane],
      );
    }
    final problems = <RuleError>{};
    if (plane.status != PlaneStatus.parked) {
      problems.add(RuleError.planeNotParked);
    }
    if (stops.isEmpty) problems.add(RuleError.noStops);
    if (_weather.isClosed(state, plane.cityId, t)) {
      problems.add(RuleError.airportClosed);
    }
    final load = Loading(rules).summary(state, plane, t);
    if (load.seatsUsed > load.seats) problems.add(RuleError.heatWaveSeats);
    if (rules.crew.departureProblem(state, plane) != null) {
      problems.add(RuleError.crewMissing);
    }

    final stats = PlaneStats.of(rules, state, plane);
    final legs = <LegQuote>[];
    var from = plane.cityId;
    var at = t;
    for (final to in stops) {
      final problem = legProblem(state, plane, from, to, at);
      if (problem != null) {
        problems.add(problem);
        if (problem == RuleError.unknownCity) break;
      }
      final km = rules.distanceKm(from, to);
      final leg = LegQuote(
        fromCityId: from,
        toCityId: to,
        distanceKm: km,
        duration: rules.config.flights.realDuration(km, stats.speedKmh),
        fuel: Economy(rules).fuelCost(state, plane, from, to, at),
        departAt: at,
      );
      legs.add(leg);
      from = to;
      at = leg.arriveAt;
    }
    final fuel = legs.fold(0, (sum, l) => sum + l.fuel);
    if (fuel > state.player.money) problems.add(RuleError.notEnoughMoney);

    final marked = _markLoadBonuses(state, plane, t);
    var payout = 0;
    for (final job in marked.load) {
      for (final leg in legs) {
        if (leg.toCityId == job.unloadCityId) {
          if (job.destCityId == leg.toCityId) {
            payout += deliveryPay(state, marked, job, leg.arriveAt);
          }
          break;
        }
      }
    }
    return RouteQuote(
      legs: legs,
      fuel: fuel,
      expectedPayout: payout,
      problems: problems.toList(),
    );
  }

  /// What [job] pays if [plane] delivers it at [t].
  int deliveryPay(GameState state, Plane plane, Job job, DateTime t) {
    if (job.deadline != null && t.isAfter(job.deadline!)) return 0;
    final pct =
        job.bonusPct +
        job.loadBonusPct +
        rules.crew.deliveryPayPct(state, plane, job);
    return (job.payout * (1 + pct / 100)).round();
  }

  /// Marks passengers in a charter and cargo in a full hold with their
  /// bonus, as the plane takes off.
  Plane _markLoadBonuses(GameState state, Plane plane, DateTime t) {
    final load = Loading(rules).summary(state, plane, t);
    final jobs = rules.config.jobs;
    double bonus(Job j) {
      final earned = j.type == JobType.passenger
          ? (load.isCharter ? jobs.charterBonusPct : 0.0)
          : (load.isFullHold ? jobs.fullHoldBonusPct : 0.0);
      return earned > j.loadBonusPct ? earned : j.loadBonusPct;
    }

    return plane.copyWith(
      load: [for (final j in plane.load) j.copyWith(loadBonusPct: bonus(j))],
    );
  }

  /// Rush jobs must go on the next departure from their airport; when a
  /// plane leaves, any still on the board are gone.
  GameState _dropRushJobs(GameState state, String cityId) =>
      state.updateAirport(
        cityId,
        (a) => a.copyWith(
          board: [
            for (final j in a.board)
              if (j.kind != JobKind.rush || j.isConnecting) j,
          ],
        ),
      );

  /// Sends [planeId] off through [stops], charging fuel for the whole trip
  /// now. Throws [RuleException] if [quote] finds a problem.
  GameState depart(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime t,
  ) {
    final plan = quote(state, planeId, stops, t);
    if (!plan.canDepart) throw RuleException(plan.problems.first);
    var next = Economy(rules).spend(state, plan.fuel);
    final load = Loading(rules).summary(state, state.plane(planeId)!, t);
    final challenges = Challenges(rules);
    if (load.isCharter) next = challenges.record(next, 'charters', 1);
    if (load.isFullHold) next = challenges.record(next, 'fullHolds', 1);
    next = next.copyWith(
      stats: next.stats.copyWith(fuelSpent: next.stats.fuelSpent + plan.fuel),
    );
    final plane = state.plane(planeId)!;
    next = _takeOff(next, plane, plan.legs.first, stops.sublist(1), t);
    return landHolding(next, plane.cityId, t, SimReport());
  }

  GameState _takeOff(
    GameState state,
    Plane plane,
    LegQuote leg,
    List<String> remaining,
    DateTime t, {
    bool diverted = false,
  }) {
    final marked = _markLoadBonuses(state, plane, t);
    return _dropRushJobs(state, leg.fromCityId).updatePlane(
      plane.id,
      (_) => marked.copyWith(
        status: PlaneStatus.flying,
        cityId: leg.fromCityId,
        leg: () => FlightLeg(
          fromCityId: leg.fromCityId,
          toCityId: leg.toCityId,
          departAt: t,
          arriveAt: t.add(leg.duration),
          distanceKm: leg.distanceKm,
          diverted: diverted,
        ),
        remainingStops: remaining,
        holdingSince: () => null,
      ),
    );
  }

  LegQuote _legNow(
    GameState state,
    Plane plane,
    String from,
    String to,
    DateTime t,
  ) {
    final km = rules.distanceKm(from, to);
    return LegQuote(
      fromCityId: from,
      toCityId: to,
      distanceKm: km,
      duration: rules.config.flights.realDuration(
        km,
        PlaneStats.of(rules, state, plane).speedKmh,
      ),
      fuel: 0,
      departAt: t,
    );
  }

  /// The nearest owned airport [plane] can divert to from [closedCityId].
  String? diversionFor(
    GameState state,
    Plane plane,
    String closedCityId,
    DateTime t,
  ) {
    final stats = PlaneStats.of(rules, state, plane);
    String? best;
    var bestKm = double.infinity;
    for (final a in state.airports) {
      if (a.cityId == closedCityId) continue;
      final km = rules.distanceKm(closedCityId, a.cityId);
      if (km > stats.rangeKm || km >= bestKm) continue;
      if (!_fitsAirport(stats, a)) continue;
      if (!_weather.canLand(state, plane, a.cityId, t)) continue;
      best = a.cityId;
      bestKm = km;
    }
    return best;
  }

  /// [planeId]'s current leg reaches its airport at [t]. It lands if it can;
  /// if weather shuts the airport it diverts to the nearest owned airport in
  /// range (jobs stay aboard), or holds until the weather clears; if every
  /// gate is full it holds until one opens.
  GameState arrive(
    GameState state,
    String planeId,
    DateTime t,
    SimReport report,
  ) {
    final plane = state.plane(planeId)!;
    final target = plane.leg!.toCityId;
    if (!_weather.canLand(state, plane, target, t)) {
      final alt = diversionFor(state, plane, target, t);
      if (alt != null) {
        report.diversions.add((
          planeId: planeId,
          fromCityId: target,
          toCityId: alt,
        ));
        return _takeOff(
          state,
          plane,
          _legNow(state, plane, target, alt, t),
          const [],
          t,
          diverted: true,
        );
      }
      return _hold(state, plane, t);
    }
    if (freeGates(state, target) <= 0) return _hold(state, plane, t);
    return _land(state, plane, t, report);
  }

  GameState _hold(GameState state, Plane plane, DateTime t) =>
      state.updatePlane(
        plane.id,
        (p) => p.copyWith(
          status: PlaneStatus.holding,
          cityId: p.leg!.toCityId,
          holdingSince: () => t,
        ),
      );

  /// Lands planes holding over [cityId] (or anywhere, with null) that now
  /// can, longest-waiting first.
  GameState landHolding(
    GameState state,
    String? cityId,
    DateTime t,
    SimReport report,
  ) {
    final holding = [
      for (final p in state.planes)
        if (p.status == PlaneStatus.holding &&
            (cityId == null || p.cityId == cityId))
          p,
    ]..sort((a, b) => a.holdingSince!.compareTo(b.holdingSince!));
    var next = state;
    for (final p in holding) {
      final plane = next.plane(p.id)!;
      if (_weather.canLand(next, plane, plane.cityId, t) &&
          freeGates(next, plane.cityId) > 0) {
        next = _land(next, plane, t, report);
      }
    }
    return next;
  }

  /// Touches down at the end of the current leg: delivers jobs bound here,
  /// drops jobs connecting here onto the board, then flies on to the next
  /// stop or parks.
  GameState _land(GameState state, Plane plane, DateTime t, SimReport report) {
    final leg = plane.leg!;
    final city = leg.toCityId;
    final economy = Economy(rules);
    final airport = state.airport(city)!;
    final transferPct = rules.pathEffect(airport, 'transferPayPct');
    final codeshareXp = rules.hasPathEffect(airport, 'codeshare')
        ? rules.config.airports.codeshareTransferXp
        : 0;
    final key = StatsState.routeKey(leg.fromCityId, city);
    var next = state.copyWith(
      stats: state.stats.copyWith(
        legsFlown: state.stats.legsFlown + 1,
        kmFlown: state.stats.kmFlown + leg.distanceKm,
        routeLegs: {
          ...state.stats.routeLegs,
          key: (state.stats.routeLegs[key] ?? 0) + 1,
        },
      ),
    );
    final levelBefore = next.player.level;

    final staying = <Job>[];
    final dropped = <Job>[];
    final delivered = <Job>[];
    var paid = 0;
    for (final job in plane.load) {
      if (job.destCityId == city) {
        final pay = deliveryPay(next, plane, job, t);
        final late = job.deadline != null && t.isAfter(job.deadline!);
        if (!late) delivered.add(job);
        paid += pay;
        if (job.kind == JobKind.partCrate) {
          final parts = Parts(rules);
          next = parts.collect(
            next,
            parts.crateContents(next, _seedOf(job, next)),
          );
        }
        next = economy.earn(next, pay);
        next = next.copyWith(
          stats: next.stats.copyWith(
            jobsDelivered: next.stats.jobsDelivered + (late ? 0 : 1),
            jobsLate: next.stats.jobsLate + (late ? 1 : 0),
          ),
        );
        report.moneyEarned += pay;
        if (late) {
          report.jobsLate++;
        } else {
          report.jobsDelivered++;
        }
      } else if (job.dropAtCityId == city) {
        dropped.add(
          job.copyWith(
            dropAtCityId: () => null,
            connectingSince: () => t,
            bonusPct: job.bonusPct + transferPct,
          ),
        );
        if (codeshareXp > 0) next = economy.grantXp(next, codeshareXp);
      } else {
        staying.add(job);
      }
    }
    next = Challenges(rules).recordLanding(
      next,
      cityId: city,
      km: leg.distanceKm,
      delivered: delivered,
      paid: paid,
      connections: dropped.length,
      endsMultiStopTrip: plane.remainingStops.isEmpty && plane.tripStops > 0,
      t: t,
    );
    report.levelsGained += next.player.level - levelBefore;
    if (dropped.isNotEmpty) {
      next = next.updateAirport(
        city,
        (a) => a.copyWith(board: [...a.board, ...dropped]),
      );
    }

    final landed = plane.copyWith(
      cityId: city,
      load: staying,
      holdingSince: () => null,
    );
    if (plane.remainingStops.isNotEmpty) {
      final stop = plane.remainingStops.first;
      next = next.updatePlane(
        plane.id,
        (_) => landed.copyWith(tripStops: plane.tripStops + 1),
      );
      return _takeOff(
        next,
        next.plane(plane.id)!,
        _legNow(next, landed, city, stop, t),
        plane.remainingStops.sublist(1),
        t,
      );
    }
    report.landedPlaneIds.add(plane.id);
    return next.updatePlane(
      plane.id,
      (_) => landed.copyWith(
        status: PlaneStatus.parked,
        leg: () => null,
        remainingStops: const [],
        tripStops: 0,
      ),
    );
  }

  /// Which part a crate holds is settled when it lands, from its id.
  static int _seedOf(Job job, GameState state) {
    var h = state.createdAt.millisecondsSinceEpoch & 0xFFFFFFFF;
    for (final c in job.id.codeUnits) {
      h = (h * 31 + c) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Every flight in the air, soonest landing first (for the departures
  /// board).
  List<Plane> inTheAir(GameState state) => [
    for (final p in state.planes)
      if (p.status != PlaneStatus.parked) p,
  ]..sort((a, b) => a.leg!.arriveAt.compareTo(b.leg!.arriveAt));
}
