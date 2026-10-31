import '../core/state/game_state.dart';
import 'flights.dart' show SimReport;

/// The crew bonuses the core rules ask about. [GameCrew] (`crew.dart`)
/// answers from the crew assigned to each plane and airport; [NoCrew]
/// answers as if every plane has one level 1 rookie pilot and no one else,
/// which keeps rules tests independent of crew.
///
/// Percentages add to the matching rule's other bonuses.
abstract class CrewEffects {
  const CrewEffects();

  /// Why [plane] can't depart for lack of crew, or null if it can.
  String? departureProblem(GameState state, Plane plane);

  /// The captain's level, for fog landings.
  int captainLevel(GameState state, Plane plane);

  /// True if the crew can land in fog whatever the captain's level
  /// (Navigator's Region expert capstone).
  bool landsInFog(GameState state, Plane plane);

  bool hasRole(GameState state, Plane plane, String roleId);

  double speedPct(GameState state, Plane plane);

  double rangePct(GameState state, Plane plane);

  double fuelPct(GameState state, Plane plane);

  /// True if the plane never pays the jet stream's headwind (Tailwind).
  bool ignoresHeadwind(GameState state, Plane plane);

  /// Extra cargo slots (Packer).
  int extraCargoSlots(GameState state, Plane plane);

  /// Seats or slots [job] takes on [plane] (Tetris packs bulk crates
  /// into one).
  int jobSlots(GameState state, Plane plane, Job job);

  /// Empty cargo slots a hold may have and still count as full (Tight ship).
  int fullHoldSlack(GameState state, Plane plane);

  /// Extra pay for [job] delivered by [plane].
  double deliveryPayPct(GameState state, Plane plane, Job job);

  /// Multiplies [job]'s whole pay (Autopilot, Talk show, Heavy lift).
  double payMultiplier(GameState state, Plane plane, Job job);

  /// Extra time before [job]'s deadline on [plane] (Red carpet).
  Duration deadlineExtension(GameState state, Plane plane, Job job);

  /// Extra pay for jobs that appear on [cityId]'s board (airport manager).
  double boardPayPct(GameState state, String cityId, JobType type);

  /// Extra board slots at [cityId] (airport manager's Bigger board, station
  /// agent's Lost and found).
  int extraBoardSlots(GameState state, String cityId);

  /// True if [cityId]'s board favours far destinations, as connection jobs
  /// (Lost and found).
  bool favoursConnections(GameState state, String cityId);

  /// Percentage points added to the chance a new job at [cityId] is [kind]
  /// (Hub pride, VIP service, Charmer, Celebrity, Kid gloves).
  double specialChancePct(GameState state, String cityId, JobKind kind);

  /// Extra pay for jobs dropped at [cityId] to connect (station agent).
  double transferPayPct(GameState state, String cityId);

  /// How many times per rotation [cityId]'s board tops up its empty slots
  /// (Local hero makes it 2).
  int boardRefillsPerRotation(GameState state, String cityId);

  /// Called as [plane] (still carrying its load) lands at the end of [leg],
  /// after [delivered] jobs were paid. [unattended] is true when the
  /// landing happens while the player is away. Gives crew XP and returns
  /// any extra coins paid (Lucky, Red-eye), already added to the state.
  (GameState, int) afterLanding(
    GameState state,
    Plane plane,
    FlightLeg leg,
    List<({Job job, int pay})> delivered,
    DateTime t, {
    required bool unattended,
  });

  /// Runs after every simulation step and action: gives new planes their
  /// free pilot and sends planes on autopilot off again.
  GameState settle(GameState state, DateTime t, SimReport report);
}

class NoCrew extends CrewEffects {
  const NoCrew();

  @override
  String? departureProblem(GameState state, Plane plane) => null;

  @override
  int captainLevel(GameState state, Plane plane) => 1;

  @override
  bool landsInFog(GameState state, Plane plane) => false;

  @override
  bool hasRole(GameState state, Plane plane, String roleId) =>
      roleId == 'pilot';

  @override
  double speedPct(GameState state, Plane plane) => 0;

  @override
  double rangePct(GameState state, Plane plane) => 0;

  @override
  double fuelPct(GameState state, Plane plane) => 0;

  @override
  bool ignoresHeadwind(GameState state, Plane plane) => false;

  @override
  int extraCargoSlots(GameState state, Plane plane) => 0;

  @override
  int jobSlots(GameState state, Plane plane, Job job) => job.slots;

  @override
  int fullHoldSlack(GameState state, Plane plane) => 0;

  @override
  double deliveryPayPct(GameState state, Plane plane, Job job) => 0;

  @override
  double payMultiplier(GameState state, Plane plane, Job job) => 1;

  @override
  Duration deadlineExtension(GameState state, Plane plane, Job job) =>
      Duration.zero;

  @override
  double boardPayPct(GameState state, String cityId, JobType type) => 0;

  @override
  int extraBoardSlots(GameState state, String cityId) => 0;

  @override
  bool favoursConnections(GameState state, String cityId) => false;

  @override
  double specialChancePct(GameState state, String cityId, JobKind kind) => 0;

  @override
  double transferPayPct(GameState state, String cityId) => 0;

  @override
  int boardRefillsPerRotation(GameState state, String cityId) => 1;

  @override
  (GameState, int) afterLanding(
    GameState state,
    Plane plane,
    FlightLeg leg,
    List<({Job job, int pay})> delivered,
    DateTime t, {
    required bool unattended,
  }) => (state, 0);

  @override
  GameState settle(GameState state, DateTime t, SimReport report) => state;
}
