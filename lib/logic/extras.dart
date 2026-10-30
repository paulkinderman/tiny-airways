import 'dart:math' as math;

import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'economy.dart';
import 'flights.dart';
import 'rng.dart';
import 'rules.dart';
import 'weather.dart';

/// Plane parts and the special planes they build (design doc, Extras).
///
/// Part crates are cargo jobs that pay nothing; delivering one adds a part
/// to the collection. Each special plane needs one of each part kind, and
/// is built once. Spare parts (more than the one a plane needs, or any for
/// a plane already built) sell for cash.
class Parts {
  const Parts(this.rules);

  final Rules rules;

  ExtrasConfig get _config => rules.config.extras;

  /// Parts still needed for planes not yet built.
  List<String> missing(GameState state) => [
    for (final id in _config.partIds)
      if (!state.extras.isBuilt(ExtrasConfig.planeOfPart(id)) &&
          state.extras.partCount(id) == 0)
        id,
  ];

  /// Which part a crate holds. Usually one the player is missing; [seed]
  /// makes it the same every time for the same crate.
  String crateContents(GameState state, int seed) {
    final rng = GameRng(seed);
    final needed = missing(state);
    if (needed.isNotEmpty && rng.chance(_config.newPartChancePct)) {
      return rng.pick(needed);
    }
    return rng.pick(_config.partIds);
  }

  /// Adds [partId] to the collection.
  GameState collect(GameState state, String partId) {
    final extras = state.extras;
    final next = state.copyWith(
      extras: extras.copyWith(
        parts: {...extras.parts, partId: extras.partCount(partId) + 1},
      ),
    );
    return Challenges(rules).record(next, 'partsCollected', 1);
  }

  /// Parts of [partId] that can be sold without holding back a build.
  int spares(GameState state, String partId) {
    final held = state.extras.partCount(partId);
    if (state.extras.isBuilt(ExtrasConfig.planeOfPart(partId))) return held;
    return math.max(0, held - 1);
  }

  bool canBuild(GameState state, String modelId) =>
      _config.partBuiltPlanes.contains(modelId) &&
      !state.extras.isBuilt(modelId) &&
      _config.partKinds.every(
        (k) => state.extras.partCount(ExtrasConfig.partId(modelId, k)) > 0,
      );

  /// Where a newly built plane parks: home if a gate is free there, else
  /// the first owned airport with a free gate that takes its class.
  String? parkingFor(GameState state, String modelId) {
    final flights = Flights(rules);
    final model = rules.config.planes.model(modelId);
    final rank = rules.config.planes.planeClass(model.classId).rank;
    bool fits(AirportState a) =>
        flights.freeGates(state, a.cityId) > 0 &&
        rank <=
            rules.config.planes
                .planeClass(rules.config.airports.level(a.level).maxPlaneClass)
                .rank;
    final home = state.airport(state.homeCityId!);
    if (home != null && fits(home)) return home.cityId;
    for (final a in state.airports) {
      if (fits(a)) return a.cityId;
    }
    return null;
  }

  /// Uses one of each part to build [modelId], parked at a free gate.
  GameState build(GameState state, String modelId) {
    require(state.hasStarted, RuleError.notStarted);
    require(_config.partBuiltPlanes.contains(modelId), RuleError.unknownPlane);
    require(!state.extras.isBuilt(modelId), RuleError.alreadyBuilt);
    require(canBuild(state, modelId), RuleError.missingParts);
    final cityId = parkingFor(state, modelId);
    require(cityId != null, RuleError.noFreeGate);

    final parts = {...state.extras.parts};
    for (final kind in _config.partKinds) {
      final id = ExtrasConfig.partId(modelId, kind);
      parts[id] = parts[id]! - 1;
      if (parts[id] == 0) parts.remove(id);
    }
    return state.copyWith(
      planes: [
        ...state.planes,
        Plane(id: 'p${state.nextId}', modelId: modelId, cityId: cityId!),
      ],
      nextId: state.nextId + 1,
      extras: state.extras.copyWith(
        parts: parts,
        builtPlanes: [...state.extras.builtPlanes, modelId],
      ),
    );
  }

  /// Sells one spare [partId].
  GameState sellSpare(GameState state, String partId) {
    require(spares(state, partId) > 0, RuleError.noSparePart);
    final parts = {...state.extras.parts};
    parts[partId] = parts[partId]! - 1;
    if (parts[partId] == 0) parts.remove(partId);
    return state.copyWith(
      player: state.player.copyWith(
        money: state.player.money + _config.duplicatePartSellPrice,
      ),
      extras: state.extras.copyWith(parts: parts),
    );
  }
}

/// Daily, weekly and milestone challenges (design doc, Extras).
///
/// Things that happen in the game are [record]ed as metrics; challenges on
/// the board and the lifetime counters behind milestones add them up.
/// Dailies and the weekly are rolled by [refresh] at local midnight and on
/// Mondays, once the challenge board unlocks; milestones are tracked from
/// the start. Finished challenges are claimed by the player, and none can
/// be failed.
class Challenges {
  const Challenges(this.rules, {this.utcOffset = Duration.zero});

  final Rules rules;

  /// The player's time zone, so days start at their midnight.
  final Duration utcOffset;

  ChallengesConfig get _config => rules.config.extras.challenges;

  static const _dayMs = 24 * 60 * 60 * 1000;

  /// Local days since 1970-01-01.
  int dayIndex(DateTime t) =>
      (t.add(utcOffset).millisecondsSinceEpoch) ~/ _dayMs;

  /// Weeks starting on Monday (1970-01-01 was a Thursday).
  static int weekIndex(int day) => (day + 3) ~/ 7;

  /// When the next local midnight falls.
  DateTime nextDayAt(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    (dayIndex(t) + 1) * _dayMs,
    isUtc: true,
  ).subtract(utcOffset);

  /// When the next Monday starts.
  DateTime nextWeekAt(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
    ((weekIndex(dayIndex(t)) + 1) * 7 - 3) * _dayMs,
    isUtc: true,
  ).subtract(utcOffset);

  bool isUnlocked(GameState state) =>
      rules.config.progression.isUnlocked('challenges', state.player.level);

  // Rewards and targets ------------------------------------------------------

  ({int xp, int money}) dailyReward(int level, [double times = 1]) {
    final progression = rules.config.progression;
    final bar = progression.xpToNext(math.min(level, progression.maxLevel));
    return (
      xp: (bar * _config.dailyXpFractionOfLevel * times).round(),
      money: (_config.dailyMoneyPerLevel * level * times).round(),
    );
  }

  ({int xp, int money}) milestoneReward(int level) =>
      dailyReward(level, _config.milestoneMultiplier);

  /// [def]'s target at [level], rounded to a friendly number.
  static int targetFor(ChallengeDef def, int level) =>
      friendly(def.target + def.targetPerLevel * level);

  /// Rounds to 2 significant figures above 20 (1,234 is 1,200).
  static int friendly(double n) {
    if (n <= 20) return math.max(1, n.round());
    final step = math.pow(10, (math.log(n) / math.ln10).floor() - 1).toInt();
    return (n / step).round() * step;
  }

  static String describe(ChallengeDef def, int target) =>
      def.text.replaceAll('{n}', _withCommas(target));

  String text(ActiveChallenge challenge) {
    final def = _config.def(challenge.defId);
    return def == null ? challenge.defId : describe(def, challenge.target);
  }

  static String _withCommas(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  // Recording ----------------------------------------------------------------

  /// Adds [amount] to [metric]: the lifetime counter, and the progress of
  /// every unclaimed challenge on the board that counts it. For best-of
  /// metrics ([ExtrasConfig.bestMetrics]) the highest value is kept instead.
  ///
  /// Other packages call this for the metrics they own: rivals record
  /// `terminalsBuilt`, `terminalsTakenFromJumbos` and `contractsWon`; crew
  /// records `topCrewLevel` as the best level reached.
  GameState record(GameState state, String metric, int amount) {
    if (amount <= 0) return state;
    final best = ExtrasConfig.bestMetrics.contains(metric);
    int add(int was) => best ? math.max(was, amount) : was + amount;
    final extras = state.extras;
    ActiveChallenge bump(ActiveChallenge c) {
      if (c.claimed || _config.def(c.defId)?.metric != metric) return c;
      return c.copyWith(progress: math.min(c.target, add(c.progress)));
    }

    return state.copyWith(
      extras: extras.copyWith(
        counters: {...extras.counters, metric: add(extras.counter(metric))},
        dailies: [for (final c in extras.dailies) bump(c)],
        weekly: extras.weekly == null ? null : () => bump(extras.weekly!),
      ),
    );
  }

  /// Records everything one landing at [cityId] counts for: the landing
  /// itself, the jobs [delivered] on time and what they paid, and the
  /// weather it landed in.
  GameState recordLanding(
    GameState state, {
    required String cityId,
    required double km,
    required List<Job> delivered,
    required int paid,
    required int connections,
    required bool endsMultiStopTrip,
    required DateTime t,
  }) {
    var next = record(state, 'landings', 1);
    next = record(next, 'kmFlown', km.round());
    next = record(next, 'moneyEarned', paid);
    next = record(next, 'bestLandingPay', paid);
    next = record(next, 'connections', connections);
    if (endsMultiStopTrip) next = record(next, 'multiStopTrips', 1);
    final bad = _config.badWeather;
    if (WeatherRules(rules)
        .activeAt(state, cityId, t)
        .any((e) => bad.contains(e.typeId))) {
      next = record(next, 'badWeatherLandings', 1);
    }
    var passengers = 0;
    var cargo = 0;
    var cross = 0;
    var special = 0;
    var vip = 0;
    var tours = 0;
    for (final job in delivered) {
      if (job.type == JobType.passenger) {
        passengers++;
      } else {
        cargo++;
      }
      if (rules.crossesRegions(job.originCityId, job.destCityId)) cross++;
      switch (job.kind) {
        case JobKind.vip:
          vip++;
          special++;
        case JobKind.fragile || JobKind.rush:
          special++;
        case JobKind.sightseeing:
          tours++;
        default:
          break;
      }
    }
    next = record(next, 'jobsDelivered', delivered.length);
    next = record(next, 'passengersDelivered', passengers);
    next = record(next, 'cargoDelivered', cargo);
    next = record(next, 'crossRegionDeliveries', cross);
    next = record(next, 'specialDeliveries', special);
    next = record(next, 'vipDeliveries', vip);
    return record(next, 'sightseeingTours', tours);
  }

  // The board ----------------------------------------------------------------

  /// Rolls the dailies at local midnight and the weekly on Mondays. Returns
  /// [state] itself when nothing is due, so the per-second tick stays cheap.
  GameState refresh(GameState state, DateTime t) {
    if (!state.hasStarted || !isUnlocked(state)) return state;
    final day = dayIndex(t);
    final extras = state.extras;
    if (day == extras.day && extras.dailies.length >= _config.dailyCount) {
      return state;
    }

    var next = state;
    if (day != extras.day) {
      // A finished weekly left unclaimed when the week ends pays anyway.
      final weekly = extras.weekly;
      if (weekIndex(day) != extras.week &&
          weekly != null &&
          weekly.isDone &&
          !weekly.claimed) {
        next = claimWeekly(next, t);
      }
      final kept = [
        for (final c in next.extras.dailies)
          if (c.isDone) c,
      ];
      next = next.copyWith(
        extras: next.extras.copyWith(
          day: day,
          dailies: kept,
          rerollsLeft: _config.dailyFreeRerolls,
        ),
      );
      if (weekIndex(day) != extras.week) {
        next = next.copyWith(
          extras: next.extras.copyWith(
            week: weekIndex(day),
            weekly: () => _rollWeekly(next, weekIndex(day)),
          ),
        );
      }
    }
    while (next.extras.dailies.length < _config.dailyCount) {
      final rolled = _rollDaily(next, next.extras.dailies.length);
      if (rolled == null) break;
      next = next.copyWith(
        extras: next.extras.copyWith(dailies: [...next.extras.dailies, rolled]),
      );
    }
    return next;
  }

  bool _eligible(GameState state, ChallengeDef def) {
    final feature = def.requiresFeature;
    if (feature != null &&
        !rules.config.progression.isUnlocked(feature, state.player.level)) {
      return false;
    }
    final plane = def.requiresPlane;
    if (plane != null && !state.planes.any((p) => p.modelId == plane)) {
      return false;
    }
    if (def.requiresAirportsInRegions > 0) {
      final regions = {
        for (final a in state.airports) rules.world.city(a.cityId).regionId,
      };
      if (regions.length < def.requiresAirportsInRegions) return false;
    }
    return true;
  }

  /// A seed that changes with the airline, the day and every roll made.
  int _seed(GameState state, int salt) {
    final e = state.extras;
    return (state.createdAt.millisecondsSinceEpoch +
            e.day * 1000003 +
            e.counter('dailiesClaimed') * 7919 +
            (_config.dailyFreeRerolls - e.rerollsLeft) * 104729 +
            salt * 31) &
        0xFFFFFFFF;
  }

  ActiveChallenge? _rollDaily(GameState state, int salt, {String? not}) {
    final onBoard = {for (final c in state.extras.dailies) c.defId, ?not};
    final pool = [
      for (final d in _config.daily)
        if (!onBoard.contains(d.id) && _eligible(state, d)) d,
    ];
    if (pool.isEmpty) return null;
    final def = GameRng(_seed(state, salt)).pick(pool);
    final level = state.player.level;
    final reward = dailyReward(level);
    return ActiveChallenge(
      defId: def.id,
      target: targetFor(def, level),
      xp: reward.xp,
      money: reward.money,
    );
  }

  ActiveChallenge? _rollWeekly(GameState state, int week) {
    final pool = [
      for (final d in _config.weekly)
        if (_eligible(state, d)) d,
    ];
    if (pool.isEmpty) return null;
    final seed =
        (state.createdAt.millisecondsSinceEpoch + week * 15485863) & 0xFFFFFFFF;
    final def = GameRng(seed).pick(pool);
    final level = state.player.level;
    final reward = dailyReward(level, _config.weeklyMultiplier);
    final crates = rules.config.progression.isUnlocked('partCrates', level);
    return ActiveChallenge(
      defId: def.id,
      target: targetFor(def, level),
      xp: reward.xp,
      money: reward.money,
      bonus: crates ? 'partCrate' : 'crewXp',
    );
  }

  GameState _pay(
    GameState state,
    String text,
    String kind,
    int xp,
    int money,
    DateTime t,
  ) {
    final paid = Economy(rules).grantXp(
      state.copyWith(
        player: state.player.copyWith(money: state.player.money + money),
      ),
      xp,
    );
    return paid.copyWith(
      extras: paid.extras.copyWith(
        log: [
          ClaimRecord(text: text, kind: kind, xp: xp, money: money, at: t),
          ...paid.extras.log.take(29),
        ],
      ),
    );
  }

  /// Pays the finished daily at [index] and rolls a new one in its place.
  GameState claimDaily(GameState state, int index, DateTime t) {
    final dailies = state.extras.dailies;
    require(index >= 0 && index < dailies.length, RuleError.unknownChallenge);
    final c = dailies[index];
    require(c.isDone, RuleError.challengeNotDone);
    var next = _pay(state, text(c), 'daily', c.xp, c.money, t);
    next = next.copyWith(
      extras: next.extras.copyWith(
        dailies: [...dailies]..removeAt(index),
        counters: {
          ...next.extras.counters,
          'dailiesClaimed': next.extras.counter('dailiesClaimed') + 1,
        },
      ),
    );
    final rolled = _rollDaily(next, index, not: c.defId);
    if (rolled == null) return next;
    final list = [...next.extras.dailies]..insert(index, rolled);
    return next.copyWith(extras: next.extras.copyWith(dailies: list));
  }

  /// Swaps an unfinished daily for another, using a free reroll.
  GameState rerollDaily(GameState state, int index) {
    final dailies = state.extras.dailies;
    require(index >= 0 && index < dailies.length, RuleError.unknownChallenge);
    require(!dailies[index].isDone, RuleError.challengeDone);
    require(state.extras.rerollsLeft > 0, RuleError.noRerollsLeft);
    final rolled = _rollDaily(state, index + 100, not: dailies[index].defId);
    require(rolled != null, RuleError.noRerollsLeft);
    final list = [...dailies]..[index] = rolled!;
    return state.copyWith(
      extras: state.extras.copyWith(
        dailies: list,
        rerollsLeft: state.extras.rerollsLeft - 1,
      ),
    );
  }

  /// Pays the finished weekly and its bonus: a part crate, or crew XP for
  /// the whole roster before part crates unlock.
  GameState claimWeekly(GameState state, DateTime t) {
    final c = state.extras.weekly;
    require(c != null, RuleError.unknownChallenge);
    require(!c!.claimed, RuleError.alreadyClaimed);
    require(c.isDone, RuleError.challengeNotDone);
    var next = _pay(state, text(c), 'weekly', c.xp, c.money, t);
    next = next.copyWith(
      extras: next.extras.copyWith(
        weekly: () => c.copyWith(claimed: true),
        counters: {
          ...next.extras.counters,
          'weekliesClaimed': next.extras.counter('weekliesClaimed') + 1,
        },
      ),
    );
    if (c.bonus == 'partCrate') {
      final parts = Parts(rules);
      final seed = _seed(next, next.extras.week);
      next = parts.collect(next, parts.crateContents(next, seed));
    } else if (c.bonus == 'crewXp') {
      next = next.copyWith(
        extras: next.extras.copyWith(
          pendingCrewXp: next.extras.pendingCrewXp + _config.weeklyCrewXp,
        ),
      );
    }
    return next;
  }

  // Milestones ---------------------------------------------------------------

  /// How far along [def] is.
  int progress(GameState state, MilestoneDef def) => switch (def.metric) {
    'airlineLevel' => state.player.level,
    'airportsOwned' => state.airports.length,
    'continentsOwned' => {
      for (final a in state.airports) rules.world.city(a.cityId).regionId,
    }.length,
    'topAirportLevel' => state.airports.fold(
      0,
      (best, a) => math.max(best, a.level),
    ),
    'planesOwned' => state.planes.length,
    'specialPlanesBuilt' => state.extras.builtPlanes.length,
    final metric => state.extras.counter(metric),
  };

  bool milestoneReady(GameState state, MilestoneDef def) =>
      !state.extras.isClaimed(def.id) && progress(state, def) >= def.target;

  /// Pays a reached milestone, and adds its badge, livery or veteran.
  GameState claimMilestone(GameState state, String id, DateTime t) {
    final def = rules.config.extras.milestone(id);
    require(def != null, RuleError.unknownChallenge);
    require(!state.extras.isClaimed(id), RuleError.alreadyClaimed);
    require(progress(state, def!) >= def.target, RuleError.challengeNotDone);
    final reward = milestoneReward(state.player.level);
    final next = _pay(state, def.text, 'milestone', reward.xp, reward.money, t);
    return next.copyWith(
      extras: next.extras.copyWith(
        claimedMilestones: [...next.extras.claimedMilestones, id],
        unlocks: [...next.extras.unlocks, ?def.unlock],
      ),
    );
  }

  /// Challenges and milestones waiting to be claimed (the top bar badge).
  int claimable(GameState state) {
    final extras = state.extras;
    var n = 0;
    if (isUnlocked(state)) {
      n += extras.dailies.where((c) => c.isDone).length;
      final weekly = extras.weekly;
      if (weekly != null && weekly.isDone && !weekly.claimed) n++;
    }
    for (final m in rules.config.extras.milestones) {
      if (milestoneReady(state, m)) n++;
    }
    return n;
  }
}
