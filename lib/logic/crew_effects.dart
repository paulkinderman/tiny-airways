import '../core/state/game_state.dart';

/// The crew bonuses the core rules ask about. Crew (package 7) implements
/// this from the crew assigned to each plane and airport; until then
/// [NoCrew] answers as if every plane has one level 1 rookie pilot and no
/// one else.
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

  /// Extra pay for [job] delivered by [plane].
  double deliveryPayPct(GameState state, Plane plane, Job job);

  /// Extra pay for jobs that appear on [cityId]'s board (airport manager).
  double boardPayPct(GameState state, String cityId, JobType type);

  /// Extra board slots at [cityId] (airport manager's Bigger board).
  int extraBoardSlots(GameState state, String cityId);
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
  double deliveryPayPct(GameState state, Plane plane, Job job) => 0;

  @override
  double boardPayPct(GameState state, String cityId, JobType type) => 0;

  @override
  int extraBoardSlots(GameState state, String cityId) => 0;
}
