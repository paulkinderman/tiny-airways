# Growth

The design doc's "Fleet", "World and airports" and "Progression" growth rules: buying planes and airports, hangar space, plane upgrades, airport levels, upgrade paths, region licenses and what each airline level unlocks. The rules are in `lib/logic/growth.dart`; the screens are the Hangar and Airports tabs plus additions to the airport panel, city card and top bar.

## Using it

Every action is a `Simulation` extension that runs the world to `now` first, like the core actions, and throws `RuleException` when refused. Screens call them through `GameSession.act`:

```dart
session.act((sim, s, now) => sim.buyPlane(s, 'hauler_h2', now));
session.act((sim, s, now) => sim.buyAirport(s, 'denver', now));
session.act((sim, s, now) => sim.upgradeAirport(s, 'chicago', now));
session.act((sim, s, now) => sim.buyPathTier(s, 'chicago', 'cargo', now));
session.act((sim, s, now) => sim.sellPathTier(s, 'chicago', 'cargo', now));
session.act((sim, s, now) => sim.buyLicense(s, 'europe', now));
session.act((sim, s, now) => sim.buyHangarExpansion(s, now));
session.act((sim, s, now) => sim.upgradePlane(s, 'p3', PlaneTrack.speed, now));
session.act((sim, s, now) => sim.renamePlane(s, 'p3', 'Blue Jay', now));
```

`sim.growth` (a `Growth`) answers the questions screens ask before acting: prices (`airportPrice`, `pathTierCost`, `airportUpgradeCost`, `planeUpgradeCost`, `hangarExpansionPrice`), why something can't happen yet (`buyPlaneProblem`, `buyAirportProblem`, `upgradeAirportProblem`, `buyTierProblem`, `licenseProblem`, each returning a `RuleError` or null), `hangarSlots`, `licensedRegions`, `nextLicense`, `freePoints`, `topPath`, `title` and `unlocksAt(level)`.

## Rules as built

| Rule | How it works |
| --- | --- |
| Hangar | Slots = `planes.hangar.startingSlots` (3) + level bonuses (+1 at 5, +1 at 10, +2 at 15) + expansions bought. Expansions cost 10,000, then 1.5x more each. |
| Buying planes | Fixed price from `planes.json`. A plane unlocks at the later of its own unlock level and its class level (Medium 5, Large 20). Special planes are not for sale. It is delivered parked, empty, at home, or the owned airport nearest home with a free gate that takes its class; with none, the purchase is refused. |
| Plane upgrades | Capacity (+1 seat, or +1 slot on cargo-only planes), speed +10%, range +15%, 3 levels each, costing 20% / 40% / 80% of the plane's price. They work mid-flight; a leg already flying keeps its times. Special planes can't be upgraded (they have no price). Renaming takes up to 16 characters; an empty name goes back to the model name. |
| Region licenses | The home region is licensed. Licenses go on sale in order (`progression.regionLicenses`): the 2nd at level 5 for 20,000, 3rd at 12, 4th at 15, then 30, 35 and 40. Each can be spent on any region. A region where the airline already owns an airport (the free starting airport can sit across a border) counts as licensed without using one up. |
| Buying airports | `base(size) x (1 + 0.1 x airports owned)`, only in licensed regions. It starts at level 1 with a full board (`JobBoards.fill`); other boards offer jobs there from their next rotation. The weather clock for a new region starts on the next tick. |
| Airport levels | The upgrade cost of the next level (`airports.levels`) x the city size multiplier. Airline level caps it: 3 from the start, 4 at level 10, 5 at level 20. The bigger board fills at once, and planes holding there for a gate land. |
| Upgrade paths | Points = the level's `upgradePoints` (1, 2, 3, 4, 6). Each tier costs a point plus 5,000 / 15,000 / 40,000 x the size multiplier, bought in order. Selling takes back the top tier of a path for 50%, freeing its point; jobs already on the board stay until they rotate. Board-slot tiers fill the new slots at once. |
| Map | Regions without a license are drawn locked. Each airport's top path (most tiers, first in config order on a tie) shows as a coloured badge: passenger blue, cargo orange, gateway green, transfer hub purple. |
| Levels | XP and levelling were already in `Economy.grantXp`. Reaching a level shows a card with what it unlocked (from `unlocksAt`, which reads `progression.json` and `planes.json`, so it stays right as numbers are tuned). The top bar shows the airline's title, and tapping the level opens the airline sheet: XP, hangar, the next three levels with unlocks, and network stats (money earned, jobs, km, airports, planes, busiest route). |

## Save schema

`PlayerState` gained `licenses` (regions bought, in order) and `hangarExpansions`. Older saves don't have them and read as none, which is what those airlines had, so the save version stays at 2.

## Design calls

- New planes go home (or the nearest airport that fits) rather than asking where; the toast says where it is waiting.
- Licenses are bought in order but for any region, as `regions.json` describes.
- Selling a tier always sells the highest tier on that path, so tiers stay in order.
- The level-up card lists features that later packages build (challenges, part crates, rivals) at their config unlock levels.
- The airline sheet doubles as the doc's "Stats and level" screen.
- Big balances shrink to fit in the top bar instead of pushing it off screen.

## Tests

`test/logic/growth_test.dart` covers every rule above and every row of the Progression unlock table. `test/app/growth_screens_test.dart` buys a plane, expands the hangar, upgrades and renames a plane, buys an airport from the shop and from a city card, buys a license, upgrades an airport and buys and sells a path tier, shows the level-up card and the airline sheet, and checks the tabs fit a 320-point-wide iPhone. `test/ui/map_scene_builder_test.dart` checks license locking and path badges.
