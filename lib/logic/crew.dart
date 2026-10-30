import 'dart:math' as math;

import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'economy.dart';
import 'flights.dart';
import 'loading.dart';
import 'rng.dart';
import 'rules.dart';

/// Effects that add up across crew (and that a first officer gives at a
/// reduced share when they are percentages or slots). Every other effect is
/// a capability whose strongest value wins: Autopilot, Tailwind, Talk show.
bool _sums(String effect) =>
    effect.endsWith('Pct') ||
    const {
      'cargoSlots',
      'coinsPerPassenger',
      'vipDeadlineMinutes',
      'fullHoldSlack',
    }.contains(effect);

bool _scales(String effect) => effect.endsWith('Pct') || effect == 'cargoSlots';

/// Totals of a group of crew's effects.
class CrewTotals {
  CrewTotals._(this._values);

  /// Adds [effects] at [share] (1, or the first officer's share).
  factory CrewTotals.of(Iterable<(Effect, double)> effects) {
    final values = <String, double>{};
    for (final (e, share) in effects) {
      final v = _scales(e.effect) ? e.value * share : e.value;
      final old = values[e.effect];
      values[e.effect] = old == null
          ? v
          : _sums(e.effect)
          ? old + v
          : math.max(old, v);
    }
    return CrewTotals._(values);
  }

  static final empty = CrewTotals._(const {});

  final Map<String, double> _values;

  double operator [](String effect) => _values[effect] ?? 0;
  bool has(String effect) => _values.containsKey(effect);
}

/// The crew aboard one plane.
class PlaneCrew {
  PlaneCrew._(this.members, this.captain, this.totals, this.byMember);

  factory PlaneCrew.of(GameConfig config, GameState state, String planeId) {
    final members = state.crew.onPlane(planeId);
    final pilots = [
      for (final m in members)
        if (m.roleId == 'pilot') m,
    ];
    CrewMember? captain;
    for (final p in pilots) {
      if (captain == null || p.level > captain.level) captain = p;
    }
    final factor = config.crew.xp.firstOfficerSkillFactor;
    final byMember = <String, CrewTotals>{};
    final all = <(Effect, double)>[];
    for (final m in members) {
      final share = m.roleId == 'pilot' && m != captain ? factor : 1.0;
      final effects = [for (final e in memberEffects(config, m)) (e, share)];
      byMember[m.id] = CrewTotals.of(effects);
      all.addAll(effects);
    }
    return PlaneCrew._(members, captain, CrewTotals.of(all), byMember);
  }

  final List<CrewMember> members;

  /// The highest-level pilot aboard; the other pilots are first officers.
  final CrewMember? captain;
  final CrewTotals totals;
  final Map<String, CrewTotals> byMember;

  int get pilots => members.where((m) => m.roleId == 'pilot').length;

  bool captainHas(GameConfig config, String effect) =>
      captain != null &&
      memberEffects(config, captain!).any((e) => e.effect == effect);
}

/// Everything [member] brings: their role's base bonus plus learned nodes
/// (flight crew) or bought staff tiers (airport staff).
List<Effect> memberEffects(GameConfig config, CrewMember member) {
  final crew = config.crew;
  final role = crew.role(member.roleId);
  return [
    role.base,
    if (role.isFlightCrew)
      for (final id in member.allNodes)
        if (crew.nodes[id] case (_, final node)) node,
    if (!role.isFlightCrew)
      for (final path in crew.staffPaths[member.roleId]!)
        if (member.tier(path.id) > 0) path.tiers[member.tier(path.id) - 1],
  ];
}

/// The crew rules: bonuses from the crew aboard each plane and the staff at
/// each airport, crew XP, free pilots and autopilot.
class GameCrew extends CrewEffects {
  const GameCrew(this.config);

  final GameConfig config;

  Rules get _rules => Rules(config, crew: this);

  PlaneCrew aboard(GameState state, Plane plane) =>
      PlaneCrew.of(config, state, plane.id);

  /// Totals for the staff working at [cityId].
  CrewTotals staffAt(GameState state, String cityId) {
    final staff = state.crew.atAirport(cityId);
    if (staff.isEmpty) return CrewTotals.empty;
    return CrewTotals.of([
      for (final m in staff)
        for (final e in memberEffects(config, m)) (e, 1.0),
    ]);
  }

  PlaneClass _class(Plane plane) =>
      config.planes.planeClass(config.planes.model(plane.modelId).classId);

  bool _onAutopilot(GameState state, Plane plane) =>
      state.crew.autopilot.containsKey(plane.id);

  @override
  String? departureProblem(GameState state, Plane plane) {
    final needed = _class(plane).pilotsRequired;
    final have = aboard(state, plane).pilots;
    if (have >= needed) return null;
    return needed == 1 ? 'Needs a pilot' : 'Needs $needed pilots';
  }

  @override
  int captainLevel(GameState state, Plane plane) =>
      aboard(state, plane).captain?.level ?? 0;

  @override
  bool landsInFog(GameState state, Plane plane) =>
      aboard(state, plane).totals.has('fogLanding');

  @override
  bool hasRole(GameState state, Plane plane, String roleId) =>
      state.crew.onPlane(plane.id).any((m) => m.roleId == roleId);

  @override
  double speedPct(GameState state, Plane plane) {
    final crew = aboard(state, plane).totals;
    // Shortcuts cut flight time; as speed, -10% time is +11.1% speed.
    final time = crew['flightTimePct'];
    final faster = time == 0 ? 0.0 : (100 / (100 + time) - 1) * 100;
    return crew['speedPct'] + faster;
  }

  @override
  double rangePct(GameState state, Plane plane) {
    final crew = aboard(state, plane).totals;
    return crew['rangePct'] +
        (plane.load.isEmpty ? crew['emptyLegRangePct'] : 0);
  }

  @override
  double fuelPct(GameState state, Plane plane) =>
      aboard(state, plane).totals['fuelPct'];

  @override
  bool ignoresHeadwind(GameState state, Plane plane) =>
      aboard(state, plane).totals.has('ignoreHeadwind');

  @override
  int extraCargoSlots(GameState state, Plane plane) =>
      aboard(state, plane).totals['cargoSlots'].floor();

  @override
  int jobSlots(GameState state, Plane plane, Job job) {
    if (job.kind != JobKind.bulk) return job.slots;
    final crew = aboard(state, plane).totals;
    return crew.has('bulkSlots') ? crew['bulkSlots'].round() : job.slots;
  }

  @override
  int fullHoldSlack(GameState state, Plane plane) =>
      aboard(state, plane).totals['fullHoldSlack'].round();

  /// Scheduled hours for [job]'s whole trip at [plane]'s model speed.
  double _hours(Plane plane, Job job) =>
      _rules.distanceKm(job.originCityId, job.destCityId) /
      config.planes.model(plane.modelId).speedKmh;

  @override
  double deliveryPayPct(GameState state, Plane plane, Job job) {
    final crew = aboard(state, plane);
    final t = crew.totals;
    final autopilot = _onAutopilot(state, plane);
    final long = _hours(plane, job) > 2;
    final cross = _rules.crossesRegions(job.originCityId, job.destCityId);
    var pct = 0.0;
    if (job.type == JobType.passenger) {
      pct += t['passengerPayPct'];
      if (long) pct += t['longFlightPassengerPayPct'];
      if (t.has('coinsPerPassenger') && job.payout > 0) {
        pct += t['coinsPerPassenger'] * 100 / job.payout;
      }
      if (!autopilot && job.loadBonusPct > 0) pct += t['charterBonusPct'];
    } else {
      pct += t['cargoPayPct'];
      if (!autopilot && job.loadBonusPct > 0) pct += t['fullHoldBonusPct'];
    }
    if (job.kind == JobKind.fragile) pct += t['fragilePayPct'];
    pct += cross ? t['crossRegionPayPct'] : t['inRegionPayPct'];
    if (long) pct += t['longFlightPayPct'];
    for (final m in crew.members) {
      if (job.originCityId == m.homeCityId || job.destCityId == m.homeCityId) {
        pct += crew.byMember[m.id]!['homeLegPayPct'];
      }
    }
    // Autopilot never earns the charter or full-hold bonus.
    if (autopilot) pct -= job.loadBonusPct;
    return pct;
  }

  @override
  double payMultiplier(GameState state, Plane plane, Job job) {
    final t = aboard(state, plane).totals;
    var m = 1.0;
    if (_onAutopilot(state, plane)) m *= _autopilotPayPct / 100;
    final special = config.jobs.special[job.kind.name];
    if (job.kind == JobKind.vip && t.has('vipPayMultiplier')) {
      m *= t['vipPayMultiplier'] / special!.payMultiplier;
    }
    if (job.kind == JobKind.bulk && t.has('bulkPayMultiplier')) {
      m *= t['bulkPayMultiplier'] / special!.payMultiplier;
    }
    return m;
  }

  double get _autopilotPayPct => config.crew.nodes.values
      .firstWhere((e) => e.$2.effect == 'autopilot')
      .$2
      .value;

  @override
  Duration deadlineExtension(GameState state, Plane plane, Job job) {
    if (job.kind != JobKind.vip) return Duration.zero;
    final minutes = aboard(state, plane).totals['vipDeadlineMinutes'];
    return Duration(minutes: minutes.round());
  }

  @override
  double boardPayPct(GameState state, String cityId, JobType type) =>
      staffAt(state, cityId)['jobPayPct'];

  @override
  int extraBoardSlots(GameState state, String cityId) {
    final staff = staffAt(state, cityId);
    return (staff['boardSlots'] + staff['connectionBoardSlots']).round();
  }

  @override
  bool favoursConnections(GameState state, String cityId) =>
      staffAt(state, cityId)['connectionBoardSlots'] > 0;

  @override
  double specialChancePct(GameState state, String cityId, JobKind kind) {
    final parked = [
      for (final p in state.planes)
        if (p.status == PlaneStatus.parked && p.cityId == cityId)
          aboard(state, p).totals,
    ];
    switch (kind) {
      case JobKind.vip:
        return staffAt(state, cityId)['vipChancePct'] +
            parked.fold(0.0, (sum, t) => sum + t['vipChancePct']);
      case JobKind.fragile:
        final pct = parked.fold(0.0, (best, t) {
          return math.max(best, t['fragileChancePct']);
        });
        return config.jobs.special['fragile']!.chancePct * pct / 100;
      default:
        return 0;
    }
  }

  @override
  double transferPayPct(GameState state, String cityId) =>
      staffAt(state, cityId)['transferPayPct'];

  @override
  int boardRefillsPerRotation(GameState state, String cityId) {
    var refills = 1;
    for (final m in state.crew.members) {
      if (m.homeCityId != cityId || !m.isAssigned) continue;
      for (final e in memberEffects(config, m)) {
        if (e.effect == 'homeBoardRefillMultiplier') {
          refills = math.max(refills, e.value.round());
        }
      }
    }
    return refills;
  }

  // Crew XP ------------------------------------------------------------

  /// XP each crew member aboard earns for [leg], before mentors and
  /// Passport: distance / 10 x plane factor x load factor x (1 + bonuses).
  ({
    double base,
    double planeFactor,
    int used,
    int capacity,
    double loadFactor,
    double bonusPct,
  })
  legXp(GameState state, Plane plane, FlightLeg leg, List<Job> delivered) {
    final xp = config.crew.xp;
    final stats = PlaneStats.of(_rules, state, plane);
    final capacity = stats.seats + stats.cargoSlots;
    var used = 0;
    for (final j in plane.load) {
      used += jobSlots(state, plane, j);
    }
    used = math.min(used, capacity);
    final load = capacity == 0
        ? 1.0
        : math.max(xp.minLoadFactor, used / capacity).clamp(0.0, 1.0);
    var bonus = 0.0;
    if (_rules.crossesRegions(leg.fromCityId, leg.toCityId)) {
      bonus += xp.crossRegionBonusPct;
    }
    if (delivered.any((j) => j.kind == JobKind.vip || j.kind == JobKind.bulk)) {
      bonus += xp.vipOrBulkBonusPct;
    }
    bonus += plane.tripStops * xp.perEarlierStopBonusPct;
    final connecting =
        plane.remainingStops.isNotEmpty ||
        plane.load.any((j) => j.dropAtCityId == leg.toCityId);
    if (connecting) {
      bonus += staffAt(state, leg.toCityId)['connectingCrewXpPct'];
    }
    return (
      base: leg.distanceKm / xp.kmPerXp,
      planeFactor: stats.planeClass.crewXpFactor,
      used: used,
      capacity: capacity,
      loadFactor: load,
      bonusPct: bonus,
    );
  }

  /// Adds [xp] to [member], levelling up as far as it reaches.
  CrewMember gainXp(CrewMember member, int xp) {
    final crew = config.crew;
    var level = member.level;
    var total = member.xp + xp;
    while (level < crew.maxLevel && total >= crew.xpToNext(level)) {
      total -= crew.xpToNext(level);
      level++;
    }
    if (level >= crew.maxLevel) total = 0;
    return member.copyWith(level: level, xp: total);
  }

  @override
  (GameState, int) afterLanding(
    GameState state,
    Plane plane,
    FlightLeg leg,
    List<({Job job, int pay})> delivered,
    DateTime t, {
    required bool unattended,
  }) {
    final crew = aboard(state, plane);
    if (crew.members.isEmpty) return (state, 0);

    // Lucky and Red-eye pay extra coins.
    final rng = GameRng(state.rngState);
    final luck = crew.totals['doublePayChancePct'];
    final jackpot = crew.totals.has('luckyPayMultiplier')
        ? crew.totals['luckyPayMultiplier']
        : 2.0;
    final overnight = unattended ? crew.totals['overnightPayPct'] : 0.0;
    var extra = 0.0;
    for (final d in delivered) {
      if (d.pay <= 0) continue;
      if (luck > 0 && rng.chance(luck)) extra += d.pay * (jackpot - 1);
      extra += d.pay * overnight / 100;
    }
    var next = state.copyWith(rngState: rng.state);
    if (extra.round() > 0) next = Economy(_rules).earn(next, extra.round());

    final xp = legXp(state, plane, leg, [for (final d in delivered) d.job]);
    final cross = _rules.crossesRegions(leg.fromCityId, leg.toCityId);
    final legacy = crew.members.where(
      (m) => crew.byMember[m.id]!.has('legacyNode'),
    );
    var members = next.crew;
    for (final m in crew.members) {
      var mentors = 0.0;
      for (final other in crew.members) {
        if (other.id != m.id) {
          mentors += crew.byMember[other.id]!['mentorXpPct'];
        }
      }
      final passport =
          cross && crew.byMember[m.id]!.has('crossRegionXpMultiplier')
          ? crew.byMember[m.id]!['crossRegionXpMultiplier']
          : 1.0;
      final bonus = xp.bonusPct + mentors;
      final earned =
          (xp.base *
                  xp.planeFactor *
                  xp.loadFactor *
                  (1 + bonus / 100) *
                  passport)
              .round();
      var grown = gainXp(m, earned).copyWith(
        lastFlight: CrewFlightXp(
          fromCityId: leg.fromCityId,
          toCityId: leg.toCityId,
          distanceKm: leg.distanceKm,
          modelId: plane.modelId,
          planeFactor: xp.planeFactor,
          loadUsed: xp.used,
          loadCapacity: xp.capacity,
          loadFactor: xp.loadFactor,
          bonusPct: (1 + bonus / 100) * passport * 100 - 100,
          xp: earned,
        ),
      );
      grown = _inheritLegacy(m, grown, legacy);
      members = members.updateMember(m.id, (_) => grown);
    }
    return (next.copyWith(crew: members), extra.round());
  }

  /// Legacy: crew who reach level 6 flying with a Legacy mentor get the
  /// mentor's first signature node they don't have, once.
  CrewMember _inheritLegacy(
    CrewMember before,
    CrewMember after,
    Iterable<CrewMember> mentors,
  ) {
    const level = 6;
    if (before.level >= level || after.level < level) return after;
    if (after.bonusNodes.isNotEmpty) return after;
    for (final mentor in mentors) {
      if (mentor.id == before.id || mentor.signatureId == null) continue;
      for (final node in config.crew.signature(mentor.signatureId!).nodes) {
        if (!after.allNodes.contains(node.id)) {
          return after.copyWith(bonusNodes: [node.id]);
        }
      }
    }
    return after;
  }

  // Free pilots and autopilot --------------------------------------------

  /// A rookie with a random name from [cityId]'s continent and a random
  /// signature (flight crew only).
  CrewMember rookie(
    GameRng rng, {
    required String id,
    required String roleId,
    required String cityId,
    required int price,
  }) {
    final city = config.world.city(cityId);
    final names = config.crew.rookieNames[city.regionId]!;
    final flight = config.crew.role(roleId).isFlightCrew;
    return CrewMember(
      id: id,
      name: '${rng.pick(names.first)} ${rng.pick(names.last)}',
      roleId: roleId,
      signatureId: flight ? rng.pick(config.crew.signatures).id : null,
      homeCityId: cityId,
      hirePrice: price,
    );
  }

  @override
  GameState settle(GameState state, DateTime t, SimReport report) {
    var next = _tidy(state);
    if (config.crew.hiring.freePilotWithPlane) next = _freePilots(next);
    return _runAutopilot(next, t, report);
  }

  /// Unassigns crew from planes or airports that are gone, and drops
  /// autopilot routes for planes that are gone.
  GameState _tidy(GameState state) {
    final crew = state.crew;
    bool stale(CrewMember m) =>
        (m.planeId != null && state.plane(m.planeId!) == null) ||
        (m.cityId != null && !state.ownsAirport(m.cityId!));
    final gone = crew.autopilot.keys.where((id) => state.plane(id) == null);
    if (!crew.members.any(stale) && gone.isEmpty) return state;
    return state.copyWith(
      crew: crew.copyWith(
        members: [
          for (final m in crew.members)
            stale(m) ? m.copyWith(planeId: () => null, cityId: () => null) : m,
        ],
        autopilot: {
          for (final e in crew.autopilot.entries)
            if (state.plane(e.key) != null) e.key: e.value,
        },
      ),
    );
  }

  /// Every new plane comes with one rookie pilot.
  GameState _freePilots(GameState state) {
    final fresh = [
      for (final p in state.planes)
        if (!state.crew.staffedPlaneIds.contains(p.id)) p,
    ];
    if (fresh.isEmpty) return state;
    final rng = GameRng(state.rngState);
    var nextId = state.nextId;
    final hired = <CrewMember>[];
    for (final p in fresh) {
      hired.add(
        rookie(
          rng,
          id: 'c${nextId++}',
          roleId: 'pilot',
          cityId: p.cityId,
          price: _class(p).pilotHirePrice,
        ).copyWith(planeId: () => p.id),
      );
    }
    return state.copyWith(
      rngState: rng.state,
      nextId: nextId,
      crew: state.crew.copyWith(
        members: [...state.crew.members, ...hired],
        staffedPlaneIds: [
          ...state.crew.staffedPlaneIds,
          for (final p in fresh) p.id,
        ],
      ),
    );
  }

  /// True if [plane]'s captain has learned Autopilot.
  bool hasAutopilot(GameState state, Plane plane) =>
      aboard(state, plane).captainHas(config, 'autopilot');

  /// Why [plane] can't fly the autopilot leg to [to] from where it is
  /// parked, or null if it can.
  RuleError? autopilotProblem(
    GameState state,
    Plane plane,
    String to,
    DateTime t,
  ) {
    if (!hasAutopilot(state, plane)) return RuleError.noAutopilot;
    final problems = Flights(_rules).quote(state, plane.id, [to], t).problems;
    return problems.isEmpty ? null : problems.first;
  }

  /// Sends parked planes on autopilot off on their next leg, loading the
  /// best-paying plain jobs bound there first. A plane whose route has
  /// become impossible comes off autopilot and waits.
  GameState _runAutopilot(GameState state, DateTime t, SimReport report) {
    if (state.crew.autopilot.isEmpty) return state;
    var next = state;
    final ids = state.crew.autopilot.keys.toList()..sort();
    for (final id in ids) {
      final plane = next.plane(id)!;
      if (plane.status != PlaneStatus.parked) continue;
      final route = next.crew.autopilot[id]!;
      final from = route.stops[(route.next - 1) % route.stops.length];
      final to = route.stops[route.next];
      final problem = plane.cityId != from
          ? RuleError.badDropCity
          : autopilotProblem(next, plane, to, t);
      if (problem != null) {
        next = stopAutopilot(next, id);
        report.autopilotStoppedIds.add(id);
        continue;
      }
      next = _autoLoad(next, plane, to, t);
      try {
        next = Flights(_rules).depart(next, id, [to], t);
      } on RuleException {
        next = stopAutopilot(next, id);
        report.autopilotStoppedIds.add(id);
        continue;
      }
      next = next.copyWith(
        crew: next.crew.copyWith(
          autopilot: {...next.crew.autopilot, id: route.advanced()},
        ),
      );
    }
    return next;
  }

  /// Autopilot loading: plain jobs bound for [to], best-paying first; never
  /// special jobs or part crates.
  GameState _autoLoad(GameState state, Plane plane, String to, DateTime t) {
    final loading = Loading(_rules);
    final candidates = [
      for (final j in state.airport(plane.cityId)!.board)
        if (j.destCityId == to && j.kind == JobKind.standard) j,
    ]..sort((a, b) => b.payout.compareTo(a.payout));
    var next = state;
    for (final job in candidates) {
      if (loading.loadProblem(next, next.plane(plane.id)!, job, t) == null) {
        next = loading.load(next, plane.id, job.id, t);
      }
    }
    return next;
  }

  GameState stopAutopilot(GameState state, String planeId) => state.copyWith(
    crew: state.crew.copyWith(
      autopilot: {
        for (final e in state.crew.autopilot.entries)
          if (e.key != planeId) e.key: e.value,
      },
    ),
  );
}
