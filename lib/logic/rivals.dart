import 'dart:math' as math;

import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'economy.dart';
import 'rng.dart';
import 'rules.dart';

/// A rival plane in the air, for the map.
class RivalFlight {
  const RivalFlight({
    required this.rivalId,
    required this.planeIndex,
    required this.fromCityId,
    required this.toCityId,
    required this.departAt,
    required this.arriveAt,
  });

  final String rivalId;
  final int planeIndex;
  final String fromCityId;
  final String toCityId;
  final DateTime departAt;
  final DateTime arriveAt;

  /// Unique on the map: `rival:<rivalId>:<planeIndex>`.
  String get planeId => 'rival:$rivalId:$planeIndex';

  /// The rival id in a map plane id, or null for one of the player's planes.
  static String? rivalIdOf(String planeId) =>
      planeId.startsWith('rival:') ? planeId.split(':')[1] : null;
}

/// One row of a season leaderboard.
class Standing {
  const Standing({
    required this.airlineId,
    required this.citiesLed,
    required this.wins,
  });

  /// [playerAirlineId] or a rival id.
  final String airlineId;
  final int citiesLed;
  final int wins;

  bool get isPlayer => airlineId == playerAirlineId;
}

/// Rival airlines (design doc, Rival airlines): city share and leader perks,
/// hubs and terminals, contracts, seasons and difficulty.
///
/// Rivals never touch what the player owns. They deliver "ghost" jobs the
/// rules make up for them, so they only ever move share meters, race
/// contracts and fly planes across the map.
class Rivals {
  const Rivals(this.rules);

  final Rules rules;

  RivalsConfig get _c => rules.config.rivals;
  ProgressionConfig get _progression => rules.config.progression;

  // Unlocks -----------------------------------------------------------------

  bool shareOn(GameState s) =>
      _progression.isUnlocked('cityShare', s.player.level);
  bool contractsOn(GameState s) =>
      _progression.isUnlocked('contracts', s.player.level);
  bool terminalsOn(GameState s) =>
      _progression.isUnlocked('terminals', s.player.level);
  bool leaderboardOn(GameState s) =>
      _progression.isUnlocked('leaderboard', s.player.level);

  // Strength ----------------------------------------------------------------

  RivalDifficulty difficulty(GameState s) => _c.difficulty(s.rivals.difficulty);

  /// The rival's tier, moved up one when the airline started in a hard-mode
  /// region (Antarctica).
  String tierOf(GameState s, RivalAirline r) {
    final home = s.homeCityId;
    final hard =
        home != null &&
        rules.world.region(rules.world.city(home).regionId).hardMode;
    if (!hard) return r.tier;
    final i = _c.tiers.indexWhere((t) => t.id == r.tier);
    return _c.tiers[math.min(i + _c.hardModeTierShift, _c.tiers.length - 1)].id;
  }

  /// How strong [r] is against the player's curve (0.7 = 30% behind).
  double strength(GameState s, RivalAirline r) =>
      difficulty(s).tierStrength[tierOf(s, r)]!;

  /// Rivals grow along the player's level, scaled by their strength.
  int levelOf(GameState s, RivalAirline r) =>
      (s.player.level * strength(s, r)).round().clamp(1, _progression.maxLevel);

  String titleOf(GameState s, RivalAirline r) =>
      _progression.titleFor(levelOf(s, r));

  int fleetSize(GameState s, RivalAirline r) {
    final pace = _c.pace;
    final size =
        (pace['fleetBase']! + pace['fleetPerLevel']! * levelOf(s, r)) *
        _c.personality(r.personality).fleet;
    return size.round().clamp(1, pace['maxFleet']!.round());
  }

  /// The best plane [r] can fly at its level: the same planes the player
  /// buys, so rivals keep to the same range.
  PlaneModel planeFor(GameState s, RivalAirline r) {
    final p = _c.personality(r.personality);
    final level = levelOf(s, r);
    final models = [
      for (final m in rules.config.planes.models)
        if (p.planeClasses.contains(m.classId) &&
            (m.seats == 0) == p.cargoOnly &&
            (m.unlockLevel ?? 1) <= level)
          m,
    ];
    if (models.isEmpty) {
      return rules.config.planes.model(
        rules.config.economy.startingPlaneModelId,
      );
    }
    models.sort((a, b) {
      final byLevel = (b.unlockLevel ?? 1).compareTo(a.unlockLevel ?? 1);
      return byLevel != 0 ? byLevel : b.rangeKm.compareTo(a.rangeKm);
    });
    return models.first;
  }

  List<RivalAirline> inRegion(String regionId) => [
    for (final r in _c.roster)
      if (r.regionId == regionId) r,
  ];

  /// Regions where rivals compete with the player: those with one of the
  /// player's airports. Elsewhere they are scenery.
  Set<String> activeRegions(GameState s) => {
    for (final a in s.airports) rules.world.city(a.cityId).regionId,
  };

  // Rival terminals ---------------------------------------------------------

  /// Cities where [r] holds a terminal from the start: its hub, plus the
  /// next biggest cities in its region for a Jumbo's fortified hubs.
  List<String> fortifiedCities(RivalAirline r) =>
      (_fortified[_c] ??= {})[r.id] ??= _fortify(r);

  // Worked out once per config: rivals ask for it many times a step.
  static final _fortified = Expando<Map<String, List<String>>>();

  List<String> _fortify(RivalAirline r) {
    final tier = _c.tiers.firstWhere((t) => t.id == r.tier);
    final hubs = {for (final o in _c.roster) o.hubCityId};
    final others =
        [
          for (final c in rules.world.citiesIn(r.regionId))
            if (!hubs.contains(c.id)) c,
        ]..sort((a, b) {
          final bySize = b.size.compareTo(a.size);
          return bySize != 0 ? bySize : a.id.compareTo(b.id);
        });
    // Two Jumbos in a region would want the same cities; deal them out in
    // roster order.
    final jumbos = [
      for (final o in inRegion(r.regionId))
        if (_c.tiers.firstWhere((t) => t.id == o.tier).fortifiedHubs > 1) o.id,
    ];
    final turn = jumbos.indexOf(r.id);
    final extra = <String>[];
    for (
      var i = math.max(turn, 0);
      i < others.length && extra.length < tier.fortifiedHubs - 1;
      i += math.max(jumbos.length, 1)
    ) {
      extra.add(others[i].id);
    }
    return [r.hubCityId, ...extra];
  }

  /// The rival holding a terminal at [cityId], or null.
  String? rivalTerminalAt(GameState s, String cityId) {
    if (s.rivals.lostTerminalCityIds.contains(cityId)) return null;
    if (s.rivals.terminal(cityId) != null) return null;
    final region = rules.world.city(cityId).regionId;
    for (final r in inRegion(region)) {
      if (fortifiedCities(r).contains(cityId)) return r.id;
    }
    return null;
  }

  // City share --------------------------------------------------------------

  /// Who leads [cityId], or null if nobody has enough share yet (or city
  /// share hasn't unlocked).
  String? leaderOf(GameState s, String cityId) {
    if (!shareOn(s)) return null;
    final share = s.rivals.share(cityId);
    final leader = share.leader;
    if (leader == null) return null;
    return share.of(leader) >= _c.pace['minPointsToLead']! ? leader : null;
  }

  bool playerLeads(GameState s, String cityId) =>
      leaderOf(s, cityId) == playerAirlineId;

  /// Cities in [regionId] that [airlineId] leads.
  int citiesLed(GameState s, String airlineId, String regionId) {
    var n = 0;
    for (final cityId in s.rivals.cities.keys) {
      if (rules.world.city(cityId).regionId == regionId &&
          leaderOf(s, cityId) == airlineId) {
        n++;
      }
    }
    return n;
  }

  /// "Heated" toward the player after losing a terminal, or while the
  /// player leads its hub; otherwise a friendly rivalry.
  bool isHeated(GameState s, RivalAirline r) =>
      s.rivals.heatedRivalIds.contains(r.id) || playerLeads(s, r.hubCityId);

  /// Hub status: the player has held the hub share (50%) for the days it
  /// takes (3).
  bool isHub(GameState s, String cityId, DateTime t) {
    if (!shareOn(s)) return false;
    final since = s.rivals.share(cityId).playerHubSince;
    return since != null &&
        t.difference(since) >=
            Duration(hours: (_c.hub['daysHeld']! * 24).round());
  }

  /// How long until [cityId] becomes a hub, or null if the share is short.
  Duration? hubIn(GameState s, String cityId, DateTime t) {
    final since = s.rivals.share(cityId).playerHubSince;
    if (since == null || !shareOn(s)) return null;
    final left = since
        .add(Duration(hours: (_c.hub['daysHeld']! * 24).round()))
        .difference(t);
    return left.isNegative ? Duration.zero : left;
  }

  /// How long until the player takes over the rival terminal at [cityId],
  /// or null if they aren't leading it.
  Duration? takeoverIn(GameState s, String cityId, DateTime t) {
    final since = s.rivals.share(cityId).playerLeadSince;
    if (since == null || rivalTerminalAt(s, cityId) == null) return null;
    final left = since.add(_days('takeoverDaysLeading')).difference(t);
    return left.isNegative ? Duration.zero : left;
  }

  Duration _days(String key) =>
      Duration(minutes: (_c.terminal[key]! * 24 * 60).round());

  /// Leader and terminal pay bonuses for delivering [job] to [cityId].
  double deliveryPayPct(GameState s, Job job, String cityId) {
    var pct = playerLeads(s, cityId) ? _c.leader['payPct']! : 0.0;
    if (job.type == JobType.passenger) {
      pct += terminalEffect(s, cityId, 'passengerPayPct');
      if (job.originCityId != cityId) {
        pct += terminalEffect(s, job.originCityId, 'passengerPayPct');
      }
    }
    return pct;
  }

  /// Extra board slots at [cityId]: a hub's slot, and the terminal's Gates
  /// branch (including the exclusive jobs only the player sees).
  int extraBoardSlots(GameState s, String cityId) =>
      (isHub(s, cityId, s.simulatedTo) ? _c.hub['boardSlots']!.round() : 0) +
      terminalEffect(s, cityId, 'boardSlots').round() +
      terminalEffect(s, cityId, 'exclusiveJobs').round();

  /// Percent off a paid refresh at [cityId].
  double refreshCostPct(GameState s, String cityId) =>
      terminalEffect(s, cityId, 'refreshCostPct');

  /// First look: while a rival leads [job]'s city, new jobs are its for the
  /// first minute; they reach the player's board after that.
  bool isHeld(GameState s, Job job, DateTime t) {
    if (job.isConnecting) return false;
    final leader = leaderOf(s, job.originCityId);
    if (leader == null || leader == playerAirlineId) return false;
    return t.isBefore(heldUntil(job));
  }

  DateTime heldUntil(Job job) => job.createdAt.add(
    Duration(seconds: _c.leader['firstLookSeconds']!.round()),
  );

  /// Share [pay] coins delivered to [cityId] earn the player.
  double playerSharePoints(GameState s, String cityId, int pay) {
    final airport = s.airport(cityId);
    final tiers = airport == null
        ? 0
        : airport.pathTiers.values.fold(0, (a, b) => a + b);
    final pct =
        tiers * _c.share['pathTierBonusPct']! +
        terminalEffect(s, cityId, 'sharePct');
    final holder = s.rivals.terminal(cityId) != null
        ? _c.share['terminalShareMultiplier']!
        : 1.0;
    return pay * _c.share['perCoinDelivered']! * (1 + pct / 100) * holder;
  }

  /// The player delivered [job] to [cityId] for [pay]: share, terminal
  /// points and contract progress.
  GameState playerDelivered(
    GameState s,
    Job job,
    String cityId,
    int pay,
    DateTime t,
  ) {
    var rivals = s.rivals;
    for (final id in {job.originCityId, cityId}) {
      if (rivals.terminal(id) != null) {
        rivals = rivals.updateTerminal(id, (x) => x.copyWith(jobs: x.jobs + 1));
      }
    }
    var next = s.copyWith(rivals: rivals);
    if (shareOn(next) && pay > 0) {
      final points = playerSharePoints(next, cityId, pay);
      next = next.copyWith(
        rivals: next.rivals.updateCity(
          cityId,
          (c) => c.add(playerAirlineId, points),
        ),
      );
      next = _updateFlags(next, cityId, t);
    }
    final contract = next.rivals.liveContract;
    if (contract != null &&
        pay > 0 &&
        contract.cityId == cityId &&
        t.isBefore(contract.endsAt) &&
        contractsOn(next)) {
      final score = contract.score(playerAirlineId) + 1;
      next = _replaceContract(
        next,
        contract.copyWith(scores: {...contract.scores, playerAirlineId: score}),
      );
      if (score >= contract.jobsToWin) {
        next = _win(next, next.rivals.liveContract!, playerAirlineId, t);
      }
    }
    return next;
  }

  /// Keeps [cityId]'s lead and hub clocks up to date, and hands over a
  /// rival terminal the player has led long enough.
  GameState _updateFlags(GameState s, String cityId, DateTime t) {
    final share = s.rivals.share(cityId);
    final leads = playerLeads(s, cityId);
    final hubShare =
        share.fraction(playerAirlineId) * 100 >= _c.hub['minSharePct']!;
    var next = s.copyWith(
      rivals: s.rivals.updateCity(
        cityId,
        (c) => c.copyWith(
          playerLeadSince: () => leads ? (c.playerLeadSince ?? t) : null,
          playerHubSince: () => hubShare ? (c.playerHubSince ?? t) : null,
        ),
      ),
    );
    final holder = rivalTerminalAt(next, cityId);
    final left = takeoverIn(next, cityId, t);
    if (holder != null && left == Duration.zero) {
      next = next.copyWith(
        rivals: next.rivals.copyWith(
          lostTerminalCityIds: [...next.rivals.lostTerminalCityIds, cityId],
          heatedRivalIds: {...next.rivals.heatedRivalIds, holder}.toList(),
        ),
      );
    }
    return next;
  }

  // Terminals ---------------------------------------------------------------

  /// How many terminals the player may hold at their level.
  int terminalLimit(GameState s) {
    final first = _c.terminal['firstAirlineLevel']!.round();
    final every = _c.terminal['extraEveryLevels']!.round();
    if (s.player.level < first) return 0;
    return 1 + (s.player.level - first) ~/ every;
  }

  /// A rival terminal the player took over, waiting to be leased.
  bool isForLease(GameState s, String cityId) =>
      s.rivals.lostTerminalCityIds.contains(cityId) &&
      s.rivals.terminal(cityId) == null;

  int terminalCost(GameState s, String cityId) {
    final full =
        _c.terminal['buildCostPerCitySize']! * rules.world.city(cityId).size;
    return (isForLease(s, cityId)
            ? full * _c.terminal['leaseCostFraction']!
            : full)
        .round();
  }

  /// Why the player can't build (or lease) a terminal at [cityId] now.
  RuleError? terminalProblem(GameState s, String cityId, DateTime t) {
    if (!rules.world.hasCity(cityId)) return RuleError.unknownCity;
    if (!terminalsOn(s)) return RuleError.locked;
    if (!s.ownsAirport(cityId)) return RuleError.notOwned;
    if (s.rivals.terminal(cityId) != null) return RuleError.alreadyBuilt;
    if (!isForLease(s, cityId) && !isHub(s, cityId, t)) {
      return RuleError.notAHub;
    }
    if (s.rivals.terminals.length >= terminalLimit(s)) {
      return RuleError.terminalLimit;
    }
    if (terminalCost(s, cityId) > s.player.money) {
      return RuleError.notEnoughMoney;
    }
    return null;
  }

  GameState buildTerminal(GameState s, String cityId, DateTime t) {
    final problem = terminalProblem(s, cityId, t);
    if (problem != null) throw RuleException(problem);
    final paid = Economy(rules).spend(s, terminalCost(s, cityId));
    return paid.copyWith(
      rivals: paid.rivals.copyWith(
        terminals: [
          ...paid.rivals.terminals,
          PlayerTerminal(cityId: cityId, builtAt: t),
        ],
      ),
    );
  }

  /// Terminal points earned at [t]: one per 40 jobs, up to 10.
  int pointsEarned(PlayerTerminal t) => math.min(
    _c.terminal['maxPoints']!.round(),
    t.jobs ~/ _c.terminal['jobsPerPoint']!.round(),
  );

  int pointsToSpend(PlayerTerminal t) => pointsEarned(t) - t.spent;

  /// Learns the next node down [branchId] at the terminal in [cityId].
  GameState learnNode(GameState s, String cityId, String branchId) {
    final terminal = s.rivals.terminal(cityId);
    require(terminal != null, RuleError.noTerminal);
    final branch = _c.terminalBranches.where((b) => b.id == branchId);
    require(branch.isNotEmpty, RuleError.unknownBranch);
    require(
      terminal!.learned(branchId) < branch.first.nodes.length,
      RuleError.branchComplete,
    );
    require(pointsToSpend(terminal) > 0, RuleError.noPoints);
    return s.copyWith(
      rivals: s.rivals.updateTerminal(
        cityId,
        (x) =>
            x.copyWith(nodes: {...x.nodes, branchId: x.learned(branchId) + 1}),
      ),
    );
  }

  /// Sum of an effect over the nodes learned at the player's terminal in
  /// [cityId].
  double terminalEffect(GameState s, String cityId, String effect) {
    final terminal = s.rivals.terminal(cityId);
    if (terminal == null) return 0;
    var total = 0.0;
    for (final b in _c.terminalBranches) {
      final n = terminal.learned(b.id);
      for (var i = 0; i < n && i < b.nodes.length; i++) {
        if (b.nodes[i].effect == effect) total += b.nodes[i].value;
      }
    }
    return total;
  }

  /// Premium lounge: after a rotation, makes sure a VIP job is on the
  /// board.
  GameState premiumLounge(GameState s, String cityId, DateTime t) {
    if (terminalEffect(s, cityId, 'vipEveryRotation') <= 0) return s;
    final board = s.airport(cityId)!.board;
    if (board.any((j) => j.kind == JobKind.vip && !j.isConnecting)) return s;
    final pick = board.where(
      (j) =>
          j.type == JobType.passenger &&
          j.kind == JobKind.standard &&
          !j.isConnecting,
    );
    if (pick.isEmpty) return s;
    final vip = rules.config.jobs.special['vip']!;
    final job = pick.first;
    return s.updateAirport(
      cityId,
      (a) => a.copyWith(
        board: [
          for (final j in a.board)
            j.id == job.id
                ? Job(
                    id: j.id,
                    type: j.type,
                    kind: JobKind.vip,
                    originCityId: j.originCityId,
                    destCityId: j.destCityId,
                    payout: (j.payout * vip.payMultiplier).round(),
                    createdAt: j.createdAt,
                    deadline: vip.deadlineMinutes == null
                        ? null
                        : t.add(Duration(minutes: vip.deadlineMinutes!)),
                  )
                : j,
        ],
      ),
    );
  }

  // Difficulty --------------------------------------------------------------

  GameState setDifficulty(GameState s, String difficultyId) {
    require(
      _c.difficulties.any((d) => d.id == difficultyId),
      RuleError.unknownDifficulty,
    );
    return s.copyWith(rivals: s.rivals.copyWith(difficulty: difficultyId));
  }

  // What rivals go after ----------------------------------------------------

  /// Where [r] sends its flights now, with how much of its effort each
  /// city gets: its hub (and fortified cities) plus its targets, picked by
  /// personality and shifted by how the player is doing there.
  Map<String, double> targets(GameState s, RivalAirline r) {
    final p = _c.personality(r.personality);
    final reaction = _c.reaction;
    final react = reaction['boost']! * difficulty(s).reactionSpeedMultiplier;
    final model = planeFor(s, r);
    final hop = p.maxHopKm > 0
        ? math.min(p.maxHopKm, model.rangeKm.toDouble())
        : model.rangeKm.toDouble();
    final fortified = fortifiedCities(r)
        .where((c) => rivalTerminalAt(s, c) == r.id || c == r.hubCityId)
        .toList();
    final on = shareOn(s);

    double playerPct(String cityId) =>
        on ? s.rivals.share(cityId).fraction(playerAirlineId) * 100 : 0;

    // Targets are picked by personality; how the player is doing there
    // then shifts how much of the rival's effort each one gets.
    final scored = <(String, double)>[];
    for (final c in rules.world.citiesIn(r.regionId)) {
      if (fortified.contains(c.id)) continue;
      final km = rules.distanceKm(r.hubCityId, c.id);
      if (km > hop || km < rules.config.jobs.minJobDistanceKm) continue;
      var w = math.pow(c.size, p.sizeExponent).toDouble();
      if (p.cargoPathWeight > 0) {
        w += p.cargoPathWeight * (s.airport(c.id)?.tier('cargo') ?? 0);
      }
      scored.add((c.id, w));
    }
    scored.sort((a, b) {
      final byWeight = b.$2.compareTo(a.$2);
      return byWeight != 0 ? byWeight : a.$1.compareTo(b.$1);
    });
    final count = p.targets + levelOf(s, r) ~/ 10;
    final picked = scored.take(count).toList();
    final avg = picked.isEmpty
        ? 1.0
        : picked.fold(0.0, (a, b) => a + b.$2) / picked.length;
    final result = <String, double>{};
    for (final c in fortified) {
      var w = p.hubWeight * avg;
      // A rival whose hub is under attack shifts flights there.
      if (playerPct(c) >= reaction['hubAttackPct']!) w *= 1 + react;
      result[c] = w;
    }
    for (final (id, base) in picked) {
      var w = base;
      final mine = playerPct(id);
      if (mine >= reaction['dominatePct']!) {
        // Rivals all but abandon cities the player fully dominates...
        w *= reaction['dominatedWeight']!;
      } else if (mine > 0) {
        // ...and pile into cities the player is about to take.
        final share = s.rivals.share(id);
        var best = 0.0;
        for (final other in share.points.keys) {
          if (other != playerAirlineId) {
            best = math.max(best, share.fraction(other));
          }
        }
        if (mine / 100 >= reaction['aboutToTakeRatio']! * best) {
          w *= 1 + react;
        }
      }
      result[id] = w;
    }
    return result;
  }

  // The rival clock ---------------------------------------------------------

  Duration _stepFor(GameState s, DateTime now) {
    final base = Duration(minutes: _c.pace['stepMinutes']!.round());
    final last = s.rivals.lastStepAt ?? s.simulatedTo;
    final steps = now.difference(last).inMilliseconds / base.inMilliseconds;
    final max = _c.pace['maxCatchUpSteps']!;
    if (steps <= max) return base;
    // A long time away: coarser steps, so catching up stays quick. Decay
    // compounds the same either way.
    return base * (steps / max).ceil();
  }

  /// When rivals next act, on fixed marks like the job boards.
  DateTime nextStepAt(GameState s, DateTime now) {
    final step = _stepFor(s, now).inMilliseconds;
    final last = s.rivals.lastStepAt ?? s.simulatedTo;
    return DateTime.fromMillisecondsSinceEpoch(
      (last.millisecondsSinceEpoch ~/ step + 1) * step,
      isUtc: true,
    );
  }

  /// Whether a run of the clock from [from] to [now] is the game catching up
  /// after being closed, when rivals play at half pace.
  double paceFor(DateTime from, DateTime now) =>
      now.difference(from).inSeconds > _c.pace['offlineAfterSeconds']!
      ? _c.offlinePace
      : 1.0;

  /// Rivals act at [t]: share decays, rivals deliver, contracts race on,
  /// new contracts appear and seasons roll over. [pace] is 1, or
  /// `offlinePace` while the game was closed.
  GameState step(GameState s, DateTime t, double pace) {
    final last = s.rivals.lastStepAt;
    final hours = last == null
        ? 0.0
        : t.difference(last).inMilliseconds / Duration.millisecondsPerHour;
    var next = s.copyWith(rivals: s.rivals.copyWith(lastStepAt: t));
    if (hours > 0 && shareOn(next)) {
      next = _decay(next, hours);
      next = _rivalsDeliver(next, hours * pace);
      for (final cityId in next.rivals.cities.keys.toList()) {
        next = _updateFlags(next, cityId, t);
      }
    }
    if (contractsOn(next)) next = _contracts(next, t, hours * pace);
    return _season(next, t);
  }

  GameState _decay(GameState s, double hours) {
    final rate = math.log(1 - _c.share['decayPctPerHour']! / 100);
    final slow = _c.share['terminalDecayMultiplier']!;
    final cities = <String, CityShare>{};
    for (final e in s.rivals.cities.entries) {
      final holder = s.rivals.terminal(e.key) != null
          ? playerAirlineId
          : rivalTerminalAt(s, e.key);
      final points = <String, double>{};
      for (final p in e.value.points.entries) {
        final mult = p.key == holder ? slow : 1.0;
        final left = p.value * math.exp(rate * hours * mult);
        if (left >= 0.01) points[p.key] = left;
      }
      cities[e.key] = e.value.copyWith(points: points);
    }
    return s.copyWith(rivals: s.rivals.copyWith(cities: cities));
  }

  GameState _rivalsDeliver(GameState s, double hours) {
    final active = activeRegions(s);
    final perLevel = _c.pace['sharePerHourPerLevel']!;
    final winTime = difficulty(s).cityWinTimeMultiplier;
    var rivals = s.rivals;
    for (final r in _c.roster) {
      if (!active.contains(r.regionId)) continue;
      final effort =
          perLevel *
          levelOf(s, r) *
          _c.personality(r.personality).effort /
          winTime *
          hours;
      final targets = this.targets(s, r);
      final total = targets.values.fold(0.0, (a, b) => a + b);
      if (total <= 0) continue;
      for (final e in targets.entries) {
        var gain = effort * e.value / total;
        if (rivalTerminalAt(s, e.key) == r.id) {
          gain *= _c.share['terminalShareMultiplier']!;
        }
        gain *= 1 + terminalEffect(s, e.key, 'rivalShareGainPct') / 100;
        rivals = rivals.updateCity(e.key, (c) => c.add(r.id, gain));
      }
    }
    return s.copyWith(rivals: rivals);
  }

  // Contracts ---------------------------------------------------------------

  Duration contractInterval(GameState s) {
    final c = _c.contracts;
    final levels =
        s.player.level - (_progression.featureUnlockLevel['contracts'] ?? 1);
    final hours = math.max(
      c['minIntervalHours']!,
      c['intervalHours']! - c['fasterHoursPerLevel']! * levels,
    );
    return Duration(minutes: (hours * 60).round());
  }

  GameState _replaceContract(GameState s, Contract c) => s.copyWith(
    rivals: s.rivals.copyWith(
      contracts: [for (final x in s.rivals.contracts) x.id == c.id ? c : x],
    ),
  );

  GameState _win(GameState s, Contract c, String winnerId, DateTime t) {
    final region = rules.world.city(c.cityId).regionId;
    final key = winnerId == playerAirlineId
        ? SeasonState.playerKey(region)
        : winnerId;
    final season = s.rivals.season;
    var next = _replaceContract(
      s,
      c.copyWith(winnerId: winnerId, finishedAt: t),
    );
    next = next.copyWith(
      rivals: next.rivals.copyWith(
        season: season.copyWith(
          wins: {...season.wins, key: (season.wins[key] ?? 0) + 1},
        ),
      ),
    );
    if (winnerId == playerAirlineId) next = Economy(rules).earn(next, c.prize);
    // A burst of share for the winner.
    final share = next.rivals.share(c.cityId);
    final burst =
        math.max(share.total, 1.0) * _c.contracts['shareBurstPct']! / 100;
    next = next.copyWith(
      rivals: next.rivals.updateCity(c.cityId, (x) => x.add(winnerId, burst)),
    );
    return _updateFlags(next, c.cityId, t);
  }

  GameState _contracts(GameState s, DateTime t, double hours) {
    var next = s;
    final live = next.rivals.liveContract;
    if (live != null) {
      if (!t.isBefore(live.endsAt)) {
        next = _replaceContract(next, live.copyWith(finishedAt: live.endsAt));
      } else if (hours > 0) {
        final rng = GameRng(next.rngState);
        final scores = {...live.scores};
        String? winner;
        for (final id in live.rivalIds) {
          final r = _c.rival(id);
          final expected =
              _c.contracts['rivalJobsPerHour']! * strength(next, r) * hours;
          final jobs =
              expected.floor() +
              (rng.chance((expected - expected.floor()) * 100) ? 1 : 0);
          scores[id] = (scores[id] ?? 0) + jobs;
          if (winner == null && scores[id]! >= live.jobsToWin) winner = id;
        }
        next = _replaceContract(
          next.copyWith(rngState: rng.state),
          live.copyWith(scores: scores),
        );
        if (winner != null) {
          next = _win(next, next.rivals.liveContract!, winner, t);
        }
      }
    }
    final due = next.rivals.nextContractAt;
    if (due == null) {
      return next.copyWith(
        rivals: next.rivals.copyWith(
          nextContractAt: () => t.add(contractInterval(next)),
        ),
      );
    }
    if (next.rivals.liveContract == null && !t.isBefore(due)) {
      next = _startContract(next, t);
      next = next.copyWith(
        rivals: next.rivals.copyWith(
          nextContractAt: () => t.add(contractInterval(next)),
        ),
      );
    }
    return next;
  }

  /// A new contract in one of the player's airport cities. Heated rivals
  /// pick the player's hubs and terminals.
  GameState _startContract(GameState s, DateTime t) {
    final rng = GameRng(s.rngState);
    final heated = [
      for (final r in _c.roster)
        if (isHeated(s, r) && activeRegions(s).contains(r.regionId)) r,
    ];
    final strongholds = [
      for (final a in s.airports)
        if (s.rivals.terminal(a.cityId) != null || isHub(s, a.cityId, t))
          a.cityId,
    ];
    List<String> candidates = [
      for (final a in s.airports)
        if (inRegion(rules.world.city(a.cityId).regionId).isNotEmpty) a.cityId,
    ];
    if (heated.isNotEmpty) {
      final hot = strongholds.where(
        (c) => heated.any((r) => r.regionId == rules.world.city(c).regionId),
      );
      if (hot.isNotEmpty) candidates = hot.toList();
    }
    final cityId = rng.weighted(
      candidates,
      (c) => rules.world.city(c).size.toDouble(),
    );
    if (cityId == null) return s.copyWith(rngState: rng.state);
    final region = rules.world.city(cityId).regionId;
    final pool = inRegion(region)
      ..sort((a, b) {
        final ah = heated.contains(a) ? 0 : 1;
        final bh = heated.contains(b) ? 0 : 1;
        return ah != bh ? ah.compareTo(bh) : a.id.compareTo(b.id);
      });
    final heatedCount = pool.where(heated.contains).length;
    final rest = pool.skip(heatedCount).toList();
    final racing = <RivalAirline>[...pool.take(heatedCount)];
    final want = rng.between(_c.rivalsRacing[0], _c.rivalsRacing[1]);
    while (racing.length < want && rest.isNotEmpty) {
      racing.add(rest.removeAt(rng.nextInt(rest.length)));
    }
    final c = _c.contracts;
    final contract = Contract(
      id: 'c${s.nextId}',
      cityId: cityId,
      jobsToWin: c['jobsToWin']!.round(),
      prize: (c['prizePerCitySize']! * rules.world.city(cityId).size).round(),
      startsAt: t,
      endsAt: t.add(Duration(minutes: (c['durationHours']! * 60).round())),
      rivalIds: [for (final r in racing.take(want)) r.id],
    );
    final finished = s.rivals.contracts.take(c['keepFinished']!.round());
    return s.copyWith(
      rngState: rng.state,
      nextId: s.nextId + 1,
      rivals: s.rivals.copyWith(contracts: [contract, ...finished]),
    );
  }

  // Seasons -----------------------------------------------------------------

  Duration get seasonLength => Duration(days: _c.seasonLengthDays);

  DateTime? seasonEndsAt(GameState s) =>
      s.rivals.season.startedAt?.add(seasonLength);

  /// The continent leaderboard for [regionId], best first: cities led, then
  /// contracts won. The player wins ties.
  List<Standing> standings(GameState s, String regionId) {
    final season = s.rivals.season;
    final rows = [
      Standing(
        airlineId: playerAirlineId,
        citiesLed: citiesLed(s, playerAirlineId, regionId),
        wins: season.wins[SeasonState.playerKey(regionId)] ?? 0,
      ),
      for (final r in inRegion(regionId))
        Standing(
          airlineId: r.id,
          citiesLed: citiesLed(s, r.id, regionId),
          wins: season.wins[r.id] ?? 0,
        ),
    ];
    rows.sort((a, b) {
      final byCities = b.citiesLed.compareTo(a.citiesLed);
      if (byCities != 0) return byCities;
      final byWins = b.wins.compareTo(a.wins);
      if (byWins != 0) return byWins;
      if (a.isPlayer != b.isPlayer) return a.isPlayer ? -1 : 1;
      return a.airlineId.compareTo(b.airlineId);
    });
    return rows;
  }

  GameState _season(GameState s, DateTime t) {
    var season = s.rivals.season;
    if (season.startedAt == null) {
      return s.copyWith(
        rivals: s.rivals.copyWith(season: season.copyWith(startedAt: t)),
      );
    }
    if (t.isBefore(season.startedAt!.add(seasonLength))) return s;
    final results = <SeasonResult>[];
    if (leaderboardOn(s)) {
      for (final region in activeRegions(s).toList()..sort()) {
        final rows = standings(s, region);
        final rank = rows.indexWhere((r) => r.isPlayer);
        results.add(
          SeasonResult(
            number: season.number,
            regionId: region,
            rank: rank + 1,
            difficulty: s.rivals.difficulty,
            trophyRivalIds: [for (final r in rows.skip(rank + 1)) r.airlineId],
          ),
        );
      }
    }
    // Rivals reset their scores, never the player's progress.
    var start = season.startedAt!;
    var number = season.number;
    while (!t.isBefore(start.add(seasonLength))) {
      start = start.add(seasonLength);
      number++;
    }
    season = SeasonState(
      number: number,
      startedAt: start,
      history: [...season.history, ...results],
    );
    return s.copyWith(rivals: s.rivals.copyWith(season: season));
  }

  /// Trophies won from [rivalId] over every season.
  int trophiesFrom(GameState s, String rivalId) => s.rivals.season.history
      .where((h) => h.trophyRivalIds.contains(rivalId))
      .length;

  // The map -----------------------------------------------------------------

  /// Rival planes in the air at [t], worked out from the clock alone so
  /// nothing about them needs saving: each plane shuttles between its hub
  /// and its targets in fixed slots. Only rivals in the player's regions
  /// fly, up to `pace.maxMapFlights`.
  List<RivalFlight> flights(GameState s, DateTime t) {
    final out = <RivalFlight>[];
    final max = _c.pace['maxMapFlights']!.round();
    final regions = activeRegions(s);
    final baseSlot = Duration(minutes: _c.pace['flightSlotMinutes']!.round())
        .inMilliseconds;
    for (final r in _c.roster) {
      if (!regions.contains(r.regionId)) continue;
      final targets = this.targets(s, r)..remove(r.hubCityId);
      if (targets.isEmpty) continue;
      final ids = targets.keys.toList()..sort();
      final total = targets.values.fold(0.0, (a, b) => a + b);
      final model = planeFor(s, r);
      Duration legTime(String a, String b) => rules.config.flights.realDuration(
        rules.distanceKm(a, b),
        model.speedKmh.toDouble(),
      );
      var longest = 0;
      for (final id in ids) {
        longest = math.max(longest, legTime(r.hubCityId, id).inMilliseconds);
      }
      final slot = math.max(baseSlot, (longest * 1.25).round());
      String pick(int hash) {
        var roll = (hash % 10000) / 10000 * total;
        for (final id in ids) {
          roll -= targets[id]!;
          if (roll < 0) return id;
        }
        return ids.last;
      }

      final ms = t.millisecondsSinceEpoch;
      for (var i = 0; i < fleetSize(s, r); i++) {
        final offset = _hash(r.id, i, -1) % slot;
        final k = (ms + offset) ~/ slot;
        final start = k * slot - offset;
        // Odd slots fly out from the hub, even slots fly back.
        final outbound = k.isOdd;
        final target = pick(_hash(r.id, i, outbound ? k : k - 1));
        final from = outbound ? r.hubCityId : target;
        final to = outbound ? target : r.hubCityId;
        final duration = legTime(from, to).inMilliseconds;
        final spare = math.max(slot - duration, 1);
        final depart = start + _hash(r.id, i, k * 7 + 3) % spare;
        if (ms < depart || ms >= depart + duration) continue;
        out.add(
          RivalFlight(
            rivalId: r.id,
            planeIndex: i,
            fromCityId: from,
            toCityId: to,
            departAt: DateTime.fromMillisecondsSinceEpoch(depart, isUtc: true),
            arriveAt: DateTime.fromMillisecondsSinceEpoch(
              depart + duration,
              isUtc: true,
            ),
          ),
        );
        if (out.length >= max) return out;
      }
    }
    return out;
  }

  /// A small stable hash (FNV-1a), so rival schedules are the same on every
  /// device and every run.
  static int _hash(String id, int a, int b) {
    var h = 0x811C9DC5;
    void mix(int v) {
      h ^= v & 0xFF;
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }

    for (final unit in id.codeUnits) {
      mix(unit);
    }
    for (final v in [a, b]) {
      for (var shift = 0; shift < 64; shift += 8) {
        mix(v >> shift);
      }
    }
    return h;
  }
}
