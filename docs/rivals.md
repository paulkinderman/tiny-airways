# Rival airlines

The design doc's "Rival airlines" section (package 11): about 24 CPU airlines, city share and leader perks, hubs and terminals with terminal trees, contracts with a top-bar tracker, the season leaderboard, difficulty settings and rival tiers. The rules are pure Dart in `lib/logic/rivals.dart`; the screens are in `lib/ui/rivals_screens.dart`.

## Using it

`Simulation.rivals` is a `Rivals` built from the same `Rules`. The world clock drives it: `Simulation.advance` runs a rival step on every 5-minute mark (`rivals.pace.stepMinutes`), in time order with landings, weather and board rotations. Player actions:

```dart
state = sim.setDifficulty(state, 'dogfight', now);         // any time, also on the start screen
state = sim.buildTerminal(state, 'chicago', now);          // at a hub, or lease a taken-over terminal
state = sim.learnTerminalNode(state, 'chicago', 'gates', now);
```

Screens go through `GameSession.act` as usual. Read-only questions (`leaderOf`, `isHub`, `standings`, `targets`, `flights`, `terminalProblem` and so on) are plain methods on `Rivals`.

## Save schema

`GameState.rivals` (`lib/core/state/rivals_state.dart`) holds only what can't be worked out again: the difficulty, each city's share points and the player's lead and hub clocks, the player's terminals (jobs counted, nodes learned), rival terminals the player took over, heated rivals, contracts, the season (number, start, wins, history) and the last rival step. A save without the field loads as an empty `RivalsState`, so this needs no migration or version bump.

Rival levels, fleets, planes, targets and the planes on the map are all worked out from the config, the player's level and the share meters each time they are needed.

## Rules as built

| Rule | How it works |
| --- | --- |
| Roster | 24 rivals from `data/rivals.json`. Rivals compete only on continents where the player has an airport; elsewhere they don't fly or score. |
| Strength | A rival's level is the player's level x its tier strength for the difficulty (`difficulties[].tierStrength`), so it rubber-bands with the player. Starting in Antarctica moves every rival up a tier. |
| Personalities | Budget: many small planes, short hops (1,500 km), big cities. Luxury: few planes, long range, the biggest cities. Freight: cargo-only planes, weights cities by the player's Cargo path tiers. Regional: stays within 900 km and weights its hub 5x. Numbers in `rivals.personalities`. |
| Planes | The best plane in the player's own roster a rival's level unlocks, in its personality's classes (cargo-only for Freight). Rival legs never exceed that plane's range. |
| Fleet | (`fleetBase` + `fleetPerLevel` x level) x personality fleet, up to `maxFleet`. |
| Unlocks | Rival planes fly from the start. City share and leader perks from airline level 5, contracts from 7, terminals and the season leaderboard from 10 (`progression.featureUnlockLevel`). |
| City share | A player delivery adds `perCoinDelivered` points per coin paid to the city it lands in, +10% per path tier the player owns there, + Fortress nodes, x1.5 for the terminal holder. Rivals deliver ghost jobs: `sharePerHourPerLevel` x level x personality effort points an hour, split over their hub (and fortified cities) and targets by weight. Every airline's points decay 2% an hour (half that for the city's terminal holder). |
| Leader | Most points, with at least `minPointsToLead`; ties go to the player. The leader's flag flies on the city pin. |
| Leader perks | +10% pay on jobs delivered there. First look: while a rival leads a city, new jobs on the player's board there stay hidden (and can't be loaded) for their first minute. |
| Rival reactions | Cities where the player has 75%+ share get a quarter of the effort ("abandoned"); contested cities (the player within 80% of the best rival) get double; a rival whose hub the player holds 30%+ of doubles its hub. Dogfight's `reactionSpeedMultiplier` 2 makes both boosts triple. |
| Hub | 50% share held for 3 days in a row (the clock restarts if it drops below): +1 job board slot and the right to build a terminal. |
| Terminals | Build at a hub for 50,000 x city size. 1 at airline level 10, +1 every 5 levels. Once built it is the player's for good: rivals leading the city only pause the leader perks. |
| Terminal tree | 1 point per 40 jobs delivered to or from the city, up to 10. Three branches of 4 nodes, learned top down. Lounges: +5% passenger pay x3 (jobs to or from the city), then a VIP job on the board after every rotation. Gates: +1 board slot, refresh -50%, transfers +10%, then 2 exclusive board slots. Fortress: +15% share x3, then rivals gain share here 50% slower. |
| Rival terminals | Each rival holds a terminal at its hub; a Jumbo also holds the next biggest cities in its region (3 in all). Leading a rival terminal city for 7 days in a row takes it over: the rival turns heated and the terminal is up for lease at half the build cost, with a fresh tree. |
| Mood | A rival is heated after losing a terminal, and while the player leads its hub; otherwise "friendly rivalry". |
| Contracts | From level 7, every 3 hours (0.05 h sooner per level past 7, never under 1 hour) in one of the player's airport cities, weighted by size; heated rivals pick the player's hubs and terminals. 1 or 2 rivals from that continent race (heated ones first). First to 15 deliveries to the city within 3 hours wins 10,000 x city size and a share burst of 10% of the city's points. Rivals score `rivalJobsPerHour` x strength jobs an hour. Losing costs nothing. |
| Seasons | Two weeks. Each continent's board ranks the player and its rivals by cities led, then contracts won (the player wins ties). At the end, each continent with a player airport records the player's rank, the difficulty and a trophy for every rival finished below; then everyone's wins reset. Nothing else of the player's changes. |
| Difficulty | Blimp Mode (rivals weaker, gain share 1.5x slower), Cruising Altitude, Dogfight (stronger, react twice as hard). Picked on the start screen, changeable on the leaderboard screen. |
| Offline | A run of the clock longer than 2 minutes (`offlineAfterSeconds`) is the game catching up after being closed, and rivals gain share and contract progress at half pace. More than 2,000 pending steps are taken in coarser steps so a long break catches up quickly. |
| Map | Rival planes are worked out from the clock: each plane shuttles between its hub and its targets in fixed slots, so nothing about them is saved and every device shows the same sky. Up to 40 on the map. Tapping one opens its airline card. |

## Screens

| Screen | File | What it does |
| --- | --- | --- |
| City share line | `rivals_screens.dart` (`CityShareLine`) | On the airport panel and city card: who leads, with the way into the rivalry screen. |
| City rivalry | `RivalryScreen` | Share bars, road to hub (or the takeover clock on a rival terminal), leader perks, the live contract, Terminal and Season buttons. |
| Hub terminal | `TerminalScreen` | Build or lease, then the next-point progress, points to spend, the three branches (tap the open node to learn it) and the holder bonus. |
| Season leaderboard | `LeaderboardScreen` | Continent chips, the season countdown, ranks with tier badges and titles, "Pass X", trophies, and the difficulty picker. |
| Airline card | `RivalCard` | Tap a rival plane: personality, tier, title, hub, fleet, cities led, mood. |
| Contract tracker | `ContractChip` | On the top bar during a contract: your score against the best rival's. Tap for the contract city's rivalry screen. |
| Difficulty | `DifficultyPicker` | On the start screen and the leaderboard. |

## Design calls

These fill gaps in the doc; package 9's balance pass may change any of them.

- First look is the rival's minute: the player can't see a rival-led city's new jobs for 60 seconds, rather than the player getting a preview of the next rotation.
- Rivals only compete where the player has an airport, so a new continent starts with rivals building up from nothing.
- Hub status lasts while the player holds 50%; dropping below restarts the 3-day clock. A built terminal is never lost.
- Exclusive gates are 2 extra board slots (in a single-player game, every job on the board is only the player's).
- Contracts last 3 hours, as long as the gap between them, so there is usually one running.
- Season liveries are recorded as trophies; package 8's livery work can turn them into paint.
- Share and contract scores don't feed the welcome-back summary yet.

## Tests

`test/logic/rivals_test.dart` covers every rule above, including the package's "done when": over a simulated week a rival takes a city the player stopped serving and the player wins it back, while the player's airports, planes and money are never touched. `test/app/rivals_screens_test.dart` drives each screen, building a terminal and learning a node, changing difficulty, the contract tracker, a relaunch after a day away, and the 320-point-wide iPhone.
