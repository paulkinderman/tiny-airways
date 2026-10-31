# Extras

The design doc's "Extras" section: plane parts and the special planes they build, sightseeing tours, daily and weekly challenges, milestones, and iCloud save sync. Rules are in `lib/logic/extras.dart` (`Parts`, `Challenges`), sync is in `lib/core/save/cloud_sync.dart`, and the numbers and pools are in `assets/config/extras.json`.

## Using it

Everything goes through `Simulation`, like the other actions:

```dart
session.act((sim, s, now) => sim.claimDaily(s, 0, now));
session.act((sim, s, now) => sim.rerollDaily(s, 2, now));
session.act((sim, s, now) => sim.claimWeekly(s, now));
session.act((sim, s, now) => sim.claimMilestone(s, 'first_terminal', now));
session.act((sim, s, now) => sim.buildSpecialPlane(s, 'barnstormer', now));
session.act((sim, s, now) => sim.sellSparePart(s, 'mach_one.tail', now));
```

`sim.advance` rolls the challenge board at local midnight and on Mondays (`Simulation.utcOffset` is the device's time zone, from `utcOffsetProvider`). `sim.challenges.claimable(state)` is the count on the top bar's trophy; `sim.challenges.progress(state, milestone)` gives milestone progress.

## Save schema

`GameState.extras` (`ExtrasState`) holds parts held, special planes built, lifetime metric counters, the dailies and weekly on the board, the day and week they were rolled for, rerolls left, claimed milestones, unlocks (badges, liveries, veterans), crew XP waiting for package 7, and the last 30 claims. A save without the key loads as an empty `ExtrasState`, so the save version stays at 2.

## Rules as built

| Rule | How it works |
| --- | --- |
| Part crates | From level 10 (`partCrates`), a cargo job is a crate with chance 1 / `jobs.partCrateOneIn` (40). It pays nothing and takes one slot. Which part is inside is settled on delivery, from the crate's id. |
| Parts | Each special plane has its own engine, wings, fuselage and tail (12 parts). A crate holds a part the player is missing 60% of the time (`parts.newPartChancePct`), otherwise any of the 12. |
| Building | A full set of one plane's parts builds it, once. It parks at home if a gate is free there, else at the first owned airport with a free gate that takes its class. It doesn't need hangar space. |
| Spares | Parts beyond the one a build needs, and any part of a plane already built, sell for 2,500 each. |
| Special planes | Barnstormer flies sightseeing tours. Mach One burns 3x fuel (in its `fuelPerKm`). Cloud Nine burns none and ignores the jet stream. |
| Sightseeing | While the fleet has a Barnstormer, each passenger job rolled has a 10% chance of being a tour: from an airport back to it, paying like a 500 km passenger job x 3 (`extras.sightseeing.tourKm`, `jobs.special.sightseeing`). Only the Barnstormer loads them, they can't connect, and they pay when the plane lands back where they started, so a tour is any trip that goes out and comes home. |
| Dailies | 3 on the board from level 3. Each pays 4% of the current level's XP bar and 150 coins per level (package 9's balance pass; it was 15% and 500), fixed when rolled. Claiming one rolls a different one in its place. 1 free reroll a day for an unfinished one. At midnight unfinished dailies reroll; finished, unclaimed ones stay. |
| Weekly | 1, rolled each Monday, paying 5 dailies. Its bonus is a part crate from level 10, or 500 crew XP for the whole roster before that (kept in `ExtrasState.pendingCrewXp` until crew arrives). A finished weekly left unclaimed pays itself when the week ends. |
| Targets | `target + targetPerLevel x level`, rounded to two significant figures above 20 ("Deliver 19 cargo jobs" at level 11, "Fly 14,000 km"). |
| Eligibility | A challenge can ask for a feature (`requiresFeature`), a plane in the fleet (`requiresPlane`) or airports on several continents. |
| Milestones | 60, tracked from level 1, claimed once, paying 10 dailies at the current level plus any `unlock`. |
| Never failed | Nothing costs money and nothing expires unpaid. |

## Metrics

Counted (added up as they happen, for challenges on the board and the lifetime counters):

| Metric | Counted when |
| --- | --- |
| `landings`, `kmFlown` | A plane lands (including mid-trip stops and diversions) |
| `jobsDelivered`, `passengersDelivered`, `cargoDelivered` | Jobs delivered on time |
| `moneyEarned` | Coins paid for deliveries |
| `crossRegionDeliveries`, `specialDeliveries` (VIP, fragile, rush), `vipDeliveries`, `sightseeingTours` | Those jobs delivered on time |
| `connections` | A job is dropped at an airport to connect |
| `multiStopTrips` | A plane parks at the end of a trip with 2+ stops |
| `badWeatherLandings` | A landing under fog or snow (`challenges.badWeather`) |
| `charters`, `fullHolds` | The player departs with every seat (or slot) bound for one city |
| `partsCollected`, `dailiesClaimed`, `weekliesClaimed` | As named |
| `terminalsBuilt`, `terminalsTakenFromJumbos`, `contractsWon` | Recorded by rivals (package 11) |

Best-of: `bestLandingPay` (coins from one landing) and `topCrewLevel` (recorded by crew, package 7).

Read from the state: `airlineLevel`, `airportsOwned`, `continentsOwned`, `topAirportLevel`, `planesOwned`, `specialPlanesBuilt`.

Config load fails if a challenge or milestone names a metric not on these lists.

## Hooks for other packages

- **Crew (7):** call `Challenges(rules).record(state, 'topCrewLevel', level)` when a crew member levels up; hand out `extras.pendingCrewXp` and zero it; a built special plane comes with no crew, so give it the free rookie pilot. A `veteran` unlock is a named veteran for the hire shelf.
- **Rivals (11):** record `terminalsBuilt`, `terminalsTakenFromJumbos` and `contractsWon`; add "Win 2 contracts" and "Take the lead in 3 new cities" to the weekly pool with `"requiresFeature": "contracts"` once they can be counted.
- **Art (8):** `livery:<name>` and `badge:<name>` unlocks in `extras.unlocks`; the gear glyph on part crates and the trophy in the top bar.
- **Autopilot (7):** must skip `JobKind.partCrate` and every special kind when it auto-loads.

## iCloud sync

The cloud copy is the save document itself (gzipped, base64) in iCloud's key-value store under `save`, through the `tiny_airways/icloud` method channel in `ios/Runner/AppDelegate.swift`. It needs the iCloud key-value entitlement in `ios/Runner/Runner.entitlements`; without an iCloud account the game just saves locally.

`CloudSync` keeps a marker (`sync.json` next to the save) with the `savedAt` of the last document this device and iCloud agreed on. It checks at launch (in `bootstrap`, before the game starts) and whenever the app returns to the foreground:

| Cloud since last sync | This device since last sync | Result |
| --- | --- | --- |
| Unchanged | Any | Keep playing here; saves go up |
| Changed | Unchanged, or no airline yet | Switch to the cloud airline without asking |
| Changed | Changed | The picker: both airlines side by side (home, money, level, planes, airports, last played); the player keeps one, and it goes up |

Saves go up at most every 30 seconds while playing and always when the app goes to the background. Nothing goes up until a check has read iCloud, so a fresh install can't overwrite an airline. A cloud save from a newer build is never overwritten. Android will plug Google Play saved games into the same `CloudSaveStore` interface.

## Design calls

- Parts belong to one plane each, so the collection has 12 to find and duplicates are a real thing to sell.
- The daily "Complete a 4-leg trip with a transfer" became "Connect 4 jobs through another airport", since the route picker allows 3 stops.
- The challenge board opens from the level and XP bar in the top bar, with a trophy and the count to claim; the mockup's Active, Milestones and Done tabs gained a Parts tab for the collection.
- Days roll at the device's local midnight; weeks start on Monday.
- Rival and terminal milestones are listed but only move once package 11 records them.
