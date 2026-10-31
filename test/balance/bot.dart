import 'dart:math';

import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

/// One bought plane: when, for how much, and what it has earned since.
class PlaneLedger {
  PlaneLedger(this.modelId, this.price, this.boughtAt);

  final String modelId;
  final int price;
  final Duration boughtAt;
  int flights = 0;
  int profit = 0;

  /// Flights it took (or, from its average so far, will take) to earn its
  /// price back.
  double get paybackFlights => flights == 0 || profit <= 0
      ? double.infinity
      : price / (profit / flights);
}

/// What the bot saw while it played.
class BotReport {
  /// Play time (game open) when each airline level was reached.
  final Map<int, Duration> levelReachedAt = {};

  /// Coins earned per hour of play while at each level.
  final Map<int, ({int coins, Duration played})> incomeByLevel = {};

  /// Play time when the bot could first afford a plane beyond its start.
  Duration? firstPlaneAffordableAt;

  /// Play time when the bot first upgraded an airport.
  Duration? firstAirportUpgradeAt;

  final List<PlaneLedger> planes = [];
  int lowestMoney = 1 << 62;

  /// Coins earned while the game was open (flights, contracts and
  /// challenge rewards).
  int earned = 0;

  /// Coins from challenges and milestones.
  int rewards = 0;
  int departures = 0;
  int errors = 0;

  /// City share leaders over time, one sample every in-game hour:
  /// city -> leader ids in order.
  final Map<String, List<String?>> leaders = {};

  late GameState finalState;
  Duration played = Duration.zero;
  Duration wallTime = Duration.zero;

  int incomePerHour(int level) {
    final e = incomeByLevel[level];
    if (e == null || e.played.inMinutes < 5) return 0;
    return (e.coins / (e.played.inSeconds / 3600)).round();
  }
}

/// A greedy player that plays sessions of [sessionMinutes] a few times a
/// day, dispatching every parked plane to its most profitable owned
/// airport, and spending money on planes, airports and upgrades as it
/// goes. Between sessions the game is closed and the offline catch-up runs.
class BalanceBot {
  BalanceBot(
    this.sim, {
    this.homeCityId = 'chicago',
    this.sessionMinutes = 30,
    this.sessionsPerDay = 3,
    this.checkEverySeconds = 60,
    this.difficulty,
  });

  final Simulation sim;
  final String homeCityId;
  final int sessionMinutes;
  final int sessionsPerDay;

  /// How often the player looks at the game while it is open.
  final int checkEverySeconds;
  final String? difficulty;

  Growth get _growth => Growth(sim.rules);

  BotReport play({required int days, DateTime? start}) {
    final watch = Stopwatch()..start();
    final report = BotReport();
    var t = start ?? DateTime.utc(2026, 11, 2, 8);
    var s = GameState.newGame(
      now: t,
      startingMoney: sim.rules.config.economy.startingMoney,
    );
    if (difficulty != null) s = sim.setDifficulty(s, difficulty!, t);
    s = sim.startAirline(s, homeCityId, t);
    report.levelReachedAt[1] = Duration.zero;
    final gap = Duration(
      minutes: (24 * 60 - sessionsPerDay * sessionMinutes) ~/ sessionsPerDay,
    );
    final step = Duration(seconds: checkEverySeconds);
    var played = Duration.zero;

    for (var day = 0; day < days; day++) {
      for (var session = 0; session < sessionsPerDay; session++) {
        final end = played + Duration(minutes: sessionMinutes);
        while (played < end) {
          final level = s.player.level;
          s = _act(s, t, report, played);
          for (var l = level + 1; l <= s.player.level; l++) {
            report.levelReachedAt[l] = played;
          }
          final before = s.player;
          t = t.add(step);
          played += step;
          final (next, _) = sim.advance(s, t);
          s = next;
          _sample(s, report, before, played, step);
        }
        // Close the game: the next session catches up the time away.
        final hours = gap.inHours;
        for (var h = 0; h < max(hours, 1); h++) {
          final until = h == hours - 1 || hours == 0
              ? t.add(gap - Duration(hours: h))
              : t.add(const Duration(hours: 1));
          final level = s.player.level;
          s = sim.advance(s, until).$1;
          t = until;
          for (var l = level + 1; l <= s.player.level; l++) {
            report.levelReachedAt[l] = played;
          }
          _sampleLeaders(s, report);
        }
      }
    }
    report
      ..finalState = s
      ..played = played
      ..wallTime = watch.elapsed;
    return report;
  }

  void _sample(
    GameState s,
    BotReport report,
    PlayerState before,
    Duration played,
    Duration step,
  ) {
    final earned = max(0, s.player.money - before.money);
    final level = before.level;
    final e = report.incomeByLevel[level];
    report.incomeByLevel[level] = (
      coins: (e?.coins ?? 0) + earned,
      played: (e?.played ?? Duration.zero) + step,
    );
    for (var l = before.level + 1; l <= s.player.level; l++) {
      report.levelReachedAt[l] = played;
    }
    report.lowestMoney = min(report.lowestMoney, s.player.money);
    report.earned += earned;
    // A rolling hour of income, which sets how big a plane to save for.
    final perHour = earned * 3600 / step.inSeconds;
    _rate = _rate == 0 ? perHour : _rate * 0.98 + perHour * 0.02;
    if (played.inSeconds % 3600 == 0) _sampleLeaders(s, report);
  }

  void _sampleLeaders(GameState s, BotReport report) {
    for (final a in s.airports) {
      report.leaders
          .putIfAbsent(a.cityId, () => [])
          .add(sim.rivals.leaderOf(s, a.cityId));
    }
  }

  GameState _act(GameState s, DateTime t, BotReport report, Duration played) {
    var next = _claim(s, t, report);
    next = _spend(next, t, report, played);
    for (final plane in next.planes) {
      if (plane.status != PlaneStatus.parked) continue;
      next = _dispatch(next, plane.id, t, report);
    }
    return next;
  }

  /// Plans a trip of up to three stops the way a player would: fill the
  /// plane for the best first stop, then add stops while the trip makes
  /// more per hour, and fly it if it makes a profit after fuel.
  GameState _dispatch(GameState s, String planeId, DateTime t, BotReport r) {
    final plane = s.plane(planeId)!;
    final model = sim.rules.config.planes.model(plane.modelId);
    ({GameState state, List<String> stops, int profit, double perHour})? best;
    for (var n = 0; n < 3; n++) {
      final base = best;
      ({GameState state, List<String> stops, int profit, double perHour})? pick;
      final from = base == null ? plane.cityId : base.stops.last;
      for (final a in s.airports) {
        if (a.cityId == plane.cityId || a.cityId == from) continue;
        if (base != null && base.stops.contains(a.cityId)) continue;
        if (sim.rules.distanceKm(from, a.cityId) > _range(plane, model)) {
          continue;
        }
        try {
          final filled = sim.loading.fillTo(
            base?.state ?? s,
            planeId,
            a.cityId,
            t,
          );
          final p = filled.plane(planeId)!;
          // Worth a stop if it picks up jobs or drops off ones already aboard
          // (after a diversion).
          final aboard = (base?.state ?? s).plane(planeId)!.load;
          if (p.load.length == aboard.length &&
              !aboard.any((j) => j.destCityId == a.cityId)) {
            continue;
          }
          final stops = [...?base?.stops, a.cityId];
          final q = sim.flights.quote(filled, planeId, stops, t);
          if (!q.canDepart) continue;
          final profit = q.expectedPayout - q.fuel;
          final perHour = profit / max(q.duration.inSeconds, 60) * 3600;
          if (pick == null || perHour > pick.perHour) {
            pick = (
              state: filled,
              stops: stops,
              profit: profit,
              perHour: perHour,
            );
          }
        } on RuleException {
          continue;
        }
      }
      if (pick == null || (base != null && pick.perHour <= base.perHour)) {
        break;
      }
      best = pick;
      if (best.state.plane(planeId)!.load.length >= model.capacity) break;
    }
    if (best == null || best.profit <= 0) return s;
    try {
      final flown = sim.flights.depart(best.state, planeId, best.stops, t);
      r.departures++;
      _ledgerOf[planeId]
        ?..flights += 1
        ..profit += best.profit;
      return flown;
    } on RuleException {
      r.errors++;
      return s;
    }
  }

  /// Claims every finished challenge and milestone.
  GameState _claim(GameState s, DateTime t, BotReport report) {
    final challenges = sim.challenges;
    var next = s;
    final before = next.player.money;
    if (challenges.isUnlocked(next)) {
      for (var i = next.extras.dailies.length - 1; i >= 0; i--) {
        if (next.extras.dailies[i].isDone) {
          next = challenges.claimDaily(next, i, t);
        }
      }
      final weekly = next.extras.weekly;
      if (weekly != null && weekly.isDone && !weekly.claimed) {
        next = challenges.claimWeekly(next, t);
      }
    }
    for (final m in sim.rules.config.extras.milestones) {
      if (challenges.milestoneReady(next, m)) {
        next = challenges.claimMilestone(next, m.id, t);
      }
    }
    report.rewards += next.player.money - before;
    return next;
  }

  final Map<String, PlaneLedger> _ledgerOf = {};

  double _range(Plane plane, PlaneModel model) =>
      model.rangeKm *
      (1 +
          plane.upgrades.range *
              sim.rules.config.planes.upgrades.rangePctPerLevel /
              100);

  double _rate = 0;

  GameState _spend(GameState s, DateTime t, BotReport report, Duration played) {
    var next = s;
    final models = [
      for (final m in sim.rules.config.planes.models)
        if (_growth.isUnlocked(next, m) && m.price != null) m,
    ]..sort((a, b) => a.price!.compareTo(b.price!));
    final start = sim.rules.config.economy.startingMoney;
    if (report.firstPlaneAffordableAt == null &&
        start + report.earned >= models.first.price!) {
      report.firstPlaneAffordableAt = played;
    }

    // Keep a little cash for fuel.
    final reserve = 200 + next.planes.length * 100;
    bool canSpend(int cost) => next.player.money - cost > reserve;

    // Save for the biggest plane about 3 hours of income buys.
    final budget = max(models.first.price!.toDouble(), _rate * 3);
    final target = models.lastWhere((m) => m.price! <= budget);
    final rank = sim.rules.config.planes.planeClass(target.classId).rank;
    int classRank(AirportState a) => sim.rules.config.planes
        .planeClass(sim.rules.config.airports.level(a.level).maxPlaneClass)
        .rank;

    // 1. The plane, a hangar slot for it, or a gate (airport level) for it.
    final problem = _growth.buyPlaneProblem(next, target);
    final targetClass = sim.rules.config.planes.planeClass(target.classId);
    final extraPilots =
        (targetClass.pilotsRequired - 1) * targetClass.pilotHirePrice;
    if (problem == null && canSpend(target.price! + extraPilots)) {
      next = _growth.buyPlane(next, target.id);
      // A plane comes with one pilot; Large planes need a second.
      for (var i = 1; i < targetClass.pilotsRequired; i++) {
        next = sim.hirePilot(next, t);
      }
      final ledger = PlaneLedger(target.id, target.price!, played);
      report.planes.add(ledger);
      _ledgerOf[next.planes.last.id] = ledger;
    } else if (problem == RuleError.hangarFull &&
        canSpend(_growth.hangarExpansionPrice(next))) {
      next = _growth.buyHangarExpansion(next);
    } else if (problem == RuleError.noGate) {
      // Upgrade the airports the plane could use, home first.
      final home = next.airport(next.homeCityId!)!;
      final cost = _growth.airportUpgradeCost(home);
      if (cost != null &&
          _growth.upgradeAirportProblem(next, home.cityId) == null &&
          canSpend(cost)) {
        next = _growth.upgradeAirport(next, home.cityId, t);
        report.firstAirportUpgradeAt ??= played;
      }
    }

    // What is left over beyond the savings goes to the network.
    final saving = next.player.money < target.price! ? target.price! ~/ 2 : 0;
    bool spare(int cost) => canSpend(cost + saving);

    // 2. Airports big enough for the fleet's planes to land at.
    for (final a in next.airports) {
      if (classRank(a) >= rank && a.level >= 2) continue;
      final cost = _growth.airportUpgradeCost(a);
      if (cost == null) continue;
      if (_growth.upgradeAirportProblem(next, a.cityId) == null &&
          spare(cost)) {
        next = _growth.upgradeAirport(next, a.cityId, t);
        report.firstAirportUpgradeAt ??= played;
      }
    }

    // 3. A new airport for every plane or so, nearest first.
    if (next.airports.length < next.planes.length + 3) {
      final options = [
        for (final c in sim.rules.world.cities)
          if (_growth.buyAirportProblem(next, c.id) == null &&
              _growth.nearestOwned(next, c.id)!.km > 300 &&
              spare(_growth.airportPrice(next, c.id)))
            c,
      ];
      double away(String id) => _growth.nearestOwned(next, id)!.km;
      options.sort((a, b) => away(a.id).compareTo(away(b.id)));
      if (options.isNotEmpty) {
        next = _growth.buyAirport(next, options.first.id, t);
      }
    }

    // 4. A region license when one is cheap next to the savings.
    final license = _growth.nextLicense(next);
    if (license != null && spare(license.cost * 2)) {
      final home = next.homeCityId!;
      final regions = [
        for (final c in sim.rules.world.cities)
          if (!_growth.isLicensed(next, c.regionId)) c,
      ];
      regions.sort(
        (a, b) => sim.rules
            .distanceKm(home, a.id)
            .compareTo(sim.rules.distanceKm(home, b.id)),
      );
      if (regions.isNotEmpty &&
          _growth.licenseProblem(next, regions.first.regionId) == null) {
        next = _growth.buyLicense(next, regions.first.regionId);
      }
    }
    return next;
  }
}
