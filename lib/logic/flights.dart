import '../core/state/game_state.dart';
import 'economy.dart';
import 'extras.dart';
import 'loading.dart';
import 'rivals.dart';
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

/// Coins a trip in the air has made and should still make.
class TripProfit {
  const TripProfit({
    required this.earned,
    required this.expected,
    required this.fuel,
  });

  /// Paid at stops already made on this trip.
  final int earned;

  /// What the jobs aboard should pay at the stops ahead.
  final int expected;

  /// Paid for the whole trip at departure.
  final int fuel;

  int get payout => earned + expected;
  int get profit => payout - fuel;
}

/// A planned route: its legs, total fuel, what the jobs aboard should pay,
/// and anything that stops it departing.
class RouteQuote {
  const RouteQuote({
    required this.legs,
    required this.fuel,
    required this.expectedPayout,
    required this.problems,
    this.pickupsAt = const [],
    this.pickupPayout = 0,
  });

  final List<LegQuote> legs;
  final int fuel;

  /// What the jobs aboard pay, plus [pickupPayout].
  final int expectedPayout;
  final List<RuleError> problems;

  /// For each leg, how many jobs waiting at its airport right now the plane
  /// would pick up there for later stops (always 0 for the last leg, or
  /// when pickups are off).
  final List<int> pickupsAt;

  /// What those pickups should pay (included in [expectedPayout]).
  final int pickupPayout;

  int get pickups => pickupsAt.fold(0, (sum, n) => sum + n);

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

  /// Jobs planes picked up at stops partway through a trip.
  int jobsPickedUp = 0;

  /// Planes that finished their trip and are now parked, waiting.
  final List<String> landedPlaneIds = [];
  final List<({String planeId, String fromCityId, String toCityId})>
  diversions = [];

  /// Weather events forecast during the run.
  final List<String> newWeatherIds = [];

  /// The time the run catches up to. Landings well before it happen while
  /// the player is away (crew's Red-eye pays for those).
  DateTime? until;

  /// Coins earned by planes on autopilot (included in [moneyEarned]).
  int autopilotEarned = 0;

  /// Planes whose autopilot stopped because the route became impossible.
  final List<String> autopilotStoppedIds = [];

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
    return gates(airport) - parked;
  }

  // Hangar ----------------------------------------------------------------

  /// Puts parked [planeId] away in its airport's hangar: it stops taking a
  /// gate, can't load or fly, and comes off autopilot. Jobs aboard go back
  /// on the board (ones from elsewhere wait on a layover). Its crew stay
  /// with it but are free to move. A plane circling for a gate here lands
  /// in the gate it frees.
  GameState storePlane(GameState state, String planeId, DateTime t) {
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    require(plane!.status == PlaneStatus.parked, RuleError.planeNotParked);
    var next = state;
    final loading = Loading(rules);
    for (final job in plane.load) {
      next = loading.unload(next, planeId, job.id, t, checkRoom: false);
    }
    next = next
        .updatePlane(
          planeId,
          (p) => p.copyWith(status: PlaneStatus.stored, pickUpAtStops: false),
        )
        .copyWith(
          crew: next.crew.copyWith(
            autopilot: {
              for (final e in next.crew.autopilot.entries)
                if (e.key != planeId) e.key: e.value,
            },
          ),
        );
    return landHolding(next, plane.cityId, t, SimReport());
  }

  /// Why stored [plane] can't come out of the hangar now, or null if it
  /// can: it needs a free gate at its airport.
  RuleError? activateProblem(GameState state, Plane plane) {
    if (plane.status != PlaneStatus.stored) return RuleError.planeNotStored;
    if (freeGates(state, plane.cityId) <= 0) return RuleError.noFreeGate;
    return null;
  }

  /// Brings stored [planeId] out of the hangar to a free gate, ready to
  /// load and fly.
  GameState activatePlane(GameState state, String planeId, DateTime t) {
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    final problem = activateProblem(state, plane!);
    if (problem != null) throw RuleException(problem);
    return state.updatePlane(
      planeId,
      (p) => p.copyWith(status: PlaneStatus.parked),
    );
  }

  /// Gates at [airport]: its level's, plus more in bigger cities.
  int gates(AirportState airport) => rules.config.airports.gates(
    airport.level,
    rules.world.city(airport.cityId).size,
  );

  bool _fitsAirport(PlaneStats stats, AirportState airport) =>
      rules.fitsAirportLevel(stats.model, airport.level);

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

  /// Plans flying [planeId] through [stops] in order, leaving at [t]. With
  /// [pickUp], it also counts the jobs waiting at each stop that the plane
  /// would pick up there for later stops (boards change, so this is an
  /// estimate).
  RouteQuote quote(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime t, {
    bool pickUp = false,
  }) {
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
    int payFor(Job job, int fromLeg) {
      for (final leg in legs.skip(fromLeg)) {
        if (leg.toCityId == job.unloadCityId) {
          return job.destCityId == leg.toCityId
              ? deliveryPay(state, marked, job, leg.arriveAt)
              : 0;
        }
      }
      return 0;
    }

    var payout = 0;
    for (final job in marked.load) {
      payout += payFor(job, 0);
    }

    // Walk the trip with a copy of the load to see what each stop adds.
    final pickupsAt = List.filled(legs.length, 0);
    var pickupPayout = 0;
    if (pickUp && problems.isEmpty) {
      var aboard = marked.load;
      for (final (i, leg) in legs.indexed) {
        aboard = [
          for (final j in aboard)
            if (j.unloadCityId != leg.toCityId) j,
        ];
        if (i == legs.length - 1) break;
        final picked = pickups(
          state,
          marked.copyWith(cityId: leg.toCityId, load: aboard),
          stops.sublist(i + 1),
          leg.arriveAt,
        );
        pickupsAt[i] = picked.length;
        for (final job in picked) {
          pickupPayout += payFor(job, i + 1);
        }
        aboard = [...aboard, ...picked];
      }
    }
    return RouteQuote(
      legs: legs,
      fuel: fuel,
      expectedPayout: payout + pickupPayout,
      problems: problems.toList(),
      pickupsAt: pickupsAt,
      pickupPayout: pickupPayout,
    );
  }

  /// Jobs on the board where [plane] has just landed mid-trip that it picks
  /// up for [laterStops]: plain and special jobs bound for one of them that
  /// fit, best-paying first. Sightseeing tours start and end at one airport,
  /// so they wait for a plane that starts its trip there. [plane]'s load
  /// should already be without the jobs that leave it here.
  List<Job> pickups(
    GameState state,
    Plane plane,
    List<String> laterStops,
    DateTime t,
  ) {
    final airport = state.airport(plane.cityId);
    if (airport == null || laterStops.isEmpty) return const [];
    final candidates = [
      for (final j in airport.board)
        if (laterStops.contains(j.destCityId) &&
            j.destCityId != plane.cityId &&
            j.kind != JobKind.sightseeing)
          j,
    ]..sort((a, b) => b.payout.compareTo(a.payout));
    final loading = Loading(rules);
    final picked = <Job>[];
    var p = plane;
    for (final job in candidates) {
      if (loading.loadProblem(state, p, job, t) != null) continue;
      final aboard = job.copyWith(
        dropAtCityId: () => null,
        connectingSince: () => null,
      );
      picked.add(aboard);
      p = p.copyWith(load: [...p.load, aboard]);
    }
    return picked;
  }

  /// True if [job] reaches its destination on [plane] after its deadline.
  bool isLate(GameState state, Plane plane, Job job, DateTime t) =>
      job.deadline != null &&
      t.isAfter(
        job.deadline!.add(rules.crew.deadlineExtension(state, plane, job)),
      );

  /// Extra pay [plane]'s role gives [job]: Freighter on cargo, Express on
  /// passengers, Long haul on jobs going far enough.
  double rolePayPct(Plane plane, Job job) {
    final planes = rules.config.planes;
    final model = planes.model(plane.modelId);
    final role = planes.roleOf(model);
    if (role == null) return 0;
    return switch (role.effect) {
      'cargoPayPct' when job.type == JobType.cargo => role.value,
      'passengerPayPct' when job.type == JobType.passenger => role.value,
      'longJobPayPct'
          when rules.distanceKm(job.originCityId, job.destCityId) >=
              role.minKm =>
        role.value,
      _ => 0,
    };
  }

  /// What [job] pays if [plane] delivers it at [t].
  int deliveryPay(GameState state, Plane plane, Job job, DateTime t) {
    if (isLate(state, plane, job, t)) return 0;
    final pct =
        job.bonusPct +
        job.loadBonusPct +
        rolePayPct(plane, job) +
        rules.crew.deliveryPayPct(state, plane, job) +
        Rivals(rules).deliveryPayPct(state, job, job.destCityId);
    final pay =
        job.payout *
        (1 + pct / 100) *
        rules.crew.payMultiplier(state, plane, job);
    return pay <= 0 ? 0 : pay.round();
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
  /// now. With [pickUp], it picks up jobs for later stops as it lands at
  /// each one. Throws [RuleException] if [quote] finds a problem.
  GameState depart(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime t, {
    bool pickUp = false,
  }) {
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
    next = next.updatePlane(
      planeId,
      (p) => p.copyWith(
        pickUpAtStops: pickUp && stops.length > 1,
        tripFuel: plan.fuel,
        tripEarned: 0,
      ),
    );
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
      if (plane.leg!.isDelivery) {
        // A new plane waiting for a gate just pulls in once one is free;
        // it has flown nowhere, so it earns nothing and counts no leg.
        if (freeGates(next, plane.cityId) > 0) {
          next = next.updatePlane(
            plane.id,
            (p) => p.copyWith(
              status: PlaneStatus.parked,
              leg: () => null,
              holdingSince: () => null,
            ),
          );
          report.landedPlaneIds.add(plane.id);
        }
      } else if (_weather.canLand(next, plane, plane.cityId, t) &&
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
    final rivals = Rivals(rules);
    // Layover jobs pay their full fare on final delivery, plus any layover
    // bonus from the station agent or terminal where they wait.
    final transferPct =
        rules.crew.transferPayPct(state, city) +
        rivals.terminalEffect(state, city, 'transferPayPct');
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
    final delivered = <({Job job, int pay})>[];
    final onTime = <Job>[];
    var paid = 0;
    for (final job in plane.load) {
      if (job.destCityId == city) {
        final pay = deliveryPay(next, plane, job, t);
        final late = isLate(next, plane, job, t);
        delivered.add((job: job, pay: pay));
        if (!late) onTime.add(job);
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
        next = rivals.playerDelivered(next, job, city, pay, t);
        report.moneyEarned += pay;
        if (next.crew.autopilot.containsKey(plane.id)) {
          report.autopilotEarned += pay;
        }
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
      } else {
        staying.add(job);
      }
    }
    // Mid-trip, pick up jobs for the stops still ahead (before this
    // landing's layover drops reach the board, so they stay put).
    if (plane.remainingStops.isNotEmpty && plane.pickUpAtStops) {
      final picked = pickups(
        next,
        plane.copyWith(cityId: city, load: staying),
        plane.remainingStops,
        t,
      );
      if (picked.isNotEmpty) {
        final ids = {for (final j in picked) j.id};
        next = next.updateAirport(
          city,
          (a) => a.copyWith(
            board: [
              for (final j in a.board)
                if (!ids.contains(j.id)) j,
            ],
          ),
        );
        staying.addAll(picked);
        report.jobsPickedUp += picked.length;
      }
    }
    next = Challenges(rules).recordLanding(
      next,
      cityId: city,
      km: leg.distanceKm,
      delivered: onTime,
      paid: paid,
      connections: dropped.length,
      endsMultiStopTrip: plane.remainingStops.isEmpty && plane.tripStops > 0,
      t: t,
    );
    final until = report.until;
    final (afterCrew, extra) = rules.crew.afterLanding(
      next,
      plane,
      leg,
      delivered,
      t,
      unattended:
          until != null && until.difference(t) >= const Duration(minutes: 1),
    );
    next = afterCrew;
    report.moneyEarned += extra;
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
      tripEarned: plane.tripEarned + paid + extra,
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
        pickUpAtStops: false,
        tripFuel: 0,
        tripEarned: 0,
      ),
    );
  }

  /// What the trip [plane] is flying should make: coins already earned at
  /// earlier stops, what the jobs aboard should pay at the stops ahead if
  /// they land on schedule, and the fuel paid at departure. Jobs it may
  /// still pick up at later stops aren't counted.
  TripProfit tripProfit(GameState state, Plane plane, DateTime now) {
    final leg = plane.leg;
    if (plane.onGround || leg == null) {
      return const TripProfit(earned: 0, expected: 0, fuel: 0);
    }
    final speed = PlaneStats.of(rules, state, plane).speedKmh;
    final stops = [leg.toCityId, ...plane.remainingStops];
    final arrivals = <DateTime>[];
    var at = leg.arriveAt.isBefore(now) ? now : leg.arriveAt;
    for (final (i, stop) in stops.indexed) {
      if (i > 0) {
        at = at.add(
          rules.config.flights.realDuration(
            rules.distanceKm(stops[i - 1], stop),
            speed,
          ),
        );
      }
      arrivals.add(at);
    }
    var expected = 0;
    for (final job in plane.load) {
      for (final (i, stop) in stops.indexed) {
        if (job.destCityId == stop) {
          expected += deliveryPay(state, plane, job, arrivals[i]);
          break;
        }
        if (job.dropAtCityId == stop) break;
      }
    }
    return TripProfit(
      earned: plane.tripEarned,
      expected: expected,
      fuel: plane.tripFuel,
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
      if (!p.onGround) p,
  ]..sort((a, b) => a.leg!.arriveAt.compareTo(b.leg!.arriveAt));
}
