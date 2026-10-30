import '../core/config/game_config.dart';
import '../core/state/game_state.dart';
import '../logic/rules.dart';

/// 12500 -> "12,500".
String formatCoins(int coins) {
  final digits = coins.abs().toString();
  final buffer = StringBuffer(coins < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 1150.4 -> "1,150 km".
String formatKm(double km) => '${formatCoins(km.round())} km';

/// A countdown for map pills and panels: "45s", "4m 12s", "1h 40m".
String formatCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

/// A clock-style countdown for board rotations: "3:12".
String formatMinSec(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// A length of time away: "2h 14m", "6m", "1 day 3h".
String formatAway(Duration d) {
  if (d.inDays > 0) {
    final days = d.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ${d.inHours % 24}h';
  }
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

/// Local wall-clock time for the departures board: "16:42".
String formatClock(DateTime t) {
  final local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// What the player calls a plane: its nickname, or its model's name.
String planeName(GameConfig config, Plane plane) =>
    plane.nickname ?? config.planes.model(plane.modelId).name;

/// A departures-board flight number for a plane: "p3" -> "TA 103".
String flightNumber(Plane plane) {
  final n = int.tryParse(plane.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  return 'TA ${100 + n}';
}

String citySizeLabel(int size) => switch (size) {
  1 => 'Town',
  2 => 'Small city',
  3 => 'City',
  4 => 'Large city',
  _ => 'Mega city',
};

/// Why the rules refused something, in the player's words.
String ruleErrorText(RuleError error) => switch (error) {
  RuleError.notStarted => 'Start your airline first.',
  RuleError.alreadyStarted => 'Your airline has already started.',
  RuleError.unknownCity => 'That city is not on the map.',
  RuleError.unknownPlane => 'That plane is not in your fleet.',
  RuleError.unknownJob => 'That job is not on this plane.',
  RuleError.notOwned => 'You don\'t have an airport there yet.',
  RuleError.notEnoughMoney => 'Not enough coins.',
  RuleError.planeNotParked => 'The plane has already left.',
  RuleError.jobNotHere => 'That job has gone from the board.',
  RuleError.noRoom => 'No free seat or slot for that job.',
  RuleError.badDropCity => 'Jobs can only connect at another of your airports.',
  RuleError.noStops => 'Pick at least one stop.',
  RuleError.sameCity => 'The plane is already there.',
  RuleError.outOfRange => 'Out of range.',
  RuleError.planeTooBig => 'That airport is too small for this plane.',
  RuleError.airportClosed => 'A storm has closed the airport.',
  RuleError.heatWaveSeats =>
    'The heat wave took seats away. Unload a passenger first.',
  RuleError.crewMissing => 'This plane needs more crew.',
  RuleError.fragileNeedsLoadmaster => 'Fragile cargo needs a loadmaster.',
  RuleError.wrongPlaneForJob => 'This job needs a different plane.',
  RuleError.unknownCrew => 'That crew member is not on staff.',
  RuleError.offerTaken => 'Someone already took that job offer.',
  RuleError.wrongRole => 'They can\'t work there.',
  RuleError.noCrewSeat => 'No free crew seat on that plane.',
  RuleError.noStaffSlot => 'No free staff slot at that airport.',
  RuleError.crewBusy => 'Wait until the plane is parked.',
  RuleError.notAssigned => 'Assign them to an airport first.',
  RuleError.nodeLocked => 'Learn the skill above it first.',
  RuleError.noSkillPoints => 'No skill points to spend.',
  RuleError.maxTier => 'That path is maxed out.',
  RuleError.noAutopilot => 'The captain needs the Autopilot skill.',
};
