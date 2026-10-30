import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

/// A 5-minute board mark, so tests start just as boards rotate.
final t0 = DateTime.utc(2026, 3, 2, 12);

/// Far enough away that no weather rolls during a test.
final never = DateTime.utc(2100);

GameConfig? _config;

Future<GameConfig> shippedConfig() async =>
    _config ??= await ConfigLoader(DirectoryConfigSource('assets')).load();

/// A crew stand-in for rules that ask about crew before package 7.
class TestCrew extends NoCrew {
  const TestCrew({
    this.captain = 1,
    this.roles = const {'pilot'},
    this.fogLanding = false,
  });

  final int captain;
  final Set<String> roles;
  final bool fogLanding;

  @override
  int captainLevel(GameState state, Plane plane) => captain;

  @override
  bool landsInFog(GameState state, Plane plane) => fogLanding;

  @override
  bool hasRole(GameState state, Plane plane, String roleId) =>
      roles.contains(roleId);
}

/// A started airline built by hand, with no weather scheduled and boards
/// as given (empty unless a test fills them), so every number is known.
GameState airline({
  List<AirportState> airports = const [],
  List<Plane> planes = const [],
  int money = 10000,
  int level = 1,
  List<WeatherEvent> weather = const [],
  DateTime? at,
  int? boardRotation,
}) {
  final now = at ?? t0;
  return GameState(
    createdAt: now,
    lastSeenAt: now,
    player: PlayerState(money: money, xp: 0, level: level),
    homeCityId: airports.first.cityId,
    airports: airports,
    planes: planes,
    weather: WeatherState(
      events: weather,
      nextEventAt: {
        for (final r in [
          'north_america',
          'south_america',
          'europe',
          'africa',
          'asia',
          'oceania',
          'antarctica',
        ])
          r: never,
      },
    ),
    nextId: 1000,
    rngState: 42,
    simulatedTo: now,
    // Boards last rotated at [now] (jobs.boardRotationMinutes is 5).
    boardRotation:
        boardRotation ?? now.millisecondsSinceEpoch ~/ (5 * 60 * 1000),
  );
}

Job job(
  String id,
  String from,
  String to, {
  JobType type = JobType.passenger,
  JobKind kind = JobKind.standard,
  int payout = 100,
  int slots = 1,
  DateTime? deadline,
  DateTime? connectingSince,
}) => Job(
  id: id,
  type: type,
  kind: kind,
  originCityId: from,
  destCityId: to,
  payout: payout,
  createdAt: t0,
  slots: slots,
  deadline: deadline,
  connectingSince: connectingSince,
);

Job cargo(
  String id,
  String from,
  String to, {
  int payout = 100,
  int slots = 1,
}) => job(id, from, to, type: JobType.cargo, payout: payout, slots: slots);

/// Runs the simulation to [t] and returns the state.
GameState runTo(Simulation sim, GameState state, DateTime t) =>
    sim.advance(state, t).$1;
