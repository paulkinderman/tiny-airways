import '../core/state/game_state.dart';
import 'flights.dart';
import 'job_boards.dart';
import 'loading.dart';
import 'rules.dart';
import 'weather.dart';

export 'economy.dart';
export 'flights.dart';
export 'growth.dart';
export 'job_boards.dart';
export 'loading.dart';
export 'rules.dart';
export 'weather.dart';

/// The game's entry point for the screens: starting an airline, moving time
/// forward, and every player action.
///
/// Every action first runs the simulation up to [now], so it happens in an
/// up-to-date world, then returns the new state. Actions throw
/// [RuleException] when the rules refuse them, and leave the state alone.
///
/// Time never runs backwards: if the device clock is set back, the game
/// treats "now" as the last time it simulated, so flights hold until the
/// clock catches up.
class Simulation {
  const Simulation(this.rules);

  final Rules rules;

  Flights get flights => Flights(rules);
  JobBoards get boards => JobBoards(rules);
  Loading get loading => Loading(rules);
  WeatherRules get weather => WeatherRules(rules);

  DateTime _at(GameState state, DateTime now) =>
      now.isBefore(state.simulatedTo) ? state.simulatedTo : now;

  /// Starts the airline at [homeCityId]: the home airport, the nearest free
  /// airport the starting plane can reach, the starting plane parked at home,
  /// full job boards and the first weather schedule.
  GameState startAirline(GameState state, String homeCityId, DateTime now) {
    require(!state.hasStarted, RuleError.alreadyStarted);
    require(rules.world.hasCity(homeCityId), RuleError.unknownCity);
    final t = _at(state, now);
    final economy = rules.config.economy;
    final jobs = rules.config.jobs;
    final home = rules.world.city(homeCityId);
    final model = rules.config.planes.model(economy.startingPlaneModelId);

    bool usable(double km) => km >= jobs.minJobDistanceKm;
    double km(String id) => rules.distanceKm(homeCityId, id);
    final byDistance = [
      for (final c in rules.world.cities)
        if (c.id != homeCityId && usable(km(c.id))) c,
    ]..sort((a, b) => km(a.id).compareTo(km(b.id)));
    // Nearest in the home region within the starting plane's range; failing
    // that, nearest anywhere in range; failing that, nearest in the region.
    final inRange = byDistance.where((c) => km(c.id) <= model.rangeKm);
    final free = [
      ...inRange.where((c) => c.regionId == home.regionId),
      ...inRange.where((c) => c.regionId != home.regionId),
      ...byDistance.where((c) => c.regionId == home.regionId),
    ].map((c) => c.id).toSet().take(economy.freeNearbyAirports);

    var next = state.copyWith(
      homeCityId: homeCityId,
      airports: [
        AirportState(cityId: homeCityId, level: economy.homeAirportStartLevel),
        for (final id in free) AirportState(cityId: id),
      ],
      planes: [
        Plane(id: 'p${state.nextId}', modelId: model.id, cityId: homeCityId),
      ],
      nextId: state.nextId + 1,
      simulatedTo: t,
      boardRotation: boards.rotationIndex(t),
    );
    for (final a in next.airports) {
      next = boards.fill(next, a.cityId, t);
    }
    return weather.schedule(next, t);
  }

  /// Runs the world forward to [now]: landings, transfers, diversions,
  /// holding patterns, weather and board rotations, in time order. The same
  /// call does the live tick and the offline catch-up on launch; the report
  /// is the welcome-back summary.
  (GameState, SimReport) advance(GameState state, DateTime now) {
    final report = SimReport();
    if (!now.isAfter(state.simulatedTo)) return (state, report);
    if (!state.hasStarted) return (state.copyWith(simulatedTo: now), report);

    // Regions whose first airport was just bought get their weather clock.
    var next = weather.schedule(state, state.simulatedTo);
    while (true) {
      final cursor = next.simulatedTo;
      DateTime? soonest;
      void consider(DateTime t) {
        if (t.isAfter(now)) return;
        if (soonest == null || t.isBefore(soonest!)) soonest = t;
      }

      for (final p in next.planes) {
        if (p.status == PlaneStatus.flying) consider(p.leg!.arriveAt);
      }
      for (final region in next.weather.nextEventAt.keys) {
        consider(weather.rollTime(next, region));
      }
      for (final e in next.weather.events) {
        if (e.endsAt.isAfter(cursor)) consider(e.endsAt);
      }
      final found = soonest;
      if (found == null) break;
      final t = found.isBefore(cursor) ? cursor : found;
      next = _step(next, t, cursor, report);
    }

    final levelBefore = next.player.level;
    next = boards.rotateIfDue(next, now);
    next = weather.prune(next, now).copyWith(simulatedTo: now);
    report.levelsGained += next.player.level - levelBefore;
    return (next, report);
  }

  /// Applies everything that happens at [t].
  GameState _step(
    GameState state,
    DateTime t,
    DateTime cursor,
    SimReport report,
  ) {
    var next = state;
    // Boards rotate on their marks between events, so jobs dropped to
    // connect meet the board as it was then.
    next = boards.rotateIfDue(next, t);

    final regions = next.weather.nextEventAt.keys.toList()..sort();
    for (final region in regions) {
      if (weather.rollTime(next, region) == t) {
        final before = next.weather.events.length;
        next = weather.roll(next, region, t);
        report.newWeatherIds.addAll(
          next.weather.events.skip(before).map((e) => e.id),
        );
      }
    }

    for (final e in next.weather.events) {
      if (e.endsAt == t && e.endsAt.isAfter(cursor)) {
        final rush = weather.effect(e, 'afterClearMinutes') > 0;
        if (rush && e.cityId != null && next.ownsAirport(e.cityId!)) {
          next = boards.rotate(next, e.cityId!, t);
        }
      }
    }

    final landing = [
      for (final p in next.planes)
        if (p.status == PlaneStatus.flying && p.leg!.arriveAt == t) p.id,
    ]..sort();
    for (final id in landing) {
      next = flights.arrive(next, id, t, report);
    }

    next = flights.landHolding(next, null, t, report);
    next = weather.schedule(next, t);
    return next.copyWith(simulatedTo: t);
  }

  /// Loads [jobId] onto parked [planeId]; see [Loading.load].
  GameState loadJob(
    GameState state,
    String planeId,
    String jobId,
    DateTime now, {
    String? dropAtCityId,
  }) {
    final (s, _) = advance(state, now);
    return loading.load(
      s,
      planeId,
      jobId,
      s.simulatedTo,
      dropAtCityId: dropAtCityId,
    );
  }

  GameState unloadJob(
    GameState state,
    String planeId,
    String jobId,
    DateTime now,
  ) {
    final (s, _) = advance(state, now);
    return loading.unload(s, planeId, jobId, s.simulatedTo);
  }

  GameState fillTo(
    GameState state,
    String planeId,
    String destCityId,
    DateTime now,
  ) {
    final (s, _) = advance(state, now);
    return loading.fillTo(s, planeId, destCityId, s.simulatedTo);
  }

  /// Pays to swap out [cityId]'s board now.
  GameState refreshBoard(GameState state, String cityId, DateTime now) {
    final (s, _) = advance(state, now);
    return boards.refresh(s, cityId, s.simulatedTo);
  }

  /// Plans a route for the route picker.
  RouteQuote quote(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime now,
  ) {
    final (s, _) = advance(state, now);
    return flights.quote(s, planeId, stops, s.simulatedTo);
  }

  /// Sends [planeId] off through [stops].
  GameState depart(
    GameState state,
    String planeId,
    List<String> stops,
    DateTime now,
  ) {
    final (s, _) = advance(state, now);
    return flights.depart(s, planeId, stops, s.simulatedTo);
  }
}
