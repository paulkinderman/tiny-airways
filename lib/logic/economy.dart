import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'rules.dart';
import 'weather.dart';

/// A plane's working stats: its model plus upgrades and crew bonuses.
class PlaneStats {
  factory PlaneStats.of(Rules rules, GameState state, Plane plane) {
    final config = rules.config.planes;
    final model = config.model(plane.modelId);
    final up = config.upgrades;
    final extra = plane.upgrades.capacity * up.capacityPerLevel;
    final cargoOnly = model.seats == 0;
    return PlaneStats._(
      model: model,
      planeClass: config.planeClass(model.classId),
      seats: model.seats + (cargoOnly ? 0 : extra),
      cargoSlots:
          model.cargoSlots +
          (cargoOnly ? extra : 0) +
          (model.cargoSlots > 0 ? rules.crew.extraCargoSlots(state, plane) : 0),
      speedKmh:
          model.speedKmh *
          (1 +
              (plane.upgrades.speed * up.speedPctPerLevel +
                      rules.crew.speedPct(state, plane)) /
                  100),
      baseRangePct:
          plane.upgrades.range * up.rangePctPerLevel +
          rules.crew.rangePct(state, plane),
    );
  }

  const PlaneStats._({
    required this.model,
    required this.planeClass,
    required this.seats,
    required this.cargoSlots,
    required this.speedKmh,
    required this.baseRangePct,
  });

  final PlaneModel model;
  final PlaneClass planeClass;
  final int seats;
  final int cargoSlots;
  final double speedKmh;

  /// Range bonus from upgrades and crew, before any airport bonus.
  final double baseRangePct;

  /// Range with upgrades and crew, anywhere.
  double get rangeKm => model.rangeKm * (1 + baseRangePct / 100);

  /// Range for a leg leaving [from] (adds the Gateway tier 2 bonus there).
  double rangeFrom(Rules rules, AirportState? from) =>
      model.rangeKm *
      (1 + (baseRangePct + rules.pathEffect(from, 'departureRangePct')) / 100);
}

/// Money, fuel and airline XP.
class Economy {
  const Economy(this.rules);

  final Rules rules;

  /// Takes [amount] coins, refusing if the player can't afford it, so money
  /// never goes negative.
  GameState spend(GameState state, int amount) {
    require(amount <= state.player.money, RuleError.notEnoughMoney);
    return state.copyWith(
      player: state.player.copyWith(money: state.player.money - amount),
    );
  }

  /// Adds earned coins and the airline XP they bring.
  GameState earn(GameState state, int amount) {
    final paid = state.copyWith(
      player: state.player.copyWith(money: state.player.money + amount),
      stats: state.stats.copyWith(
        moneyEarned: state.stats.moneyEarned + amount,
      ),
    );
    return grantXp(paid, (amount * rules.config.jobs.airlineXpPerCoin).round());
  }

  /// Adds airline XP and levels up as many times as it reaches.
  GameState grantXp(GameState state, int xp) {
    final progression = rules.config.progression;
    var level = state.player.level;
    var total = state.player.xp + xp;
    while (level < progression.maxLevel &&
        total >= progression.xpToNext(level)) {
      total -= progression.xpToNext(level);
      level++;
    }
    return state.copyWith(
      player: state.player.copyWith(xp: total, level: level),
    );
  }

  /// Fuel for flying [plane] from [fromCityId] to [toCityId] leaving at [at]:
  /// fuel burn x km, adjusted by the Gateway path, snowstorms, the jet
  /// stream and crew.
  int fuelCost(
    GameState state,
    Plane plane,
    String fromCityId,
    String toCityId,
    DateTime at,
  ) {
    final model = rules.config.planes.model(plane.modelId);
    final km = rules.distanceKm(fromCityId, toCityId);
    final weather = WeatherRules(rules);
    var jet = model.ignoresJetStream
        ? 0.0
        : weather.jetStreamFuelPct(state, fromCityId, toCityId, at);
    if (jet > 0 && rules.crew.ignoresHeadwind(state, plane)) jet = 0;
    final pct =
        rules.pathEffect(state.airport(fromCityId), 'departureFuelPct') +
        weather.departureFuelPct(state, fromCityId, at) +
        jet +
        rules.crew.fuelPct(state, plane);
    final cost = model.fuelPerKm * km * (1 + pct / 100);
    return cost <= 0 ? 0 : cost.round();
  }
}
