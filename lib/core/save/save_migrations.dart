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
const int currentSaveVersion = 1;

/// Turns the `state` of a save at one version into the next version.
typedef SaveMigration = Map<String, dynamic> Function(
  Map<String, dynamic> state,
);

/// Migrations keyed by the version they upgrade *from*.
const Map<int, SaveMigration> saveMigrations = {};
