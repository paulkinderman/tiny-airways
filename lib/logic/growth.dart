import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'simulation.dart';

/// The three per-plane upgrade tracks.
enum PlaneTrack { capacity, cargo, speed, range }

/// Growth: the hangar (buying planes and upgrades), the airport
/// shop, airport levels and upgrade paths, region licenses and what each
/// airline level unlocks.
///
/// Every action takes the time it happens at and refuses with
/// [RuleException] (changing nothing) when the rules say no.
class Growth {
  const Growth(this.rules);

  final Rules rules;

  GameConfig get _config => rules.config;
  Economy get _economy => Economy(rules);
  JobBoards get _boards => JobBoards(rules);
  Flights get _flights => Flights(rules);

  // ---------------------------------------------------------------------
  // Hangar

  /// The airline level a hangar plane unlocks at: its own level, or its
  /// class's level if that is later (Medium at 5, Large at 20).
  int unlockLevel(PlaneModel model) {
    final classLevel = _config.progression.planeClassUnlockLevel[model.classId];
    final own = model.unlockLevel ?? 0;
    return classLevel != null && classLevel > own ? classLevel : own;
  }

  bool isUnlocked(GameState state, PlaneModel model) =>
      !model.isSpecial && state.player.level >= unlockLevel(model);

  /// Where a new [model] would be delivered: the home airport if it has a
  /// free gate big enough, otherwise the owned airport nearest home that
  /// does. When every airport that can take it is out of gates, the plane
  /// is still delivered: it circles the nearest one (home first) until a
  /// gate frees up. Null only if no owned airport is big enough.
  String? deliveryAirport(GameState state, PlaneModel model) =>
      _deliveryAirport(state, model, needGate: true) ??
      _deliveryAirport(state, model, needGate: false);

  /// Whether a new [model] would have to wait for a gate, because every
  /// airport big enough for it is full.
  bool deliveryWaitsForGate(GameState state, PlaneModel model) =>
      _deliveryAirport(state, model, needGate: true) == null &&
      _deliveryAirport(state, model, needGate: false) != null;

  String? _deliveryAirport(
    GameState state,
    PlaneModel model, {
    required bool needGate,
  }) {
    final home = state.homeCityId;
    if (home == null) return null;
    final rank = _config.planes.planeClass(model.classId).rank;
    bool fits(AirportState a) =>
        _config.planes
                .planeClass(_config.airports.level(a.level).maxPlaneClass)
                .rank >=
            rank &&
        (!needGate || _flights.freeGates(state, a.cityId) > 0);
    final options = [
      for (final a in state.airports)
        if (fits(a)) a.cityId,
    ];
    if (options.isEmpty) return null;
    if (options.contains(home)) return home;
    options.sort(
      (a, b) => rules.distanceKm(home, a).compareTo(rules.distanceKm(home, b)),
    );
    return options.first;
  }

  /// How many of [modelId] the airline owns.
  int ownedCount(GameState state, String modelId) =>
      state.planes.where((p) => p.modelId == modelId).length;

  /// Why [model] can't be bought now, or null if it can. Any number of the
  /// same model may be owned, and the fleet has no size cap (pilots are
  /// capped instead); only money and an airport big enough limit buying.
  RuleError? buyPlaneProblem(GameState state, PlaneModel model) {
    if (!state.hasStarted) return RuleError.notStarted;
    if (model.isSpecial || model.price == null) return RuleError.notForSale;
    if (!isUnlocked(state, model)) return RuleError.levelTooLow;
    if (deliveryAirport(state, model) == null) return RuleError.noGate;
    if (state.player.money < model.price!) return RuleError.notEnoughMoney;
    return null;
  }

  /// Buys a [modelId] from the hangar. It is delivered parked at
  /// [deliveryAirport] with nothing aboard, or circling it until a gate
  /// frees up if every gate there is taken.
  GameState buyPlane(GameState state, String modelId, [DateTime? now]) {
    require(_config.planes.hasModel(modelId), RuleError.unknownPlane);
    final model = _config.planes.model(modelId);
    final problem = buyPlaneProblem(state, model);
    if (problem != null) throw RuleException(problem, modelId);
    final cityId = deliveryAirport(state, model)!;
    final waits = _flights.freeGates(state, cityId) <= 0;
    final t = now ?? state.simulatedTo;
    final paid = _economy.spend(state, model.price!);
    return paid.copyWith(
      planes: [
        ...paid.planes,
        Plane(
          id: 'p${paid.nextId}',
          modelId: modelId,
          cityId: cityId,
          status: waits ? PlaneStatus.holding : PlaneStatus.parked,
          leg: waits ? FlightLeg.delivery(cityId, t) : null,
          holdingSince: waits ? t : null,
        ),
      ],
      nextId: paid.nextId + 1,
    );
  }

  /// Whether [plane] has [track] at all: only planes with both seats and a
  /// hold have a separate cargo track.
  bool hasTrack(Plane plane, PlaneTrack track) =>
      track != PlaneTrack.cargo ||
      _config.planes.model(plane.modelId).hasCargoTrack;

  int trackLevel(Plane plane, PlaneTrack track) => switch (track) {
    PlaneTrack.capacity => plane.upgrades.capacity,
    PlaneTrack.cargo => plane.upgrades.cargo,
    PlaneTrack.speed => plane.upgrades.speed,
    PlaneTrack.range => plane.upgrades.range,
  };

  /// What the next level of [track] costs on [plane], or null if it is
  /// maxed out or the plane can't be upgraded (special planes have no
  /// price to scale from). Use [hasTrack] first: a track the plane doesn't
  /// have also reads as null.
  int? planeUpgradeCost(Plane plane, PlaneTrack track) {
    final model = _config.planes.model(plane.modelId);
    final up = _config.planes.upgrades;
    final level = trackLevel(plane, track);
    if (!hasTrack(plane, track)) return null;
    if (model.price == null || level >= up.maxLevel) return null;
    return (model.price! * up.costFractionOfPrice[level]).round();
  }

  /// Buys the next level of [track] on [planeId]. Upgrades work anywhere,
  /// even mid-flight; a leg already in the air keeps its times.
  GameState upgradePlane(GameState state, String planeId, PlaneTrack track) {
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    final model = _config.planes.model(plane!.modelId);
    require(model.price != null, RuleError.notForSale);
    require(hasTrack(plane, track), RuleError.noCargoTrack);
    final cost = planeUpgradeCost(plane, track);
    require(cost != null, RuleError.maxLevel);
    final paid = _economy.spend(state, cost!);
    final u = plane.upgrades;
    return paid.updatePlane(
      planeId,
      (p) => p.copyWith(
        upgrades: PlaneUpgrades(
          capacity: u.capacity + (track == PlaneTrack.capacity ? 1 : 0),
          cargo: u.cargo + (track == PlaneTrack.cargo ? 1 : 0),
          speed: u.speed + (track == PlaneTrack.speed ? 1 : 0),
          range: u.range + (track == PlaneTrack.range ? 1 : 0),
        ),
      ),
    );
  }

  /// The track that adds room for [type] jobs on [plane]: seats on the
  /// capacity track, hold slots on the cargo track (or on the capacity
  /// track for cargo-only planes). Null if no track adds that kind of room.
  PlaneTrack? roomTrack(Plane plane, JobType type) {
    final model = _config.planes.model(plane.modelId);
    if (type == JobType.passenger) {
      return model.seats > 0 ? PlaneTrack.capacity : null;
    }
    if (model.seats == 0) return PlaneTrack.capacity;
    return model.hasCargoTrack ? PlaneTrack.cargo : null;
  }

  /// The upgrade that would make room for [job] on parked [plane] when it
  /// doesn't fit now: the track whose next level adds just enough seats or
  /// slots. Null if [job] fits already, fails for another reason, or one
  /// more level wouldn't make room. Money is not checked, so the screen
  /// can still offer the upgrade with its price.
  PlaneTrack? roomUpgradeFor(
    GameState state,
    Plane plane,
    Job job,
    DateTime t,
  ) {
    final loading = Loading(rules);
    if (loading.loadProblem(state, plane, job, t) != RuleError.noRoom) {
      return null;
    }
    final track = roomTrack(plane, job.type);
    if (track == null || planeUpgradeCost(plane, track) == null) return null;
    final load = loading.summary(state, plane, t);
    final free = job.type == JobType.passenger
        ? load.freeSeats
        : load.freeCargoSlots;
    final needed = rules.crew.jobSlots(state, plane, job) - free;
    return needed <= _config.planes.upgrades.capacityPerLevel ? track : null;
  }

  /// Buys the upgrade [roomUpgradeFor] names and loads [jobId] onto
  /// [planeId], as one action: if either step is refused, nothing changes.
  GameState upgradeAndLoad(
    GameState state,
    String planeId,
    String jobId,
    DateTime t, {
    String? dropAtCityId,
  }) {
    final plane = state.plane(planeId);
    require(plane != null, RuleError.unknownPlane);
    final job = state
        .airport(plane!.cityId)
        ?.board
        .where((j) => j.id == jobId)
        .firstOrNull;
    require(job != null, RuleError.jobNotHere);
    final track = roomUpgradeFor(state, plane, job!, t);
    require(track != null, RuleError.noRoom);
    final upgraded = upgradePlane(state, planeId, track!);
    return Loading(rules)
        .load(upgraded, planeId, jobId, t, dropAtCityId: dropAtCityId);
  }

  /// Names [planeId]; an empty name goes back to the model's name.
  GameState renamePlane(GameState state, String planeId, String name) {
    require(state.plane(planeId) != null, RuleError.unknownPlane);
    final trimmed = name.trim();
    final nickname = trimmed.isEmpty
        ? null
        : trimmed.substring(0, trimmed.length.clamp(0, maxNicknameLength));
    return state.updatePlane(
      planeId,
      (p) => p.copyWith(nickname: () => nickname),
    );
  }

  static const maxNicknameLength = 16;

  // ---------------------------------------------------------------------
  // Region licenses

  /// Regions the airline may buy airports in: the home region, every region
  /// with a license, and any region it already owns an airport in (the free
  /// starting airport can sit across a border).
  Set<String> licensedRegions(GameState state) => {
    if (state.homeCityId != null) rules.world.city(state.homeCityId!).regionId,
    ...state.player.licenses,
    for (final a in state.airports) rules.world.city(a.cityId).regionId,
  };

  bool isLicensed(GameState state, String regionId) =>
      licensedRegions(state).contains(regionId);

  /// The next license on sale (the nth one bought), or null when every
  /// license has been bought. Licenses can be spent on any region.
  RegionLicense? nextLicense(GameState state) {
    final all = _config.progression.regionLicenses;
    final bought = state.player.licenses.length;
    return bought < all.length ? all[bought] : null;
  }

  /// Why [regionId]'s license can't be bought now, or null if it can.
  RuleError? licenseProblem(GameState state, String regionId) {
    if (!state.hasStarted) return RuleError.notStarted;
    if (!rules.world.hasRegion(regionId)) return RuleError.unknownCity;
    if (isLicensed(state, regionId)) return RuleError.alreadyOwned;
    final next = nextLicense(state);
    if (next == null) return RuleError.noLicenseLeft;
    if (state.player.level < next.airlineLevel) return RuleError.levelTooLow;
    if (state.player.money < next.cost) return RuleError.notEnoughMoney;
    return null;
  }

  GameState buyLicense(GameState state, String regionId) {
    final problem = licenseProblem(state, regionId);
    if (problem != null) throw RuleException(problem, regionId);
    final paid = _economy.spend(state, nextLicense(state)!.cost);
    return paid.copyWith(
      player: paid.player.copyWith(
        licenses: [...paid.player.licenses, regionId],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Airport shop

  /// `base(size) x (1 + growth x airportsOwned)`.
  int airportPrice(GameState state, String cityId) =>
      _config.airports.purchasePrice(
        citySize: rules.world.city(cityId).size,
        airportsOwned: state.airports.length,
      );

  /// The owned airport nearest [cityId], and how far it is.
  ({String cityId, double km})? nearestOwned(GameState state, String cityId) {
    ({String cityId, double km})? best;
    for (final a in state.airports) {
      final km = rules.distanceKm(a.cityId, cityId);
      if (best == null || km < best.km) best = (cityId: a.cityId, km: km);
    }
    return best;
  }

  /// Why [cityId]'s airport can't be bought now, or null if it can.
  RuleError? buyAirportProblem(GameState state, String cityId) {
    if (!state.hasStarted) return RuleError.notStarted;
    if (!rules.world.hasCity(cityId)) return RuleError.unknownCity;
    if (state.ownsAirport(cityId)) return RuleError.alreadyOwned;
    if (!isLicensed(state, rules.world.city(cityId).regionId)) {
      return RuleError.regionLocked;
    }
    if (state.player.money < airportPrice(state, cityId)) {
      return RuleError.notEnoughMoney;
    }
    return null;
  }

  /// Buys a level 1 airport at [cityId] and fills its first job board. Other
  /// boards start offering jobs there from their next rotation.
  GameState buyAirport(GameState state, String cityId, DateTime t) {
    final problem = buyAirportProblem(state, cityId);
    if (problem != null) throw RuleException(problem, cityId);
    final paid = _economy.spend(state, airportPrice(state, cityId));
    final bought = paid.copyWith(
      airports: [
        ...paid.airports,
        AirportState(cityId: cityId),
      ],
    );
    return _boards.fill(bought, cityId, t);
  }

  // ---------------------------------------------------------------------
  // Selling airports

  /// What [airport] cost all told: its price as the latest airport bought
  /// (what buying it back would cost), plus every level and path tier
  /// bought on it.
  int airportValue(GameState state, AirportState airport) {
    final size = rules.world.city(airport.cityId).size;
    final a = _config.airports;
    var total = a.purchasePrice(
      citySize: size,
      airportsOwned: state.airports.length - 1,
    );
    for (var l = 2; l <= airport.level; l++) {
      total += a.scaledCost(a.level(l).upgradeCost, size);
    }
    for (final p in a.paths) {
      for (var i = 0; i < airport.tier(p.id); i++) {
        total += a.scaledCost(a.pathTierCosts[i], size);
      }
    }
    return total;
  }

  /// What selling [cityId]'s airport pays: `airportSellRefund` of
  /// [airportValue]. Null if it isn't owned.
  int? airportSalePrice(GameState state, String cityId) {
    final airport = state.airport(cityId);
    if (airport == null) return null;
    return (airportValue(state, airport) * _config.airports.airportSellRefund)
        .round();
  }

  /// Planes that keep [cityId]'s airport from being sold: on the ground
  /// there (at a gate or in the hangar), flying to or circling it, or with
  /// it as a later stop.
  List<Plane> planesTiedTo(GameState state, String cityId) => [
    for (final p in state.planes)
      if ((p.onGround && p.cityId == cityId) ||
          p.targetCityId == cityId ||
          p.remainingStops.contains(cityId))
        p,
  ];

  /// Why [cityId]'s airport can't be sold now, or null if it can.
  RuleError? sellAirportProblem(GameState state, String cityId) {
    if (!state.hasStarted) return RuleError.notStarted;
    if (!state.ownsAirport(cityId)) return RuleError.notOwned;
    if (state.homeCityId == cityId) return RuleError.homeAirport;
    if (planesTiedTo(state, cityId).isNotEmpty) {
      return RuleError.planesAtAirport;
    }
    if (state.crew.autopilot.values.any((r) => r.stops.contains(cityId))) {
      return RuleError.autopilotStop;
    }
    return null;
  }

  /// Jobs selling [cityId]'s airport would cancel: the jobs waiting on its
  /// board to connect, and jobs on other boards or aboard planes that are
  /// bound for it.
  int jobsLostBySale(GameState state, String cityId) {
    var n = 0;
    for (final a in state.airports) {
      for (final j in a.board) {
        if (a.cityId == cityId ? j.isConnecting : j.destCityId == cityId) n++;
      }
    }
    for (final p in state.planes) {
      n += p.load.where((j) => j.destCityId == cityId).length;
    }
    return n;
  }

  /// Whether selling [cityId]'s airport leaves its region unlicensed (an
  /// owned airport counts as a license for its region), so buying there
  /// again would need a license.
  bool saleLosesRegion(GameState state, String cityId) {
    if (!state.ownsAirport(cityId)) return false;
    final region = rules.world.city(cityId).regionId;
    final after = state.copyWith(
      airports: [
        for (final a in state.airports)
          if (a.cityId != cityId) a,
      ],
    );
    return !isLicensed(after, region);
  }

  /// Sells [cityId]'s airport for [airportSalePrice]. Its board goes with
  /// it, jobs elsewhere bound for it are cancelled (jobs set to drop off
  /// there fly straight to their destination instead), and its staff go
  /// back to the crew room. A terminal there stays the airline's and works
  /// again if the airport is bought back.
  GameState sellAirport(GameState state, String cityId) {
    final problem = sellAirportProblem(state, cityId);
    if (problem != null) throw RuleException(problem, cityId);
    final price = airportSalePrice(state, cityId)!;
    List<Job> keep(List<Job> jobs) => [
      for (final j in jobs)
        if (j.destCityId != cityId)
          j.dropAtCityId == cityId ? j.copyWith(dropAtCityId: () => null) : j,
    ];
    return state.copyWith(
      player: state.player.copyWith(money: state.player.money + price),
      airports: [
        for (final a in state.airports)
          if (a.cityId != cityId) a.copyWith(board: keep(a.board)),
      ],
      planes: [for (final p in state.planes) p.copyWith(load: keep(p.load))],
      crew: state.crew.copyWith(
        members: [
          for (final m in state.crew.members)
            m.cityId == cityId ? m.copyWith(cityId: () => null) : m,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Airport levels

  /// The highest airport level the airline's level allows.
  int maxAirportLevel(GameState state) =>
      _config.progression.maxAirportLevelAt(state.player.level);

  /// What upgrading [airport] to the next level costs, or null at level 5.
  int? airportUpgradeCost(AirportState airport) {
    if (airport.level >= _config.airports.maxLevel) return null;
    return _config.airports.scaledCost(
      _config.airports.level(airport.level + 1).upgradeCost,
      rules.world.city(airport.cityId).size,
    );
  }

  /// Why [cityId] can't be upgraded now, or null if it can.
  RuleError? upgradeAirportProblem(GameState state, String cityId) {
    final airport = state.airport(cityId);
    if (airport == null) return RuleError.notOwned;
    final cost = airportUpgradeCost(airport);
    if (cost == null) return RuleError.maxLevel;
    if (airport.level + 1 > maxAirportLevel(state)) {
      return RuleError.levelTooLow;
    }
    if (state.player.money < cost) return RuleError.notEnoughMoney;
    return null;
  }

  /// Raises [cityId] one level: more gates, a bigger board (filled now),
  /// and bigger planes. Planes holding there for a
  /// gate land if one opened.
  GameState upgradeAirport(GameState state, String cityId, DateTime t) {
    final problem = upgradeAirportProblem(state, cityId);
    if (problem != null) throw RuleException(problem, cityId);
    final paid = _economy.spend(
      state,
      airportUpgradeCost(state.airport(cityId)!)!,
    );
    final raised = paid.updateAirport(
      cityId,
      (a) => a.copyWith(level: a.level + 1),
    );
    final filled = _boards.fill(raised, cityId, t);
    return _flights.landHolding(filled, cityId, t, SimReport());
  }

  // ---------------------------------------------------------------------
  // Upgrade paths

  /// Path tiers bought at [airport], across all paths.
  int tiersBought(AirportState airport) =>
      [for (final p in _config.airports.paths) airport.tier(p.id)]
          .fold(0, (a, b) => a + b);

  /// The money cost of [airport]'s next tier on [pathId], or null when the
  /// path is maxed.
  int? pathTierCost(AirportState airport, String pathId) {
    final tier = airport.tier(pathId);
    final costs = _config.airports.pathTierCosts;
    if (tier >= costs.length) return null;
    return _config.airports.scaledCost(
      costs[tier],
      rules.world.city(airport.cityId).size,
    );
  }

  /// What selling [airport]'s top tier on [pathId] refunds, or null if no
  /// tier is bought.
  int? pathTierRefund(AirportState airport, String pathId) {
    final tier = airport.tier(pathId);
    if (tier == 0) return null;
    final cost = _config.airports.scaledCost(
      _config.airports.pathTierCosts[tier - 1],
      rules.world.city(airport.cityId).size,
    );
    return (cost * _config.airports.pathSellRefund).round();
  }

  /// Why the next tier of [pathId] at [cityId] can't be bought, or null.
  RuleError? buyTierProblem(GameState state, String cityId, String pathId) {
    final airport = state.airport(cityId);
    if (airport == null) return RuleError.notOwned;
    final cost = pathTierCost(airport, pathId);
    if (cost == null) return RuleError.maxLevel;
    if (state.player.money < cost) return RuleError.notEnoughMoney;
    return null;
  }

  /// Buys the next tier of [pathId] at [cityId] (tiers go in order). Board
  /// slot tiers fill the board right away.
  GameState buyPathTier(
    GameState state,
    String cityId,
    String pathId,
    DateTime t,
  ) {
    _checkPath(pathId);
    final problem = buyTierProblem(state, cityId, pathId);
    if (problem != null) throw RuleException(problem, '$cityId $pathId');
    final airport = state.airport(cityId)!;
    final paid = _economy.spend(state, pathTierCost(airport, pathId)!);
    final bought = paid.updateAirport(
      cityId,
      (a) =>
          a.copyWith(pathTiers: {...a.pathTiers, pathId: a.tier(pathId) + 1}),
    );
    return _boards.fill(bought, cityId, t);
  }

  /// Sells the top tier of [pathId] at [cityId] for half its price. Tiers above another must go first, so selling always takes
  /// the highest one. Jobs already on the board stay until they rotate.
  GameState sellPathTier(GameState state, String cityId, String pathId) {
    _checkPath(pathId);
    final airport = state.airport(cityId);
    require(airport != null, RuleError.notOwned);
    final refund = pathTierRefund(airport!, pathId);
    require(refund != null, RuleError.nothingToSell);
    final sold = state.updateAirport(cityId, (a) {
      final tiers = {...a.pathTiers, pathId: a.tier(pathId) - 1};
      tiers.removeWhere((_, v) => v == 0);
      return a.copyWith(pathTiers: tiers);
    });
    return sold.copyWith(
      player: sold.player.copyWith(money: sold.player.money + refund!),
    );
  }

  void _checkPath(String pathId) {
    if (!_config.airports.paths.any((p) => p.id == pathId)) {
      throw ArgumentError.value(pathId, 'pathId', 'unknown path');
    }
  }

  /// The path with the most tiers at [airport] (the first in config order on
  /// a tie), for the map badge; null with none bought.
  String? topPath(AirportState airport) {
    String? best;
    var most = 0;
    for (final p in _config.airports.paths) {
      if (airport.tier(p.id) > most) {
        most = airport.tier(p.id);
        best = p.id;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------
  // Airline levels

  String title(int level) => _config.progression.titleFor(level);

  /// What reaching [level] unlocks, in the player's words. Package-specific
  /// features (challenges, part crates, rivals) are listed by their config
  /// keys' unlock levels so the list stays right as they arrive.
  List<String> unlocksAt(int level) {
    final p = _config.progression;
    final classNames = {for (final c in _config.planes.classes) c.id: c.name};
    final out = <String>[];
    for (final MapEntry(:key, :value) in p.planeClassUnlockLevel.entries) {
      if (value == level && level > 1) out.add('${classNames[key]} planes');
    }
    for (final m in _config.planes.models) {
      if (unlockLevel(m) == level && level > 1) out.add(m.name);
    }
    final airportStep = p.airportMaxLevel.where((s) => s.airlineLevel == level);
    for (final s in airportStep) {
      if (level > 1) out.add('Airport level ${s.value}');
    }
    final licenses = p.regionLicenses;
    for (var i = 0; i < licenses.length; i++) {
      if (licenses[i].airlineLevel == level) {
        out.add('${_ordinal(i + 2)} region license');
      }
    }
    for (final s in p.pilotBonusSlots.where((s) => s.airlineLevel == level)) {
      out.add('Pilots +${s.value}');
    }
    for (final MapEntry(:key, :value) in p.featureUnlockLevel.entries) {
      if (value == level) out.add(featureNames[key] ?? key);
    }
    final t = p.titles.where((s) => s.airlineLevel == level && level > 1);
    for (final s in t) {
      out.add('Title: ${s.value}');
    }
    return out;
  }

  /// The next airline level that unlocks anything, after [level].
  int? nextUnlockLevel(int level) {
    for (var l = level + 1; l <= _config.progression.maxLevel; l++) {
      if (unlocksAt(l).isNotEmpty) return l;
    }
    return null;
  }

  static const featureNames = {
    'challenges': 'Challenge board',
    'cityShare': 'City share',
    'specialJobs': 'Special jobs (VIP, Fragile, Rush)',
    'contracts': 'Contracts',
    'partCrates': 'Part crates',
    'terminals': 'Hub terminals',
    'leaderboard': 'Season leaderboard',
    'specialLiveries': 'Special liveries',
  };

  static String _ordinal(int n) => switch (n) {
    2 => 'Second',
    3 => 'Third',
    4 => 'Fourth',
    5 => 'Fifth',
    6 => 'Sixth',
    7 => 'Seventh',
    _ => '${n}th',
  };
}

/// The growth actions as the screens call them: each runs the world up to
/// [now] first, like every other [Simulation] action.
extension GrowthActions on Simulation {
  Growth get growth => Growth(rules);

  GameState _now(GameState state, DateTime now) => advance(state, now).$1;

  GameState buyPlane(GameState state, String modelId, DateTime now) =>
      growth.buyPlane(_now(state, now), modelId, now);

  GameState upgradePlane(
    GameState state,
    String planeId,
    PlaneTrack track,
    DateTime now,
  ) => growth.upgradePlane(_now(state, now), planeId, track);

  /// Buys the seat or slot [jobId] needs and loads it; see
  /// [Growth.upgradeAndLoad].
  GameState upgradeAndLoad(
    GameState state,
    String planeId,
    String jobId,
    DateTime now, {
    String? dropAtCityId,
  }) {
    final s = _now(state, now);
    return growth.upgradeAndLoad(
      s,
      planeId,
      jobId,
      s.simulatedTo,
      dropAtCityId: dropAtCityId,
    );
  }

  GameState renamePlane(
    GameState state,
    String planeId,
    String name,
    DateTime now,
  ) => growth.renamePlane(_now(state, now), planeId, name);

  GameState buyLicense(GameState state, String regionId, DateTime now) =>
      growth.buyLicense(_now(state, now), regionId);

  GameState buyAirport(GameState state, String cityId, DateTime now) {
    final s = _now(state, now);
    return growth.buyAirport(s, cityId, s.simulatedTo);
  }

  GameState sellAirport(GameState state, String cityId, DateTime now) =>
      growth.sellAirport(_now(state, now), cityId);

  GameState upgradeAirport(GameState state, String cityId, DateTime now) {
    final s = _now(state, now);
    return growth.upgradeAirport(s, cityId, s.simulatedTo);
  }

  GameState buyPathTier(
    GameState state,
    String cityId,
    String pathId,
    DateTime now,
  ) {
    final s = _now(state, now);
    return growth.buyPathTier(s, cityId, pathId, s.simulatedTo);
  }

  GameState sellPathTier(
    GameState state,
    String cityId,
    String pathId,
    DateTime now,
  ) => growth.sellPathTier(_now(state, now), cityId, pathId);
}
