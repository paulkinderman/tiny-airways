/// The save schema version this build writes.
///
/// To change the schema:
/// 1. Bump [currentSaveVersion] (say from 1 to 2).
/// 2. Add an entry to [saveMigrations] keyed by the *old* version (1) that
///    turns a version 1 `state` map into a version 2 one.
/// 3. Add a test in `test/core/save/save_migrations_test.dart` that loads a
///    real version 1 save and checks it comes out right.
///
/// Never edit or remove an existing migration: players may still have saves
/// from any earlier version.
const int currentSaveVersion = 3;

/// Turns the `state` of a save at one version into the next version.
typedef SaveMigration = Map<String, dynamic> Function(
  Map<String, dynamic> state,
);

/// Migrations keyed by the version they upgrade *from*.
const Map<int, SaveMigration> saveMigrations = {1: _v1ToV2, 2: _v2ToV3};

/// Version 2 adds the simulation (package 3): airports, planes, job boards,
/// weather, stats, ids and the random seed. A version 1 airline had none of
/// these yet, so it comes back as not started, keeping its money and level.
Map<String, dynamic> _v1ToV2(Map<String, dynamic> state) {
  final lastSeenAt = state['lastSeenAt'] as String;
  return {
    ...state,
    'homeCityId': null,
    'airports': <dynamic>[],
    'planes': <dynamic>[],
    'weather': {'events': <dynamic>[], 'nextEventAt': <String, dynamic>{}},
    'stats': {
      'moneyEarned': 0,
      'fuelSpent': 0,
      'jobsDelivered': 0,
      'jobsLate': 0,
      'kmFlown': 0,
      'legsFlown': 0,
      'routeLegs': <String, dynamic>{},
    },
    'nextId': 1,
    'rngState':
        DateTime.parse(state['createdAt'] as String).millisecondsSinceEpoch &
        0xFFFFFFFF,
    'simulatedTo': lastSeenAt,
    'boardRotation': 0,
  };
}

/// Version 3 adds crew (package 7). Existing planes have no crew yet; the
/// rules give each one its free rookie pilot on the next tick.
Map<String, dynamic> _v2ToV3(Map<String, dynamic> state) => {
  ...state,
  'crew': {
    'members': <dynamic>[],
    'hiredOffers': <dynamic>[],
    'staffedPlaneIds': <dynamic>[],
    'autopilot': <String, dynamic>{},
  },
};
