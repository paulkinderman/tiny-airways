import 'airport_state.dart';
import 'extras_state.dart';
import 'json.dart';
import 'plane_state.dart';
import 'weather_state.dart';

export 'airport_state.dart';
export 'extras_state.dart';
export 'job.dart';
export 'plane_state.dart';
export 'weather_state.dart';

/// The whole saved state of one airline.
///
/// This is the save schema's root. Whenever a field is added, removed or
/// renamed in a way old saves don't already match, bump `currentSaveVersion`
/// and add a migration in `lib/core/save/save_migrations.dart`.
///
/// A new game starts empty (no home city, airports or planes) until the
/// player picks a home city; `startAirline` in `lib/logic` fills it in.
class GameState {
  GameState({
    required this.createdAt,
    required this.lastSeenAt,
    required this.player,
    this.homeCityId,
    this.airports = const [],
    this.planes = const [],
    this.weather = const WeatherState(),
    this.stats = const StatsState(),
    this.nextId = 1,
    this.rngState = 0,
    DateTime? simulatedTo,
    this.boardRotation = 0,
    this.extras = ExtrasState.empty,
  }) : simulatedTo = simulatedTo ?? lastSeenAt;

  /// A brand-new airline, before the player picks a home city.
  factory GameState.newGame({
    required DateTime now,
    required int startingMoney,
  }) => GameState(
    createdAt: now,
    lastSeenAt: now,
    player: PlayerState(money: startingMoney, xp: 0, level: 1),
    rngState: now.millisecondsSinceEpoch & 0xFFFFFFFF,
  );

  final DateTime createdAt;

  /// When the game was last running.
  final DateTime lastSeenAt;

  final PlayerState player;

  /// Null until the player starts the airline.
  final String? homeCityId;
  final List<AirportState> airports;
  final List<Plane> planes;
  final WeatherState weather;
  final StatsState stats;

  /// Counter for new job, plane and weather ids.
  final int nextId;

  /// The game's random number generator state, so job boards and weather
  /// replay the same way after a reload.
  final int rngState;

  /// How far the simulation has run. Landings, weather and board rotations
  /// up to this time have been applied; offline catch-up starts here. It
  /// never moves backwards, so a clock set back just pauses the game.
  final DateTime simulatedTo;

  /// Index of the last board rotation applied (time since the epoch divided
  /// by `jobs.boardRotationMinutes`).
  final int boardRotation;

  /// Parts, special planes, challenges and milestones (package 10).
  final ExtrasState extras;

  bool get hasStarted => homeCityId != null;

  AirportState? airport(String cityId) {
    for (final a in airports) {
      if (a.cityId == cityId) return a;
    }
    return null;
  }

  bool ownsAirport(String cityId) => airport(cityId) != null;

  Plane? plane(String id) {
    for (final p in planes) {
      if (p.id == id) return p;
    }
    return null;
  }

  GameState copyWith({
    DateTime? lastSeenAt,
    PlayerState? player,
    String? homeCityId,
    List<AirportState>? airports,
    List<Plane>? planes,
    WeatherState? weather,
    StatsState? stats,
    int? nextId,
    int? rngState,
    DateTime? simulatedTo,
    int? boardRotation,
    ExtrasState? extras,
  }) => GameState(
    createdAt: createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    player: player ?? this.player,
    homeCityId: homeCityId ?? this.homeCityId,
    airports: airports ?? this.airports,
    planes: planes ?? this.planes,
    weather: weather ?? this.weather,
    stats: stats ?? this.stats,
    nextId: nextId ?? this.nextId,
    rngState: rngState ?? this.rngState,
    simulatedTo: simulatedTo ?? this.simulatedTo,
    boardRotation: boardRotation ?? this.boardRotation,
    extras: extras ?? this.extras,
  );

  /// Replaces the airport at [cityId] with `change(airport)`.
  GameState updateAirport(
    String cityId,
    AirportState Function(AirportState a) change,
  ) => copyWith(
    airports: [for (final a in airports) a.cityId == cityId ? change(a) : a],
  );

  /// Replaces the plane [id] with `change(plane)`.
  GameState updatePlane(String id, Plane Function(Plane p) change) =>
      copyWith(planes: [for (final p in planes) p.id == id ? change(p) : p]);

  Map<String, dynamic> toJson() => {
    'createdAt': encodeTime(createdAt),
    'lastSeenAt': encodeTime(lastSeenAt),
    'player': player.toJson(),
    'homeCityId': homeCityId,
    'airports': [for (final a in airports) a.toJson()],
    'planes': [for (final p in planes) p.toJson()],
    'weather': weather.toJson(),
    'stats': stats.toJson(),
    'nextId': nextId,
    'rngState': rngState,
    'simulatedTo': encodeTime(simulatedTo),
    'boardRotation': boardRotation,
    'extras': extras.toJson(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
    createdAt: decodeTime(json['createdAt']),
    lastSeenAt: decodeTime(json['lastSeenAt']),
    player: PlayerState.fromJson(json['player'] as Map<String, dynamic>),
    homeCityId: json['homeCityId'] as String?,
    airports: [
      for (final a in jsonList(json['airports'])) AirportState.fromJson(a),
    ],
    planes: [for (final p in jsonList(json['planes'])) Plane.fromJson(p)],
    weather: WeatherState.fromJson(json['weather'] as Map<String, dynamic>),
    stats: StatsState.fromJson(json['stats'] as Map<String, dynamic>),
    nextId: json['nextId'] as int,
    rngState: json['rngState'] as int,
    simulatedTo: decodeTime(json['simulatedTo']),
    boardRotation: json['boardRotation'] as int,
    extras: ExtrasState.fromJson(json['extras'] as Map<String, dynamic>?),
  );

  @override
  bool operator ==(Object other) =>
      other is GameState && jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(createdAt, lastSeenAt, player);
}

/// The airline's money, level, region licenses and hangar expansions.
class PlayerState {
  const PlayerState({
    required this.money,
    required this.xp,
    required this.level,
    this.licenses = const [],
    this.hangarExpansions = 0,
  });

  /// Coins. Never negative.
  final int money;

  /// Airline XP toward the next level.
  final int xp;

  /// Airline level, starting at 1.
  final int level;

  /// Regions bought with a license, in the order they were bought. The home
  /// region and regions where the player already owns an airport count as
  /// licensed without one (see `Growth.licensedRegions`).
  final List<String> licenses;

  /// Hangar expansions bought (each adds one plane slot).
  final int hangarExpansions;

  PlayerState copyWith({
    int? money,
    int? xp,
    int? level,
    List<String>? licenses,
    int? hangarExpansions,
  }) => PlayerState(
    money: money ?? this.money,
    xp: xp ?? this.xp,
    level: level ?? this.level,
    licenses: licenses ?? this.licenses,
    hangarExpansions: hangarExpansions ?? this.hangarExpansions,
  );

  Map<String, dynamic> toJson() => {
    'money': money,
    'xp': xp,
    'level': level,
    'licenses': licenses,
    'hangarExpansions': hangarExpansions,
  };

  // Saves from before package 6 have no licenses or expansions; they read as
  // none, which is what those airlines had, so no save version bump.
  factory PlayerState.fromJson(Map<String, dynamic> json) => PlayerState(
    money: json['money'] as int,
    xp: json['xp'] as int,
    level: json['level'] as int,
    licenses: ((json['licenses'] as List<dynamic>?) ?? const []).cast<String>(),
    hangarExpansions: (json['hangarExpansions'] as int?) ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerState &&
      other.money == money &&
      other.xp == xp &&
      other.level == level &&
      other.hangarExpansions == hangarExpansions &&
      other.licenses.join(',') == licenses.join(',');

  @override
  int get hashCode => Object.hash(money, xp, level, hangarExpansions);
}
