import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'rng.dart';
import 'rules.dart';

/// Weather events: where they are, what they change, and rolling new ones.
///
/// Event effects are read by key from `weather.json`, so any event can use
/// any effect:
///
/// - `closesAirport`: planes can't land or take off there.
/// - `minCaptainLevel`: only planes whose captain is at least this level can
///   land (or whose crew lands in fog anyway).
/// - `payPct`, `outboundPayPct`: jobs appearing there pay more.
/// - `cargoPayPct`: cargo jobs appearing there pay more.
/// - `departureFuelPct`: fuel for departures there costs more.
/// - `largePlaneSeatPenalty`: Large planes departing there carry this many
///   fewer passengers.
/// - `withFuelPct`, `againstFuelPct`: fuel for legs flown with or against a
///   jet stream.
/// - `afterClearPayPct` for `afterClearMinutes`: when it clears, the board
///   refills with jobs paying more for a while.
class WeatherRules {
  const WeatherRules(this.rules);

  final Rules rules;

  WeatherConfig get config => rules.config.weather;

  WeatherEventConfig type(String typeId) =>
      config.events.firstWhere((e) => e.id == typeId);

  double effect(WeatherEvent event, String key) =>
      type(event.typeId).effects[key] ?? 0;

  /// True if [cityId] is inside [event]'s area.
  bool covers(WeatherEvent event, String cityId) {
    final city = rules.world.city(cityId);
    return switch (type(event.typeId).area) {
      'airport' => event.cityId == cityId,
      'cluster' =>
        WorldData.distanceKm(rules.world.city(event.cityId!), city) <=
            config.clusterRadiusKm,
      _ => (city.lat - event.bandLat!).abs() <= config.bandHalfWidthDeg,
    };
  }

  /// Events in effect at [t] whose area covers [cityId].
  Iterable<WeatherEvent> activeAt(GameState state, String cityId, DateTime t) =>
      state.weather.events.where(
        (e) =>
            e.activeAt(t) && type(e.typeId).area != 'band' && covers(e, cityId),
      );

  double _sum(GameState state, String cityId, DateTime t, String key) =>
      activeAt(state, cityId, t).fold(0.0, (sum, e) => sum + effect(e, key));

  bool isClosed(GameState state, String cityId, DateTime t) =>
      _sum(state, cityId, t, 'closesAirport') > 0;

  /// The captain level fog asks for at [cityId], or 0 if there is no fog.
  int fogCaptainLevel(GameState state, String cityId, DateTime t) =>
      activeAt(state, cityId, t)
          .map((e) => effect(e, 'minCaptainLevel').round())
          .fold(0, (a, b) => a > b ? a : b);

  /// Whether [plane] may land at [cityId] at [t].
  bool canLand(GameState state, Plane plane, String cityId, DateTime t) {
    if (isClosed(state, cityId, t)) return false;
    final fog = fogCaptainLevel(state, cityId, t);
    return fog == 0 ||
        rules.crew.landsInFog(state, plane) ||
        rules.crew.captainLevel(state, plane) >= fog;
  }

  double departureFuelPct(GameState state, String cityId, DateTime t) =>
      _sum(state, cityId, t, 'departureFuelPct');

  int seatPenalty(
    GameState state,
    String cityId,
    String planeClassId,
    DateTime t,
  ) => planeClassId == 'large'
      ? _sum(state, cityId, t, 'largePlaneSeatPenalty').round()
      : 0;

  /// Extra percent for a job of [type] appearing at [cityId] at [t].
  double jobPayPct(
    GameState state,
    String cityId,
    JobType jobType,
    DateTime t,
  ) {
    var pct =
        _sum(state, cityId, t, 'payPct') +
        _sum(state, cityId, t, 'outboundPayPct') +
        (jobType == JobType.cargo ? _sum(state, cityId, t, 'cargoPayPct') : 0);
    for (final e in state.weather.events) {
      final minutes = effect(e, 'afterClearMinutes');
      if (minutes <= 0 || !covers(e, cityId)) continue;
      final until = e.endsAt.add(Duration(minutes: minutes.round()));
      if (!t.isBefore(e.endsAt) && t.isBefore(until)) {
        pct += effect(e, 'afterClearPayPct');
      }
    }
    return pct;
  }

  /// Fuel percent for a leg from [fromCityId] to [toCityId] from any jet
  /// stream active at [t]. A leg rides a stream when both ends are inside
  /// its band and one end is on its continent; flying the stream's way
  /// saves fuel and flying against it costs more.
  double jetStreamFuelPct(
    GameState state,
    String fromCityId,
    String toCityId,
    DateTime t,
  ) {
    final from = rules.world.city(fromCityId);
    final to = rules.world.city(toCityId);
    var dLon = to.lon - from.lon;
    if (dLon > 180) dLon -= 360;
    if (dLon < -180) dLon += 360;
    if (dLon == 0) return 0;
    var pct = 0.0;
    for (final e in state.weather.events) {
      if (!e.activeAt(t) || type(e.typeId).area != 'band') continue;
      if (!covers(e, fromCityId) || !covers(e, toCityId)) continue;
      if (from.regionId != e.regionId && to.regionId != e.regionId) continue;
      final withIt = (dLon > 0) == e.eastbound;
      pct += effect(e, withIt ? 'withFuelPct' : 'againstFuelPct');
    }
    return pct;
  }

  /// Regions that get weather: every continent with an owned airport.
  Set<String> weatherRegions(GameState state) => {
    for (final a in state.airports) rules.world.city(a.cityId).regionId,
  };

  Duration _interval(GameRng rng) => Duration(
    minutes: rng.between(config.minIntervalMinutes, config.maxIntervalMinutes),
  );

  /// Gives every weather region without one a time for its next event.
  GameState schedule(GameState state, DateTime t) {
    final missing = weatherRegions(
      state,
    ).where((r) => !state.weather.nextEventAt.containsKey(r)).toList()..sort();
    if (missing.isEmpty) return state;
    final rng = GameRng(state.rngState);
    final next = {...state.weather.nextEventAt};
    for (final region in missing) {
      next[region] = t.add(_interval(rng));
    }
    return state.copyWith(
      rngState: rng.state,
      weather: state.weather.copyWith(nextEventAt: next),
    );
  }

  Duration get forecast => Duration(minutes: config.forecastMinutes);

  /// When [regionId]'s next event gets forecast (and so rolled).
  DateTime rollTime(GameState state, String regionId) =>
      state.weather.nextEventAt[regionId]!.subtract(forecast);

  /// Rolls [regionId]'s next event at [t] (its forecast time) and schedules
  /// the one after.
  GameState roll(GameState state, String regionId, DateTime t) {
    final rng = GameRng(state.rngState);
    final startsAt = state.weather.nextEventAt[regionId]!;
    final next = {...state.weather.nextEventAt}
      ..[regionId] = startsAt.add(_interval(rng));
    final owned = [
      for (final a in state.airports)
        if (rules.world.city(a.cityId).regionId == regionId) a.cityId,
    ];
    var nextId = state.nextId;
    final events = [...state.weather.events];
    if (owned.isNotEmpty) {
      final kind = rng.pick(config.events);
      final city = rng.pick(owned);
      final band = kind.area == 'band';
      events.add(
        WeatherEvent(
          id: 'w${nextId++}',
          typeId: kind.id,
          regionId: regionId,
          forecastAt: t,
          startsAt: startsAt,
          endsAt: startsAt.add(
            Duration(minutes: rng.between(kind.minMinutes, kind.maxMinutes)),
          ),
          cityId: band ? null : city,
          bandLat: band ? rules.world.city(city).lat : null,
          eastbound: band ? rng.nextBool() : null,
        ),
      );
    }
    return state.copyWith(
      rngState: rng.state,
      nextId: nextId,
      weather: state.weather.copyWith(events: events, nextEventAt: next),
    );
  }

  /// When [event] stops mattering (after any after-clear bonus).
  DateTime finishedAt(WeatherEvent event) => event.endsAt.add(
    Duration(minutes: effect(event, 'afterClearMinutes').round()),
  );

  /// Drops events that are over.
  GameState prune(GameState state, DateTime t) {
    final kept = [
      for (final e in state.weather.events)
        if (finishedAt(e).isAfter(t)) e,
    ];
    if (kept.length == state.weather.events.length) return state;
    return state.copyWith(weather: state.weather.copyWith(events: kept));
  }
}
