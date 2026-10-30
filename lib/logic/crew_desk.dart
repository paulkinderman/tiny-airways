import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'rng.dart';
import 'simulation.dart';

/// Someone on the recruitment board. [member] has a placeholder id until
/// hired.
class CrewOffer {
  const CrewOffer({
    required this.id,
    required this.member,
    required this.price,
    required this.taken,
    this.bio,
  });

  final String id;
  final CrewMember member;
  final int price;
  final bool taken;

  /// Named crew have a short bio.
  final String? bio;
}

/// The recruitment board at the home airport.
class CrewShelves {
  const CrewShelves({
    required this.rookies,
    required this.rookiesRefreshAt,
    required this.veteran,
    required this.veteranRefreshAt,
    required this.pilotPrice,
    required this.pilotClass,
  });

  /// Non-pilot rookies (refresh every 8 hours).
  final List<CrewOffer> rookies;
  final DateTime rookiesRefreshAt;

  /// The veteran of the day, or null once all 40 named crew are hired.
  final CrewOffer? veteran;
  final DateTime veteranRefreshAt;

  /// A rookie pilot from the pilot school, priced by the biggest plane
  /// class in the fleet.
  final int pilotPrice;
  final PlaneClass pilotClass;
}

/// Hiring, assigning, skill trees, staff upgrades and autopilot.
///
/// Every action takes the time it happens at and throws [RuleException]
/// when refused, like the other rules. Screens use the [CrewActions]
/// wrappers on [Simulation], which run the world up to now first.
class CrewDesk {
  const CrewDesk(this.rules);

  final Rules rules;

  GameConfig get config => rules.config;
  CrewConfig get _crew => config.crew;
  GameCrew get effects => switch (rules.crew) {
    final GameCrew crew => crew,
    _ => GameCrew(config),
  };

  // Shelves --------------------------------------------------------------

  /// A random stream for one shelf period, seeded by the airline so the
  /// shelf looks the same every time it is opened in that period.
  GameRng _shelfRng(GameState state, int period, int salt) => GameRng(
    state.createdAt.millisecondsSinceEpoch * 31 +
        period * 0x9E3779B1 +
        salt * 0x85EBCA6B,
  );

  int _period(DateTime t, int hours) =>
      t.millisecondsSinceEpoch ~/ Duration(hours: hours).inMilliseconds;

  DateTime _periodStart(int period, int hours) =>
      DateTime.fromMillisecondsSinceEpoch(
        period * Duration(hours: hours).inMilliseconds,
        isUtc: true,
      );

  /// What the next non-pilot rookie costs.
  int rookiePrice(GameState state) => _crew.hiring.rookiePrice(
    state.crew.members.where((m) => m.roleId != 'pilot').length,
  );

  /// The biggest plane class in the fleet (Small with no planes).
  PlaneClass pilotClass(GameState state) {
    var best = config.planes.classes.first;
    for (final p in state.planes) {
      final c = config.planes.planeClass(
        config.planes.model(p.modelId).classId,
      );
      if (c.rank > best.rank) best = c;
    }
    return best;
  }

  CrewShelves shelves(GameState state, DateTime t) {
    final hiring = _crew.hiring;
    final rookiePeriod = _period(t, hiring.rookieRefreshHours);
    final vetPeriod = _vetDay(state, t);
    final price = rookiePrice(state);
    final rookies = [
      for (final (i, m) in _rookies(state, rookiePeriod).indexed)
        CrewOffer(
          id: 'r$rookiePeriod.$i',
          member: m,
          price: price,
          taken: state.crew.hiredOffers.contains('r$rookiePeriod.$i'),
        ),
    ];
    final pilots = pilotClass(state);
    return CrewShelves(
      rookies: rookies,
      rookiesRefreshAt: _periodStart(
        rookiePeriod + 1,
        hiring.rookieRefreshHours,
      ),
      veteran: _veteran(state, vetPeriod),
      veteranRefreshAt: state.createdAt.add(
        Duration(hours: hiring.veteranRefreshHours * (vetPeriod + 1)),
      ),
      pilotPrice: pilots.pilotHirePrice,
      pilotClass: pilots,
    );
  }

  List<CrewMember> _rookies(GameState state, int period) {
    final cities = [for (final a in state.airports) a.cityId]..sort();
    if (cities.isEmpty) return const [];
    final rng = _shelfRng(state, period, 1);
    final roles = [
      for (final r in _crew.roles)
        if (r.id != 'pilot') r.id,
    ];
    return [
      for (var i = 0; i < _crew.hiring.rookiesOnOffer; i++)
        effects.rookie(
          rng,
          id: 'offer',
          roleId: rng.pick(roles),
          cityId: rng.pick(cities),
          price: 0,
        ),
    ];
  }

  /// Days since the airline was created, counted in veteran refreshes.
  int _vetDay(GameState state, DateTime t) =>
      t.difference(state.createdAt).inMilliseconds ~/
      Duration(hours: _crew.hiring.veteranRefreshHours).inMilliseconds;

  /// The veteran of the day: the named crew come round in a shuffled order
  /// that changes each lap, skipping anyone already hired, so nobody
  /// repeats until all of them have appeared.
  CrewOffer? _veteran(GameState state, int day) {
    final named = _crew.named;
    if (named.isEmpty) return null;
    final hiring = _crew.hiring;
    final level = _shelfRng(
      state,
      day,
      3,
    ).between(hiring.veteranMinLevel, hiring.veteranMaxLevel);
    CrewOffer offer(NamedCrew pick, {bool taken = false}) => CrewOffer(
      id: 'v$day',
      member: veteran(pick, level),
      price: hiring.veteranPrice(level),
      taken: taken,
      bio: pick.bio,
    );

    // Today's veteran already hired: show them as taken.
    for (final key in state.crew.hiredOffers) {
      if (key.startsWith('v$day:')) {
        final id = key.substring('v$day:'.length);
        return offer(named.firstWhere((n) => n.id == id), taken: true);
      }
    }
    final hired = {for (final m in state.crew.members) m.namedId};
    final lap = day ~/ named.length;
    final order = [...named];
    final rng = _shelfRng(state, lap, 2);
    for (var i = order.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final swap = order[i];
      order[i] = order[j];
      order[j] = swap;
    }
    final start = day % named.length;
    for (var k = 0; k < order.length; k++) {
      final pick = order[(start + k) % order.length];
      if (!hired.contains(pick.id)) return offer(pick);
    }
    return null;
  }

  /// [named] at [level] with their points already spent: their favourite
  /// branch to its capstone, then their signature, then the other branches.
  /// Airport staff get `level - 3` staff tiers, favourite path first.
  CrewMember veteran(NamedCrew named, int level) {
    final base = CrewMember(
      id: 'offer',
      name: named.name,
      roleId: named.roleId,
      signatureId: named.signatureId,
      namedId: named.id,
      homeCityId: named.homeCityId,
      isVeteran: true,
      hirePrice: _crew.hiring.veteranPrice(level),
      level: level,
    );
    if (!_crew.role(named.roleId).isFlightCrew) {
      final all = _crew.staffPaths[named.roleId]!;
      final paths = [
        ...all.where((p) => p.id == named.favoriteId),
        ...all.where((p) => p.id != named.favoriteId),
      ];
      var left = level - 3;
      final tiers = <String, int>{};
      for (final p in paths) {
        final n = left.clamp(0, p.tiers.length);
        if (n > 0) tiers[p.id] = n;
        left -= n;
      }
      return base.copyWith(staffTiers: tiers);
    }
    final trees = _crew.skillTrees[named.roleId]!;
    final order = [
      trees.firstWhere((b) => b.id == named.favoriteId),
      _crew.signature(named.signatureId!),
      for (final b in trees)
        if (b.id != named.favoriteId) b,
    ];
    final nodes = [
      for (final b in order)
        for (final n in b.nodes) n.id,
    ].take(_crew.skillPoints(level)).toList();
    return base.copyWith(nodes: nodes);
  }

  // Hiring ---------------------------------------------------------------

  GameState _addMember(GameState state, CrewMember member, String? offerId) =>
      state.copyWith(
        nextId: state.nextId + 1,
        crew: state.crew.copyWith(
          members: [...state.crew.members, member],
          hiredOffers: [...state.crew.hiredOffers, ?offerId],
        ),
      );

  /// Hires the shelf offer [offerId]. New crew start unassigned.
  GameState hire(GameState state, String offerId, DateTime t) {
    require(state.hasStarted, RuleError.notStarted);
    final shelf = shelves(state, t);
    final offer = [
      ...shelf.rookies,
      ?shelf.veteran,
    ].where((o) => o.id == offerId).firstOrNull;
    require(offer != null, RuleError.offerTaken);
    require(!offer!.taken, RuleError.offerTaken);
    final paid = Economy(rules).spend(state, offer.price);
    final member = CrewMember.fromJson({
      ...offer.member.toJson(),
      'id': 'c${state.nextId}',
      'hirePrice': offer.price,
    });
    final named = offer.member.namedId;
    return _addMember(
      paid,
      member,
      named == null ? offerId : '$offerId:$named',
    );
  }

  /// Hires a rookie pilot from the pilot school. They go straight to the
  /// first parked plane short of a pilot, if there is one.
  GameState hirePilot(GameState state, DateTime t) {
    require(state.hasStarted, RuleError.notStarted);
    final price = pilotClass(state).pilotHirePrice;
    final paid = Economy(rules).spend(state, price);
    final rng = GameRng(paid.rngState);
    final short = paid.planes
        .where(
          (p) =>
              p.status == PlaneStatus.parked &&
              effects.departureProblem(paid, p) != null,
        )
        .firstOrNull;
    final pilot = effects.rookie(
      rng,
      id: 'c${paid.nextId}',
      roleId: 'pilot',
      cityId: short?.cityId ?? paid.homeCityId!,
      price: price,
    );
    return _addMember(
      paid.copyWith(rngState: rng.state),
      pilot.copyWith(planeId: () => short?.id),
      null,
    );
  }

  // Assigning ------------------------------------------------------------

  CrewMember _member(GameState state, String id) {
    final m = state.crew.member(id);
    require(m != null, RuleError.unknownCrew);
    return m!;
  }

  /// True if [member] can be moved now: airport staff always, flight crew
  /// while their plane is parked.
  bool canMove(GameState state, CrewMember member) {
    final plane = member.planeId == null ? null : state.plane(member.planeId!);
    return plane == null || plane.status == PlaneStatus.parked;
  }

  /// Crew seats on [plane]: pilots it needs, and open seats for any role.
  ({int pilots, int open}) seats(Plane plane) {
    final c = config.planes.planeClass(
      config.planes.model(plane.modelId).classId,
    );
    return (pilots: c.pilotsRequired, open: c.openCrewSeats);
  }

  /// Whether [member] could join [plane]'s crew (ignoring where they are
  /// now): pilots fill the pilot seats first, then open seats; anyone else
  /// needs an open seat.
  bool hasSeatFor(GameState state, Plane plane, CrewMember member) {
    final s = seats(plane);
    final crew = [
      for (final m in state.crew.onPlane(plane.id))
        if (m.id != member.id) m,
      member,
    ];
    final pilots = crew.where((m) => m.roleId == 'pilot').length;
    final others = crew.length - pilots;
    return others <= s.open && crew.length <= s.pilots + s.open;
  }

  int staffSlots(GameState state, String cityId) =>
      config.airports.level(state.airport(cityId)!.level).staffSlots;

  GameState _move(
    GameState state,
    String memberId, {
    String? planeId,
    String? cityId,
  }) => state.copyWith(
    crew: state.crew.updateMember(
      memberId,
      (m) => m.copyWith(planeId: () => planeId, cityId: () => cityId),
    ),
  );

  /// Puts flight crew [memberId] on parked plane [planeId].
  GameState assignToPlane(
    GameState state,
    String memberId,
    String planeId,
    DateTime t,
  ) {
    final member = _member(state, memberId);
    require(_crew.role(member.roleId).isFlightCrew, RuleError.wrongRole);
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    require(plane!.status == PlaneStatus.parked, RuleError.crewBusy);
    require(canMove(state, member), RuleError.crewBusy);
    if (member.planeId == planeId) return state;
    require(hasSeatFor(state, plane, member), RuleError.noCrewSeat);
    return _move(state, memberId, planeId: planeId);
  }

  /// Puts airport staff [memberId] at the owned airport [cityId].
  GameState assignToAirport(
    GameState state,
    String memberId,
    String cityId,
    DateTime t,
  ) {
    final member = _member(state, memberId);
    require(!_crew.role(member.roleId).isFlightCrew, RuleError.wrongRole);
    require(state.ownsAirport(cityId), RuleError.notOwned);
    if (member.cityId == cityId) return state;
    final here = state.crew.atAirport(cityId).length;
    require(here < staffSlots(state, cityId), RuleError.noStaffSlot);
    return _move(state, memberId, cityId: cityId);
  }

  /// Takes [memberId] off their plane or airport.
  GameState unassign(GameState state, String memberId, DateTime t) {
    final member = _member(state, memberId);
    require(canMove(state, member), RuleError.crewBusy);
    return _move(state, memberId);
  }

  // Skill trees and staff tiers ------------------------------------------

  /// Skill points [member] hasn't spent yet.
  int unspentPoints(CrewMember member) => _crew.role(member.roleId).isFlightCrew
      ? _crew.skillPoints(member.level) - member.nodes.length
      : 0;

  /// Why [member] can't learn [nodeId] now, or null if they can.
  RuleError? learnProblem(CrewMember member, String nodeId) {
    final entry = _crew.nodes[nodeId];
    if (entry == null) return RuleError.nodeLocked;
    final (branch, node) = entry;
    final allowed = _crew.branchesFor(member.roleId, member.signatureId);
    if (!allowed.any((b) => b.id == branch.id)) return RuleError.wrongRole;
    if (member.allNodes.contains(nodeId)) return RuleError.nodeLocked;
    for (final before in branch.nodes.take(node.step - 1)) {
      if (!member.allNodes.contains(before.id)) return RuleError.nodeLocked;
    }
    if (unspentPoints(member) <= 0) return RuleError.noSkillPoints;
    return null;
  }

  GameState learn(GameState state, String memberId, String nodeId, DateTime t) {
    final member = _member(state, memberId);
    final problem = learnProblem(member, nodeId);
    if (problem != null) throw RuleException(problem);
    return state.copyWith(
      crew: state.crew.updateMember(
        memberId,
        (m) => m.copyWith(nodes: [...m.nodes, nodeId]),
      ),
    );
  }

  int respecCost(CrewMember member) =>
      (member.hirePrice * _crew.hiring.respecCostFractionOfHirePrice).round();

  /// Resets [memberId]'s tree, refunding every point, for half their hire
  /// price. Free (Legacy) nodes stay.
  GameState respec(GameState state, String memberId, DateTime t) {
    final member = _member(state, memberId);
    require(_crew.role(member.roleId).isFlightCrew, RuleError.wrongRole);
    require(member.nodes.isNotEmpty, RuleError.nodeLocked);
    final paid = Economy(rules).spend(state, respecCost(member));
    return paid.copyWith(
      crew: paid.crew.updateMember(memberId, (m) => m.copyWith(nodes: [])),
    );
  }

  /// What the next tier of [pathId] costs for [member] where they work.
  int? staffTierCost(GameState state, CrewMember member, String pathId) {
    final tier = member.tier(pathId);
    if (tier >= _crew.staffTierCosts.length || member.cityId == null) {
      return null;
    }
    return config.airports.scaledCost(
      _crew.staffTierCosts[tier],
      config.world.city(member.cityId!).size,
    );
  }

  /// Buys the next tier of [pathId] for airport staff [memberId]. Tier
  /// costs scale with the size of the city they work in.
  GameState buyStaffTier(
    GameState state,
    String memberId,
    String pathId,
    DateTime t,
  ) {
    final member = _member(state, memberId);
    final paths = _crew.staffPaths[member.roleId];
    require(paths != null, RuleError.wrongRole);
    require(paths!.any((p) => p.id == pathId), RuleError.wrongRole);
    require(member.cityId != null, RuleError.notAssigned);
    final cost = staffTierCost(state, member, pathId);
    require(cost != null, RuleError.maxTier);
    final paid = Economy(rules).spend(state, cost!);
    return paid.copyWith(
      crew: paid.crew.updateMember(
        memberId,
        (m) => m.copyWith(
          staffTiers: {...m.staffTiers, pathId: m.tier(pathId) + 1},
        ),
      ),
    );
  }

  // Autopilot ------------------------------------------------------------

  /// Sets parked [planeId] to fly [stops] round and round: from where it is
  /// to each stop in turn, then home again, loading the best-paying plain
  /// jobs at each airport. Jobs already aboard go back on the board.
  GameState startAutopilot(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime t,
  ) {
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    require(plane!.status == PlaneStatus.parked, RuleError.planeNotParked);
    require(stops.isNotEmpty, RuleError.noStops);
    require(effects.hasAutopilot(state, plane), RuleError.noAutopilot);
    var next = state;
    for (final job in plane.load) {
      next = Loading(rules).unload(next, planeId, job.id, t);
    }
    final problem = effects.autopilotProblem(
      next,
      next.plane(planeId)!,
      stops.first,
      t,
    );
    if (problem != null) throw RuleException(problem);
    next = next.copyWith(
      crew: next.crew.copyWith(
        autopilot: {
          ...next.crew.autopilot,
          planeId: AutopilotRoute(stops: [plane.cityId, ...stops]),
        },
      ),
    );
    return effects.settle(next, t, SimReport());
  }

  GameState stopAutopilot(GameState state, String planeId, DateTime t) =>
      effects.stopAutopilot(state, planeId);
}

/// The crew actions as screens call them: each runs the world up to [now]
/// first, like the other [Simulation] actions.
extension CrewActions on Simulation {
  CrewDesk get crew => CrewDesk(rules);

  GameState _now(GameState state, DateTime now) => advance(state, now).$1;

  GameState hireCrew(GameState state, String offerId, DateTime now) {
    final s = _now(state, now);
    return crew.hire(s, offerId, s.simulatedTo);
  }

  GameState hirePilot(GameState state, DateTime now) {
    final s = _now(state, now);
    return crew.hirePilot(s, s.simulatedTo);
  }

  GameState assignCrewToPlane(
    GameState state,
    String memberId,
    String planeId,
    DateTime now,
  ) {
    final s = _now(state, now);
    return crew.assignToPlane(s, memberId, planeId, s.simulatedTo);
  }

  GameState assignCrewToAirport(
    GameState state,
    String memberId,
    String cityId,
    DateTime now,
  ) {
    final s = _now(state, now);
    return crew.assignToAirport(s, memberId, cityId, s.simulatedTo);
  }

  GameState unassignCrew(GameState state, String memberId, DateTime now) {
    final s = _now(state, now);
    return crew.unassign(s, memberId, s.simulatedTo);
  }

  GameState learnSkill(
    GameState state,
    String memberId,
    String nodeId,
    DateTime now,
  ) {
    final s = _now(state, now);
    return crew.learn(s, memberId, nodeId, s.simulatedTo);
  }

  GameState respecCrew(GameState state, String memberId, DateTime now) {
    final s = _now(state, now);
    return crew.respec(s, memberId, s.simulatedTo);
  }

  GameState buyStaffTier(
    GameState state,
    String memberId,
    String pathId,
    DateTime now,
  ) {
    final s = _now(state, now);
    return crew.buyStaffTier(s, memberId, pathId, s.simulatedTo);
  }

  GameState startAutopilot(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime now,
  ) {
    final s = _now(state, now);
    return crew.startAutopilot(s, planeId, stops, s.simulatedTo);
  }

  GameState stopAutopilot(GameState state, String planeId, DateTime now) {
    final s = _now(state, now);
    return crew.stopAutopilot(s, planeId, s.simulatedTo);
  }
}
