# Architecture

Tiny Airways is a Flutter app with a Flame game for the world map. The game rules live in a pure Dart layer that knows nothing about the screen, so they can be unit tested and shared with Android unchanged.

## Folder layout

| Folder | What lives there | May import Flutter? |
| --- | --- | --- |
| `lib/core/` | Services every system needs: the clock, the config loader, the save system, and the saved `GameState` | No |
| `lib/logic/` | Game rules (package 3 onward): economy, job boards, loading, flights, weather, offline catch-up, crew, rivals | No |
| `lib/game/` | The Flame game that draws the world map, planes and weather (package 4) | Yes |
| `lib/ui/` | Flutter screens, sheets and widgets over the map (package 5 onward) | Yes |
| `lib/app/` | Startup (`bootstrap.dart`), app widget, Riverpod providers, Flutter-only adapters such as `AssetConfigSource` | Yes |
| `assets/config/` | Every tunable number, as JSON | |
| `assets/data/` | Static game data: cities and the rival roster | |
| `test/` | Mirrors `lib/`; `test/fixtures/` holds sample saves and configs | |
| `integration_test/` | Tests that launch the real app on a simulator | |

`test/architecture_test.dart` fails the build if `lib/core` or `lib/logic` imports Flutter, Flame or Riverpod, or calls `DateTime.now()`.

## Rules for every package

- **Time comes from the `Clock`.** Never call `DateTime.now()` in game code. Take a `Clock` (`lib/core/clock/clock.dart`) and use `clock.now()`, which is always UTC. Tests use `FakeClock` and move time with `advance()`.
- **Numbers live in config.** Prices, rates, plane stats and unlock levels go in `assets/config/*.json`, never in Dart code.
- **State changes go through `GameSession.update`.** It applies the change and auto-saves, which is how the game saves after every action. The app also saves when it goes to the background.
- **Rules are pure functions over `GameState`.** Screens read state through Riverpod (`gameSessionProvider`) and call into `lib/logic`.

## State management

Riverpod (`flutter_riverpod`). Services are created once in `bootstrap()` and injected with provider overrides:

- `clockProvider`: the `Clock`
- `gameConfigProvider`: the typed `GameConfig`
- `saveRepositoryProvider`: the `SaveRepository`
- `gameSessionProvider`: the live `GameState`, with `update()` and `persist()`

Tests build the app the same way, passing a `FakeClock`, `MemorySaveStorage` and a config source.

## Config

`ConfigLoader` reads every file named in `GameConfig.files` (from `assets/config/`) and `GameConfig.dataFiles` (from `assets/data/`) through a `ConfigSource`, and builds typed config classes with `ConfigReader`. A source serves paths under `assets/` without `.json`, such as `config/economy`: the asset bundle in the app, `DirectoryConfigSource('assets')` or a `MemoryConfigSource` in tests.

A missing or mistyped field throws a `ConfigException` naming the exact path, such as `economy.rates.cargoPerKm is missing` or `data/cities.cities[3].size should be 1 to 5`. After every file parses, `GameConfig` checks them against each other (ids are unique, every referenced plane, city, region, role and tier exists, tables are sorted), so bad data fails at startup and in CI.

What lives where is listed in [game-data.md](game-data.md).

To add a config file:

1. Add `assets/config/<name>.json`.
2. Add `<name>` to `GameConfig.files`.
3. Write a typed class with a `fromConfig(ConfigReader)` factory and add it to `GameConfig`. Put range checks in the factory (`c.check(...)`) and cross-file checks in `GameConfig._crossCheck`.
4. `test/core/config/game_data_test.dart` loads every shipped file; add tests for the new class's own checks there. `loadEdited` in `config_test_helpers.dart` loads the shipped files with one field changed.

## Saving

One save slot, one JSON document:

```json
{"version": 1, "savedAt": "2026-10-30T20:00:00.000Z", "state": { ... }}
```

- `FileSaveStorage` keeps `save.json` and `save.backup.json` in the app support folder. Each write goes to a temp file and is renamed into place, and the previous save becomes the backup.
- If `save.json` can't be read, the backup loads. If neither can, both are renamed to `*.unreadable-N.json` (never deleted) and a new game starts.
- A save from a newer build is refused rather than overwritten.

To change the save schema:

1. Change `GameState` (and its `toJson`/`fromJson`).
2. Bump `currentSaveVersion` in `lib/core/save/save_migrations.dart`.
3. Add a migration keyed by the old version that turns an old `state` map into the new shape.
4. Add a fixture `test/fixtures/saves/v<new>.json` and keep every older fixture. `save_migrations_test.dart` checks each one still loads.

iCloud sync (package 10) will sit behind the same `SaveStorage` interface.

## Packages

The build is split into 11 packages (see the design doc's build plan). Package 1 is the foundation; package 2 added the game data.
