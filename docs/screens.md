# Core screens

The screens from the design doc's "Screens and UI" section that the core loop needs, in the departure-board style of the mockups (dark ground, amber flap text). They live in `lib/ui/`. The map is home; everything else is a sheet or panel over it.

| Screen | File | What it does |
| --- | --- | --- |
| Starting continent picker | `start_screen.dart` | Shown until the airline starts. Pick a continent (with its city count and start label from `regions.json`) and a home city (the three biggest, or any from "More…"), then `sim.startAirline`. |
| Top bar | `top_bar.dart` | Money, airline level with an XP bar, and the planes waiting at a gate. Tapping the count opens the next idle plane's airport, cycling through them. |
| Ready at gate | `fleet_board.dart` (`GatePanel`) | The map's bottom panel: parked planes with Load buttons, or when the next plane lands. |
| Departures board | `fleet_board.dart` (`FleetScreen`) | The Fleet tab: planes ready at a gate, then planes in the air, soonest first, with local ETA and status (en route, diverted, holding). Tapping a row jumps to the plane. |
| Airport panel | `airport_panel.dart` | Tap an owned airport. Gates in use, jobs, the next rotation countdown, weather over it, the planes parked there and the job board. "Load <plane>" opens the loading sheet. |
| Loading sheet | `loading_sheet.dart` | Seats and cargo slots, the board filtered by destination, paid refresh, "Fill to", charter and full-hold progress with "Make charter", and Choose route. Tap a job to add it, tap again to take it off. Long-press a job (or add one whose city is out of range) to drop it at another airport to connect. |
| Route picker | `route_picker.dart` | The map shows the range ring and reachable airports; tap them (or the chips) in order, up to 3 stops; tap the last stop again to take it off. Shows each leg, time, payout, fuel and profit, and why it can't depart. |
| Welcome back | `info_cards.dart` (`WelcomeBackDialog`) | After a minute or more away: money earned, jobs delivered or late, levels gained, diversions, new weather and planes waiting. |
| Plane, weather and city cards | `info_cards.dart` | Tap a plane in the air, a weather icon or a city you don't own. |

The Hangar and Airports tabs are placeholders for package 6. The Crew tab is package 7's (see [crew.md](crew.md)); it also added Autopilot to the route picker and the plane card.

## How it fits together

- **Game clock.** `HomeScreen` calls `GameSession.tick()` once a second, on launch and when the app comes back to the foreground. It runs `Simulation.advance` to now and saves only when something happened (a landing, a rotation, new weather). A gap of a minute or more with something to report posts the welcome-back summary, so launch and returning from the background use the same path.
- **Actions.** Screens call `GameSession.act((sim, state, now) => ...)`. It runs the action through the rules at the clock's time and saves, or returns the `RuleError` that refused it, which the screen shows with `ruleErrorText`.
- **Panels.** `uiProvider` holds the open tab and one `Panel` (airport, city, loading, route, plane, weather). It is not saved. Opening a panel moves the camera to what it is about.
- **Map adapter.** `buildMapScene` turns the game state and open panel into a `MapScene`: owned airports with waiting counts, flights with later stops, weather (airport, cluster or band), regions without an airport drawn locked, and the route picker. `sceneKey` fingerprints it so the map only gets a new scene (and rebuilds its caches) when something visible changed, not every tick.

## Design calls

- The waiting count opens the plane's airport panel rather than going straight to loading, so the player sees the board and where the plane is first.
- A route whose jobs all leave the plane at one reachable airport starts with that stop picked.
- Adding a job whose city is out of range asks where to drop it to connect, nearest to its destination first.
- Regions show as locked until the player owns an airport in them; package 6 replaces this with licenses.
- Flight numbers are "TA" plus 100 and the plane's number (p3 is TA 103).
- Fonts stay system fonts until package 8 bundles Rubik and JetBrains Mono.

## Tests

`test/app/app_test.dart` plays the core loop end to end in a widget test (start an airline, load with Make charter, choose the suggested route, depart, let the clock pass the landing and get paid), checks the welcome-back summary after two hours away, the departures board, and that the screens fit a 320-point-wide iPhone. `test/ui/` covers the map adapter and the formatting helpers.
