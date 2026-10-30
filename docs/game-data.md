# Game data

Every number and every piece of static content the game uses, and the design calls made while turning the design doc into data. Rules code reads these through the typed classes in `lib/core/config/`, never as raw JSON.

## Files

| File | Typed as | What it holds |
| --- | --- | --- |
| `assets/data/cities.json` | `WorldData.cities` | 152 real cities: id, name, country, region, lat/lon, size 1 to 5, metro population |
| `assets/data/rivals.json` | `RivalsConfig.roster` | 24 named rival airlines: region, personality, tier, hub city, livery colour |
| `assets/data/crew.json` | `CrewConfig.named`, `CrewConfig.rookieNames` | The 40 named crew (role, signature, favourite branch, home city, bio) and rookie first and last names per continent |
| `config/economy.json` | `EconomyConfig` | Starting money, plane and airports; pay rates per km |
| `config/regions.json` | `WorldData.regions` | The 7 continents, start labels, Antarctica's hard mode and outbound pay, cross-region bonus |
| `config/planes.json` | `PlanesConfig` | Plane classes (pilots, crew seats, XP factor, pilot price), the 12 hangar planes, 3 special planes, plane upgrades, hangar space |
| `config/airports.json` | `AirportsConfig` | Purchase prices, the 5 airport levels, the 4 upgrade paths, city-size cost scaling |
| `config/jobs.json` | `JobsConfig` | Board rotation and refresh, cargo share, destination weights, how long connecting jobs wait, charter and full-hold bonuses, special jobs, part crates, airline XP per coin |
| `config/flights.json` | `FlightsConfig` | Time compression and how a leg's real duration is worked out |
| `config/progression.json` | `ProgressionConfig` | Airline XP curve, plane class and airport level unlocks, region licenses, hangar bonuses, feature unlock levels, titles |
| `config/crew.json` | `CrewConfig` | Roles and base bonuses, skill trees, signatures, airport staff paths, crew XP, hiring prices |
| `config/weather.json` | `WeatherConfig` | Event frequency, forecast time, the 5 weather events |
| `config/rivals.json` | `RivalsConfig` | Personalities (and how each plays), tiers, difficulty settings, rival pace and reactions, city share, leader perks, hubs, terminals and the terminal tree, contracts, seasons |
| `config/extras.json` | `ExtrasConfig` | Plane parts, sightseeing tours, challenge rewards, the daily and weekly pools and the 60 milestones |

Keys starting with `_note` are comments and are ignored.

## Effects

Upgrade tiers, skill nodes, staff paths and terminal nodes all use one shape, `Effect`: `{"effect": "passengerPayPct", "value": 15, "text": "..."}`. The `effect` key is what rules code switches on; `...Pct` values are percentages and stack by adding. Skill node values are per node (a branch's values add up); airport staff tier values are the total at that tier.

## Design calls

These fill gaps in the design doc or change its first-draft numbers. Package 9's balance pass may tune any of them.

- **Plane ranges are double the doc's draft.** With about 150 real cities, most are 600 to 1,200 km from their nearest neighbour, so a 600 km Sparrow could not leave most home cities. Doubled, the Sparrow reaches 1,200 km and 85%+ of cities have a neighbour in range; remote ones (Honolulu, Perth, Reykjavik, the far Antarctic stations) need a bigger plane or a stop.
- **Flights run at 20x.** `flights.timeCompression` is 20, so a 900 km Sparrow leg takes about 10 real minutes and a 7,000 km Goose leg about 25. Rules that say "flights over 2 hours" mean scheduled hours (distance / speed), not real time.
- **Fuel** is 15% of a full plane's pay per km (Cloud Nine burns none; Mach One burns 3x).
- **Airport prices by size** are 1,000 / 1,800 / 3,000 / 6,000 / 25,000, which reproduces the airport shop mockup (size 4 at 9,000 with 5 airports owned). They moved from `economy.json` to `airports.json`. Upgrade, path and staff costs in the doc are for a size 3 city and scale by 0.5 / 0.75 / 1 / 1.5 / 2.5.
- **City size** comes from metro population: 10M+ is 5, 4M+ is 4, 1.5M+ is 3, 500k+ is 2, smaller is 1.
- **Region licenses** come in order, not per region: the 2nd continent at level 5 (20,000, as in the shop mockup), then levels 12, 15, 30, 35 and 40.
- **Airline XP** is 10% of payout, and level L to L+1 needs 100 x L^1.6.
- **Skill trees.** Each flight-crew role has 3 branches of 5 nodes (three small steps, one double step, a capstone) plus a 4-node signature: 19 nodes, as the doc says. The doc names each branch; the node values and the capstones other than Autopilot and Region expert's fog landing are new. Airport managers and station agents have no skill tree; their three branches are the money-bought staff paths.
- **Rivals.** 24 rivals, 2 to 4 per continent, each continent with at least a Puddle Jumper and a Wingman. Antarctica's two have no Jumbo, since hard mode shifts every rival up a tier anyway.
- **Antarctic stations** are size 1 with crew counts as population, and legs leaving Antarctica pay 3x. The South Pole station sits at latitude -90; map projections should clamp it.

## Left for later packages

- ~~The 40 named crew with bios and the rookie name lists~~: done in package 7 (see [crew.md](crew.md)).
- Season trophies and liveries (packages 8 and 11).

## Known balance gap

The doc's target that "a full plane earns its price back in 20 to 40 flights" doesn't hold with its own prices and rates: a full Sparrow on a 1,000 km leg earns about 980 after fuel, so it pays for itself in under 2 flights. Package 9 should raise plane prices or lower rates; this package keeps the doc's numbers.
