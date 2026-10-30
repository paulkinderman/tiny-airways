# Core simulation

The game rules from the design doc's "Jobs, loading and flights", "Weather", "Economy" and "Time, offline play and saving" sections, as pure Dart in `lib/logic/`. Nothing here imports Flutter, and nothing reads the real clock: every call takes the time it happens at.

## Using it

Screens talk to one class, `Simulation` (`lib/logic/simulation.dart`), built from a `Rules`:

```dart
final sim = Simulation(Rules(config));            // package 7 passes crew: ...
state = sim.startAirline(state, 'chicago', now);  // after the continent picker
final (next, report) = sim.advance(state, now);   // every tick, and on launch
state = sim.loadJob(state, planeId, jobId, now, dropAtCityId: 'toronto');
state = sim.fillTo(state, planeId, 'new_york', now);
final quote = sim.quote(state, planeId, ['toronto', 'montreal'], now);
state = sim.depart(state, planeId, ['toronto', 'montreal'], now);
state = sim.refreshBoard(state, cityId, now);
```

- Every action runs the world up to `now` first, then acts. Refused actions throw `RuleException` with a `RuleError` and change nothing.
- `quote` never throws: the route picker shows its legs (time, fuel), `expectedPayout` and `problems`. `flights.reachable` lists the airports a plane can fly to in one leg; `loading.summary` gives the loading sheet's seat counts and charter progress ("4 of 6 seats to Toronto").
- `advance` is both the live tick and the offline catch-up. Its `SimReport` is the welcome-back summary: money earned, jobs delivered, planes that landed, diversions and new weather.

## Save schema (version 2)

`GameState` now holds the home city, owned airports (level, path tiers, job board), planes (status, current leg, remaining stops, load), weather (events and each continent's next event time), network stats, an id counter, the random number generator's state, `simulatedTo` and the last board rotation. A version 1 save comes back as a not-yet-started airline with its money and level.

## Rules as built

| Rule | How it works |
| --- | --- |
| Money | Never negative: anything that costs money is refused if the player can't pay. Fuel for the whole trip is charged at departure. |
| Airline XP | Each delivery gives 10% of its pay as airline XP, and levels up along `progression.xpToNext`. Unlock screens are package 6. |
| Job boards | Board size from the airport level, 40% cargo, plus Passenger and Cargo path slots. Destinations are owned airports at least 150 km away, weighted by city size. |
| Payout | Rate per km x distance x special-job multiplier x Antarctica's outbound multiplier x (1 + bonuses). Bonuses fixed when the job appears: origin Passenger/Cargo path, cross-region +20%, Long-haul +25%, connection job +30%, weather. Added on delivery: transfer hub bonus, charter or full hold, crew. |
| Rotation | Boards rotate together on fixed 5-minute marks. Jobs on a plane or waiting to connect stay. After time away, boards rotate once, as of the latest mark. |
| Paid refresh | 25 x city size; swaps every job not loaded or connecting. |
| Loading | A job takes one seat or slot (bulk crates take 2). Fragile jobs need a loadmaster aboard. A job can be marked to drop at another owned airport to connect. Unloading puts it back on the board; a job from elsewhere then waits to connect. |
| Charter and full hold | Checked at each takeoff: every seat filled with passengers for one city gives them +25%; every cargo slot filled for one city gives the crates +15%. |
| Routes | Each leg must end at an owned, open airport within range (Gateway tier 2 adds 15% from that airport) that allows the plane's class. Real time = distance / speed / 20, at least 30 seconds. |
| Multi-stop trips | The plane lands at each stop, delivers jobs bound there, drops connecting jobs, and flies straight on. Loading happens before the trip starts. Jobs bound elsewhere stay aboard. |
| Transfers | A dropped job waits on that board, survives rotations and paid refreshes, and picks up the Transfer hub tier 1 bonus. It is dropped after 4 hours (`jobs.connectionExpiryMinutes`) unless the airport has Codeshare, which also gives 10 airline XP per transfer. |
| Gates | Parked planes take gates. A plane arriving at a full airport (including a mid-trip stop) holds until one opens, longest wait first. |
| Special jobs | From level 7: VIP (3x, lands within 2 hours or pays nothing), fragile (2x) and rush (1.5x, gone when the next plane leaves without it). A VIP lounge brings VIP jobs at 5x the chance at any level; a freight yard brings bulk crates. |
| Weather | Each continent with an owned airport gets an event every 30 to 60 minutes, rolled and shown 10 minutes before it starts. Events land on owned airports (or a band of latitude through one). |
| Thunderstorm | No landings or departures, and routes there are refused. Planes arriving divert to the nearest owned airport within range of the storm, jobs aboard; with nowhere to go they hold. When it clears, the board refills with jobs paying +50% for 15 minutes. |
| Fog | Only captains of level 4+ (or crew with the fog capstone) land; others divert or hold. Jobs appearing there pay +25%. |
| Snowstorm, heat wave | Cover every city within 800 km. Snow: departures burn 25% more fuel, jobs pay +25%. Heat: Large planes carry 2 fewer passengers, cargo jobs pay +20%. |
| Jet stream | A 12-degree band of latitude, east or west. A leg with both ends in the band and one on that continent burns 20% less fuel with it and 20% more against it. The airship ignores it. |
| Offline | `advance` replays landings, diversions, holding, weather and rotations in time order. Landed planes wait; nothing re-dispatches them. |
| Clock safety | `simulatedTo` never moves back. If the clock is set back, flights hold and actions happen at the last known time until it catches up. Big jumps forward are fine. |
| Randomness | One seeded generator whose state is saved, so the same save and the same times always give the same boards and weather. |

## Design calls

These fill gaps in the doc; package 9's balance pass may change any of them.

- Diversion legs burn no fuel: the player didn't choose them.
- Jobs not bound for the landing city stay aboard, so a diverted plane keeps its load and the player re-routes it.
- Connecting jobs expire after 4 hours, so the doc's Codeshare tier ("jobs waiting here never expire") means something.
- Connection jobs (Transfer tier 2) double the weight of destinations beyond the fleet's longest range; Long-haul (Gateway tier 3) multiplies cross-region destinations by `airports.longHaulJobWeight`.
- Weather only lands on cities with an owned airport, so every event matters to the player.

## Hooks for later packages

- **Crew (7):** implement `CrewEffects` (`lib/logic/crew_effects.dart`) and pass it to `Rules`. Until then `NoCrew` acts as one level 1 rookie pilot per plane.
- **Growth (6):** buying airports, planes, upgrades and path tiers. A new airport needs `JobBoards.fill` for its first board; `Economy.spend` refuses what the player can't afford.
- **Extras (10):** sightseeing jobs and part crates (the `JobKind` values exist; they are not rolled yet).
- **Rivals (11):** built, see [rivals.md](rivals.md). Deliveries call `Rivals.playerDelivered` from `Flights._land`; leader and terminal pay go through `Flights.deliveryPay`; hub and terminal board slots through `JobBoards.boardSize`.
