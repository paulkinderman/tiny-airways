import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import 'crew_effects.dart';

export 'crew_effects.dart';

/// Why an action was refused. Screens use these to grey out buttons and
/// explain why.
enum RuleError {
  notStarted,
  alreadyStarted,
  unknownCity,
  unknownPlane,
  unknownJob,
  notOwned,
  notEnoughMoney,
  planeNotParked,
  jobNotHere,
  noRoom,
  badDropCity,
  noStops,
  sameCity,
  outOfRange,
  planeTooBig,
  airportClosed,
  heatWaveSeats,
  crewMissing,
  fragileNeedsLoadmaster,
  wrongPlaneForJob,
  alreadyOwned,
  levelTooLow,
  hangarFull,
  noGate,
  maxLevel,
  noUpgradePoints,
  regionLocked,
  notForSale,
  nothingToSell,
  noLicenseLeft,
  alreadyBuilt,
  missingParts,
  noFreeGate,
  noSparePart,
  unknownChallenge,
  challengeNotDone,
  challengeDone,
  noRerollsLeft,
  alreadyClaimed,
  unknownCrew,
  offerTaken,
  wrongRole,
  noCrewSeat,
  noStaffSlot,
  crewBusy,
  notAssigned,
  nodeLocked,
  noSkillPoints,
  maxTier,
  noAutopilot,
}

/// Thrown by an action the rules don't allow. Nothing changes when it is
/// thrown.
class RuleException implements Exception {
  RuleException(this.error, [this.detail]);

  final RuleError error;
  final String? detail;

  @override
  String toString() =>
      'RuleException(${error.name}${detail == null ? '' : ': $detail'})';
}

/// What every rule needs: the config, and the crew bonuses (package 7 plugs
/// in its own [CrewEffects]).
class Rules {
  const Rules(this.config, {this.crew = const NoCrew()});

  final GameConfig config;
  final CrewEffects crew;

  WorldData get world => config.world;

  double distanceKm(String fromCityId, String toCityId) =>
      WorldData.distanceKm(world.city(fromCityId), world.city(toCityId));

  bool crossesRegions(String a, String b) =>
      world.city(a).regionId != world.city(b).regionId;

  /// Sum of an effect's values over the path tiers bought at [airport].
  double pathEffect(AirportState? airport, String effect) {
    if (airport == null) return 0;
    var total = 0.0;
    for (final path in config.airports.paths) {
      final tiers = airport.tier(path.id);
      for (var i = 0; i < tiers && i < path.tiers.length; i++) {
        if (path.tiers[i].effect == effect) total += path.tiers[i].value;
      }
    }
    return total;
  }

  bool hasPathEffect(AirportState? airport, String effect) =>
      pathEffect(airport, effect) != 0;
}

/// Throws [RuleException] with [error] unless [ok].
void require(bool ok, RuleError error, [String? detail]) {
  if (!ok) throw RuleException(error, detail);
}
