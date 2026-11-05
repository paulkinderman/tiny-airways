import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/state/game_state.dart';
import '../logic/simulation.dart';

/// How the player's own airports are ordered, on the Airports tab and when
/// stepping between airport panels.
enum AirportSort {
  /// Rival-led and close cities first, then idle planes and full boards.
  needsYou('Needs you'),
  share('Share'),
  level('Level'),
  name('A–Z');

  const AirportSort(this.label);
  final String label;
}

final airportSortProvider =
    NotifierProvider<AirportSortController, AirportSort>(
      AirportSortController.new,
    );

class AirportSortController extends Notifier<AirportSort> {
  @override
  AirportSort build() => AirportSort.needsYou;

  void set(AirportSort sort) => state = sort;
}

/// Where the player stands in a city's share race.
enum ShareStanding {
  /// City share hasn't unlocked yet.
  off,

  /// Nobody has enough share to lead.
  open,
  lead,

  /// The player leads, but the runner-up is within [closeMargin].
  leadClose,
  rivalLeads,
}

/// A share gap (0 to 1) small enough to call a race close.
const closeMargin = 0.08;

/// One owned airport at a glance: the numbers the Airports tab and the
/// panel strip show without opening it.
class OwnedAirportInfo {
  const OwnedAirportInfo({
    required this.airport,
    required this.name,
    required this.parked,
    required this.gates,
    required this.jobs,
    required this.boardSize,
    required this.standing,
    required this.share,
    required this.leaderId,
    required this.isHome,
    required this.isHub,
    required this.hubIn,
    required this.terminalPoints,
    required this.hasTerminal,
    required this.weather,
  });

  final AirportState airport;
  final String name;
  final int parked;
  final int gates;

  /// Fresh jobs on the board (not layovers) and the board's size.
  final int jobs;
  final int boardSize;
  final ShareStanding standing;
  final CityShare share;

  /// Who leads the city, or null.
  final String? leaderId;
  final bool isHome;
  final bool isHub;

  /// Time left until the city becomes a hub, while the share holds.
  final Duration? hubIn;
  final int terminalPoints;
  final bool hasTerminal;

  /// The weather over the airport now or next, if any.
  final WeatherEvent? weather;

  String get cityId => airport.cityId;
  double get myShare => share.fraction(playerAirlineId);

  /// The largest share among the rivals, 0 to 1.
  double get bestRivalShare {
    var best = 0.0;
    for (final id in share.points.keys) {
      if (id == playerAirlineId) continue;
      final f = share.fraction(id);
      if (f > best) best = f;
    }
    return best;
  }

  /// Higher means the player should look here sooner.
  int get urgency =>
      switch (standing) {
        ShareStanding.rivalLeads => 100,
        ShareStanding.leadClose => 60,
        ShareStanding.open => 10,
        _ => 0,
      } +
      parked * 25 +
      (terminalPoints > 0 ? 20 : 0) +
      (weather != null ? 10 : 0) +
      (boardSize > 0 && jobs >= boardSize ? 5 : 0);
}

/// Every owned airport's summary, ordered by [sort].
List<OwnedAirportInfo> ownedAirports(
  GameState state,
  Simulation sim,
  DateTime now,
  AirportSort sort,
) {
  final shareOn = sim.rivals.shareOn(state);
  final list = [
    for (final a in state.airports) _info(state, sim, now, a, shareOn),
  ];
  int byName(OwnedAirportInfo a, OwnedAirportInfo b) =>
      a.name.compareTo(b.name);
  list.sort(
    (a, b) => switch (sort) {
      AirportSort.needsYou => _then(b.urgency.compareTo(a.urgency), a, b),
      AirportSort.share => _then(b.myShare.compareTo(a.myShare), a, b),
      AirportSort.level => _then(
        b.airport.level.compareTo(a.airport.level),
        a,
        b,
      ),
      AirportSort.name => byName(a, b),
    },
  );
  return list;
}

OwnedAirportInfo _info(
  GameState state,
  Simulation sim,
  DateTime now,
  AirportState a,
  bool shareOn,
) {
  final rivals = sim.rivals;
  final share = state.rivals.share(a.cityId);
  final leader = rivals.leaderOf(state, a.cityId);
  final size = sim.boards.boardSize(state, a);
  final terminal = state.rivals.terminal(a.cityId);
  final isHub = rivals.isHub(state, a.cityId, now);
  WeatherEvent? weather;
  for (final e in state.weather.events) {
    if (e.endsAt.isAfter(now) &&
        sim.weather.covers(e, a.cityId) &&
        (weather == null || e.startsAt.isBefore(weather.startsAt))) {
      weather = e;
    }
  }
  var bestRival = 0.0;
  for (final id in share.points.keys) {
    if (id != playerAirlineId && share.fraction(id) > bestRival) {
      bestRival = share.fraction(id);
    }
  }
  final mine = share.fraction(playerAirlineId);
  return OwnedAirportInfo(
    airport: a,
    name: sim.rules.world.city(a.cityId).name,
    parked: state.planes
        .where((p) => p.status == PlaneStatus.parked && p.cityId == a.cityId)
        .length,
    gates: sim.flights.gates(a),
    jobs: a.board.where((j) => !j.isConnecting).length,
    boardSize: size.passenger + size.cargo,
    standing: !shareOn
        ? ShareStanding.off
        : leader == null
        ? ShareStanding.open
        : leader != playerAirlineId
        ? ShareStanding.rivalLeads
        : mine - bestRival < closeMargin
        ? ShareStanding.leadClose
        : ShareStanding.lead,
    share: share,
    leaderId: leader,
    isHome: state.homeCityId == a.cityId,
    isHub: isHub,
    hubIn: isHub ? null : rivals.hubIn(state, a.cityId, now),
    terminalPoints: terminal == null ? 0 : rivals.pointsToSpend(terminal),
    hasTerminal: terminal != null,
    weather: weather,
  );
}

int _then(int first, OwnedAirportInfo a, OwnedAirportInfo b) =>
    first != 0 ? first : a.name.compareTo(b.name);
