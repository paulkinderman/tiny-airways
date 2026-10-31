import 'json.dart';

/// The airline id the player uses in share tables, contract scores and
/// season wins. Rivals use their roster id.
const playerAirlineId = 'player';

/// Rival airlines and everything the player competes with them for: city
/// share, terminals, contracts and seasons (design doc, Rival airlines).
///
/// Rivals themselves are mostly worked out from the config and the player's
/// level each time they are needed; only what can't be worked out again is
/// saved here. Saves from before rivals load with an empty [RivalsState].
class RivalsState {
  const RivalsState({
    this.difficulty = defaultDifficulty,
    this.cities = const {},
    this.terminals = const [],
    this.lostTerminalCityIds = const [],
    this.heatedRivalIds = const [],
    this.contracts = const [],
    this.nextContractAt,
    this.season = const SeasonState(),
    this.lastStepAt,
  });

  static const defaultDifficulty = 'cruising_altitude';

  /// A `rivals.difficulties[].id`, picked with the starting continent.
  final String difficulty;

  /// Share meters, by city id. Cities nobody has delivered to are missing.
  final Map<String, CityShare> cities;

  /// The player's terminals.
  final List<PlayerTerminal> terminals;

  /// Rival terminals the player has taken over (the city's terminal is up
  /// for lease until the player builds there).
  final List<String> lostTerminalCityIds;

  /// Rivals that turned "heated" toward the player.
  final List<String> heatedRivalIds;

  /// The live contract (if any) first, then the last few finished ones.
  final List<Contract> contracts;
  final DateTime? nextContractAt;
  final SeasonState season;

  /// The last rival step (share decay, rival deliveries, contract races).
  final DateTime? lastStepAt;

  CityShare share(String cityId) => cities[cityId] ?? const CityShare();

  PlayerTerminal? terminal(String cityId) {
    for (final t in terminals) {
      if (t.cityId == cityId) return t;
    }
    return null;
  }

  Contract? get liveContract {
    for (final c in contracts) {
      if (c.isLive) return c;
    }
    return null;
  }

  RivalsState copyWith({
    String? difficulty,
    Map<String, CityShare>? cities,
    List<PlayerTerminal>? terminals,
    List<String>? lostTerminalCityIds,
    List<String>? heatedRivalIds,
    List<Contract>? contracts,
    DateTime? Function()? nextContractAt,
    SeasonState? season,
    DateTime? lastStepAt,
  }) => RivalsState(
    difficulty: difficulty ?? this.difficulty,
    cities: cities ?? this.cities,
    terminals: terminals ?? this.terminals,
    lostTerminalCityIds: lostTerminalCityIds ?? this.lostTerminalCityIds,
    heatedRivalIds: heatedRivalIds ?? this.heatedRivalIds,
    contracts: contracts ?? this.contracts,
    nextContractAt: nextContractAt != null
        ? nextContractAt()
        : this.nextContractAt,
    season: season ?? this.season,
    lastStepAt: lastStepAt ?? this.lastStepAt,
  );

  RivalsState updateCity(String cityId, CityShare Function(CityShare s) f) =>
      copyWith(cities: {...cities, cityId: f(share(cityId))});

  RivalsState updateTerminal(
    String cityId,
    PlayerTerminal Function(PlayerTerminal t) f,
  ) => copyWith(
    terminals: [for (final t in terminals) t.cityId == cityId ? f(t) : t],
  );

  Map<String, dynamic> toJson() => {
    'difficulty': difficulty,
    'cities': {for (final e in cities.entries) e.key: e.value.toJson()},
    'terminals': [for (final t in terminals) t.toJson()],
    'lostTerminalCityIds': lostTerminalCityIds,
    'heatedRivalIds': heatedRivalIds,
    'contracts': [for (final c in contracts) c.toJson()],
    'nextContractAt': encodeTimeOrNull(nextContractAt),
    'season': season.toJson(),
    'lastStepAt': encodeTimeOrNull(lastStepAt),
  };

  factory RivalsState.fromJson(Map<String, dynamic> json) => RivalsState(
    difficulty: json['difficulty'] as String,
    cities: {
      for (final e in (json['cities'] as Map<String, dynamic>).entries)
        e.key: CityShare.fromJson(e.value as Map<String, dynamic>),
    },
    terminals: [
      for (final t in jsonList(json['terminals'])) PlayerTerminal.fromJson(t),
    ],
    lostTerminalCityIds: (json['lostTerminalCityIds'] as List<dynamic>)
        .cast<String>(),
    heatedRivalIds: (json['heatedRivalIds'] as List<dynamic>).cast<String>(),
    contracts: [
      for (final c in jsonList(json['contracts'])) Contract.fromJson(c),
    ],
    nextContractAt: decodeTimeOrNull(json['nextContractAt']),
    season: SeasonState.fromJson(json['season'] as Map<String, dynamic>),
    lastStepAt: decodeTimeOrNull(json['lastStepAt']),
  );
}

/// One city's share meter.
class CityShare {
  const CityShare({
    this.points = const {},
    this.playerHubSince,
    this.playerLeadSince,
  });

  /// Share points by airline id ([playerAirlineId] or a rival id). Each
  /// delivery adds points in proportion to its pay; points decay hourly.
  final Map<String, double> points;

  /// When the player's share last rose to the hub threshold (50%), while it
  /// has stayed there.
  final DateTime? playerHubSince;

  /// When the player last took the lead, while they have kept it.
  final DateTime? playerLeadSince;

  double get total => points.values.fold(0.0, (a, b) => a + b);

  double of(String airlineId) => points[airlineId] ?? 0;

  /// [airlineId]'s share, 0 to 1.
  double fraction(String airlineId) {
    final sum = total;
    return sum <= 0 ? 0 : of(airlineId) / sum;
  }

  /// The airline with the most points, or null if nobody has any. Ties go
  /// to the player, then to the lower id, so it never flickers.
  String? get leader {
    String? best;
    var bestPoints = 0.0;
    final ids = points.keys.toList()
      ..sort((a, b) {
        if (a == playerAirlineId) return -1;
        if (b == playerAirlineId) return 1;
        return a.compareTo(b);
      });
    for (final id in ids) {
      if (points[id]! > bestPoints) {
        best = id;
        bestPoints = points[id]!;
      }
    }
    return best;
  }

  CityShare copyWith({
    Map<String, double>? points,
    DateTime? Function()? playerHubSince,
    DateTime? Function()? playerLeadSince,
  }) => CityShare(
    points: points ?? this.points,
    playerHubSince: playerHubSince != null
        ? playerHubSince()
        : this.playerHubSince,
    playerLeadSince: playerLeadSince != null
        ? playerLeadSince()
        : this.playerLeadSince,
  );

  CityShare add(String airlineId, double amount) =>
      copyWith(points: {...points, airlineId: of(airlineId) + amount});

  Map<String, dynamic> toJson() => {
    'points': points,
    'playerHubSince': encodeTimeOrNull(playerHubSince),
    'playerLeadSince': encodeTimeOrNull(playerLeadSince),
  };

  factory CityShare.fromJson(Map<String, dynamic> json) => CityShare(
    points: {
      for (final e in (json['points'] as Map<String, dynamic>).entries)
        e.key: (e.value as num).toDouble(),
    },
    playerHubSince: decodeTimeOrNull(json['playerHubSince']),
    playerLeadSince: decodeTimeOrNull(json['playerLeadSince']),
  );
}

/// A terminal the player built or leased. Once built it is the player's for
/// good.
class PlayerTerminal {
  const PlayerTerminal({
    required this.cityId,
    required this.builtAt,
    this.jobs = 0,
    this.nodes = const {},
  });

  final String cityId;
  final DateTime builtAt;

  /// Jobs delivered to or from the city since the terminal opened; every
  /// `terminal.jobsPerPoint` earns a terminal point.
  final int jobs;

  /// Nodes learned in each branch, top down.
  final Map<String, int> nodes;

  int learned(String branchId) => nodes[branchId] ?? 0;
  int get spent => nodes.values.fold(0, (a, b) => a + b);

  PlayerTerminal copyWith({int? jobs, Map<String, int>? nodes}) =>
      PlayerTerminal(
        cityId: cityId,
        builtAt: builtAt,
        jobs: jobs ?? this.jobs,
        nodes: nodes ?? this.nodes,
      );

  Map<String, dynamic> toJson() => {
    'cityId': cityId,
    'builtAt': encodeTime(builtAt),
    'jobs': jobs,
    'nodes': nodes,
  };

  factory PlayerTerminal.fromJson(Map<String, dynamic> json) => PlayerTerminal(
    cityId: json['cityId'] as String,
    builtAt: decodeTime(json['builtAt']),
    jobs: json['jobs'] as int,
    nodes: (json['nodes'] as Map<String, dynamic>).cast<String, int>(),
  );
}

/// "First to deliver 15 jobs to Lima wins 50,000."
class Contract {
  const Contract({
    required this.id,
    required this.cityId,
    required this.jobsToWin,
    required this.prize,
    required this.startsAt,
    required this.endsAt,
    required this.rivalIds,
    this.scores = const {},
    this.winnerId,
    this.finishedAt,
  });

  final String id;
  final String cityId;
  final int jobsToWin;
  final int prize;
  final DateTime startsAt;

  /// Nobody wins if nobody gets there by now.
  final DateTime endsAt;

  /// The rivals racing the player.
  final List<String> rivalIds;

  /// Jobs delivered to the city so far, by airline id.
  final Map<String, int> scores;

  /// The airline that won, once someone has.
  final String? winnerId;
  final DateTime? finishedAt;

  bool get isLive => finishedAt == null;
  int score(String airlineId) => scores[airlineId] ?? 0;

  Contract copyWith({
    Map<String, int>? scores,
    String? winnerId,
    DateTime? finishedAt,
  }) => Contract(
    id: id,
    cityId: cityId,
    jobsToWin: jobsToWin,
    prize: prize,
    startsAt: startsAt,
    endsAt: endsAt,
    rivalIds: rivalIds,
    scores: scores ?? this.scores,
    winnerId: winnerId ?? this.winnerId,
    finishedAt: finishedAt ?? this.finishedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'cityId': cityId,
    'jobsToWin': jobsToWin,
    'prize': prize,
    'startsAt': encodeTime(startsAt),
    'endsAt': encodeTime(endsAt),
    'rivalIds': rivalIds,
    'scores': scores,
    'winnerId': winnerId,
    'finishedAt': encodeTimeOrNull(finishedAt),
  };

  factory Contract.fromJson(Map<String, dynamic> json) => Contract(
    id: json['id'] as String,
    cityId: json['cityId'] as String,
    jobsToWin: json['jobsToWin'] as int,
    prize: json['prize'] as int,
    startsAt: decodeTime(json['startsAt']),
    endsAt: decodeTime(json['endsAt']),
    rivalIds: (json['rivalIds'] as List<dynamic>).cast<String>(),
    scores: (json['scores'] as Map<String, dynamic>).cast<String, int>(),
    winnerId: json['winnerId'] as String?,
    finishedAt: decodeTimeOrNull(json['finishedAt']),
  );
}

/// The current two-week season and how past ones ended.
class SeasonState {
  const SeasonState({
    this.number = 1,
    this.startedAt,
    this.wins = const {},
    this.history = const [],
  });

  final int number;

  /// Set at the first rival step after the airline starts.
  final DateTime? startedAt;

  /// Contracts won this season: rivals by id, the player by
  /// `player:<regionId>` (each continent has its own board).
  final Map<String, int> wins;
  final List<SeasonResult> history;

  static String playerKey(String regionId) => '$playerAirlineId:$regionId';

  SeasonState copyWith({
    int? number,
    DateTime? startedAt,
    Map<String, int>? wins,
    List<SeasonResult>? history,
  }) => SeasonState(
    number: number ?? this.number,
    startedAt: startedAt ?? this.startedAt,
    wins: wins ?? this.wins,
    history: history ?? this.history,
  );

  Map<String, dynamic> toJson() => {
    'number': number,
    'startedAt': encodeTimeOrNull(startedAt),
    'wins': wins,
    'history': [for (final h in history) h.toJson()],
  };

  factory SeasonState.fromJson(Map<String, dynamic> json) => SeasonState(
    number: json['number'] as int,
    startedAt: decodeTimeOrNull(json['startedAt']),
    wins: (json['wins'] as Map<String, dynamic>).cast<String, int>(),
    history: [
      for (final h in jsonList(json['history'])) SeasonResult.fromJson(h),
    ],
  );
}

/// Where the player finished one season on one continent.
class SeasonResult {
  const SeasonResult({
    required this.number,
    required this.regionId,
    required this.rank,
    required this.difficulty,
    this.trophyRivalIds = const [],
  });

  final int number;
  final String regionId;

  /// 1 is first.
  final int rank;

  /// The difficulty the season ended on, shown as a badge.
  final String difficulty;

  /// Rivals the player finished above: a trophy and their season livery
  /// for each.
  final List<String> trophyRivalIds;

  Map<String, dynamic> toJson() => {
    'number': number,
    'regionId': regionId,
    'rank': rank,
    'difficulty': difficulty,
    'trophyRivalIds': trophyRivalIds,
  };

  factory SeasonResult.fromJson(Map<String, dynamic> json) => SeasonResult(
    number: json['number'] as int,
    regionId: json['regionId'] as String,
    rank: json['rank'] as int,
    difficulty: json['difficulty'] as String,
    trophyRivalIds: (json['trophyRivalIds'] as List<dynamic>).cast<String>(),
  );
}
