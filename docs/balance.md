# Balance (package 9)

The design doc's balance targets are checked by a bot player, `test/balance/bot.dart`, which `test/balance/balance_test.dart` runs on the shipped config in every CI run. The bot plays 30 in-game days as three 30-minute sessions a day (45 hours of play), with the game closed in between so the offline catch-up runs. While playing it checks the game once a minute, plans trips of up to three stops the way a player would (fill for the best stop, add stops while the trip makes more per hour), and spends on the biggest plane about three hours of income buys (plus the second pilot a Large plane needs), the pilot licenses and airport levels that plane needs, new airports and region licenses, and claims every finished challenge and milestone. It doesn't train crew, buy upgrade paths or build terminals, so a real player d## Targets and what the bot measured

| Target (design doc) | Check | Measured after tuning |
| --- | --- | --- |
| First new plane affordable within about 10 minutes | 15 minutes or less | 6 minutes |
| First airport upgrade within the first session | The cheapest upgrade costs less than the starting money plus 30 minutes of income | Yes (the free nearby airport, 1,000 to 2,500) |
| A full plane on a sensible route pays back in 20 to 40 flights | Every Small or Medium plane the bot flew 20+ times pays back in 10 to 60 flights (Large in 10 to 130, since they rarely fly full); the median is 15 to 45 | Sparrow 12, Puffin 17, Kestrel 16, Heron 23, Swift 27 to 30, Albatross 51, Goose 70 to 127 |
| Money never goes negative | Lowest balance is 0 or more and no action was refused | Yes |
| Income per hour of play: 1,000 at level 1, 5,000 at 5, 15,000 at 10, 60,000 at 20, 150,000 at 30 | Level 1 income in 1,000 to 4,000; level 10 after 5 to 20 hours of play; level 25 to 50 after 30 days | 3,500/h at level 1, 15,000/h at level 10 (8.5 hours, day 6), 41,000/h at level 20 (day 13), 77,000/h at level 30 (day 18), level 50 at day 30 |
| Crew payoff: a level 8 veteran (120,000) becomes the better deal around airline level 8 to 10, when saving for one takes less than the 15 hours a rookie needs to grow | Over 15 hours of income at level 5, under 15 by level 9 to 11 | About 60 hours at level 5, 8 hours at level 10 |
| A rival can win and lose a city in a simulated week; nothing the player owns is taken | The player leads 70% to 97% of the city-hours that have a leader, and leads change hands 10+ times | 89% on Cruising Altitude with 49 lead changes in the month (a separate run measured about 93% on Blimp Mode and 79% on Dogfight); the home city changes hands every few days |

## What changed from the package 2 to 11 numbers

| Number | Was | Now | Why |
| --- | --- | --- | --- |
| `economy.rates.passengerPerKm` | 0.35 | 0.10 | Income was about 8x the doc's level 1 target and planes paid back in 2 to 6 flights |
| `economy.rates.cargoPerKm` | 0.45 | 0.14 | The same |
| Every plane's `fuelPerKm` | | 15% of its full pay per km at the new rates | Keeps the doc's "fuel is about 15% of a full plane's payout" |
| `economy.startingMoney` | 2,500 | 3,000 | With the Sparrow at 3,200 the first new plane is a few minutes away, not free on day one |
| Sparrow, Hauler, Puffin, Kestrel | 1,500, 3,000, 4,200, 6,500 | 3,200, 6,000, 9,000, 12,000 | Small planes paid back in 2 flights |
| Heron, Mule, Swift | 45,000, 32,000, 70,000 | 30,000, 14,000, 42,000 | Medium planes rarely fly full (a board's jobs spread over many cities), so at the old prices they took 50 to 150 flights |
| Albatross, Condor, Goose | 140,000, 180,000, 320,000 | 90,000, 80,000, 120,000 | Large planes took 135 to 900 flights to pay back |
| Airport level 4 and 5 job boards | 16 and 22 jobs | 24 and 32 | Gives Large planes enough jobs to fill up |
| `airports.jobBoardScaleBySize` (new) | Same board at every city size | 0.6, 0.8, 1.0, 1.25, 1.5 times the level's board for city sizes 1 to 5 | Big cities felt as quiet as small towns; a level 1 board is now 4 jobs in a size 1 town and 9 in a size 5 city, and level 5 is 19 to 48 |
| `jobs.airlineXpPerCoin` | 0.1 | 0.16 | XP comes from pay, so lower pay needed more XP per coin to keep a steady level pace |
| `jobs.refreshCostPerCitySize` | 25 | 10 | A fresh board cost about two jobs' pay at the new rates |
| `extras.challenges.dailyMoneyPerLevel` | 500 | 150 | Rewards scale with level; at the old value one milestone paid 45,000 coins at level 9 |
| `extras.challenges.dailyXpFractionOfLevel` | 0.15 | 0.04 | Claiming a backlog of milestones chained level-ups (7 to 12 in one tap) |
| `extras.challenges.milestoneMultiplier` | 10 | 2 | The same |
| `rivals.share.perCoinDelivered` | 0.01 | 0.033 | Keeps the share a delivery earns about the same at the lower pay |
| `rivals.pace.sharePerHourPerLevel` | 3 | 9 | At 3 the player led over 95% of their cities all month and rivals never mattered |
| `rivals.contracts.prizePerCitySize` | 10,000 | 1,500 | A contract prize was worth several hours of income and jumped the airline 3 levels at once |
| Dogfight's `tierStrength` | 0.85 / 1.1 / 1.6 | 1.0 / 1.35 / 1.9 | Dogfight played the same as Cruising Altitude |

Everything else (airport prices and upgrades, path tiers, crew prices, hangar slots, weather) keeps its earlier value.

 tiers, crew prices, hangar slots, challenge rewards, weather) keeps its package 2 to 11 value.

## Bigger starting airline

A new airline starts with three small planes (Sparrow S1, Hauler H2 and a second Sparrow) and three free nearby airports instead of one of each. The first plane's range still picks the free airports (nearest in the home region first). The planes park at home until its gates are full, then at the free airports nearest first, and each comes with a rookie pilot.

| Number | Was | Now | Why |
| --- | --- | --- | --- |
| `economy.extraStartingPlanes` | (none) | Hauler H2, Sparrow S1 | Two more small planes from the start |
| `economy.freeNearbyAirports` | 1 | 3 | More cities to fly to from the start |
| `planes.hangar.startingSlots` | 3 | 4 | One free slot for the first purchase; 5 let the bot overbuy Large planes late on |

Airline XP per coin stays at 0.16: the steeper XP curve from the multiple-planes change (`progression.xpExponent` 1.65) already holds the bigger start in check. With both, the bot earns about 5,900/h at level 1 (the doc's 1,000/h assumed one plane), reaches level 10 after about 6.5 hours of play and ends the month at level 51. The balance test now allows level 1 income up to 7,000 and a final level up to 55.

## Rules tests and tuning

The rules tests in `test/logic` are written against exact numbers, so they load `testConfig()`, which pins `airports`, `economy`, `extras`, `jobs`, `planes` and `rivals` to the pre-tuning copies in `test/fixtures/rules_config/`. Retuning the shipped files only moves the balance test and the shipped-data checks in `test/core/config`; the rules tests keep passing. Re-run `flutter test test/balance` after any change to `assets/config`.

## Layovers

The Transfer hub path became Layovers: its three tiers add +2, +4 and +6 layover slots (the old +15% transfer pay, connection jobs and Codeshare are gone). Every airport now holds 2, 3, 4, 6 or 8 layover seats or slots by level. A job on a layover pays its normal full fare on final delivery, plus the station agent's and terminal's layover bonuses. The bot doesn't use layovers or buy paths, so the balance run is unchanged: about 5,900/h at level 1, level 10 after 6.5 hours of play, level 51 at the end of the month, and all seven checks pass.

## Pilot cap instead of hangar cap

The hangar no longer limits the fleet; pilots are capped instead (see [crew.md](crew.md#pilot-cap)). The bot buys a pilot license whenever its next plane's pilots wouldn't fit.

| Number | Was | Now | Why |
| --- | --- | --- | --- |
| `planes.hangar` | 4 slots, +4 from levels, expansions 10,000 x1.5 | Removed | Planes are a collection you can grow freely |
| `crew.hiring.startingPilotSlots` (new) | | 4 | The three starting planes' pilots plus one spare |
| `progression.pilotBonusSlots` (was `hangarBonusSlots`) | +1 at 5 and 10, +2 at 15 | +1 at 3, 5 and 7; +2 at 10, 15 and 20; +1 at 25, 30, 40 and 50 | Large planes (level 20) need two pilots; +2 late on let the bot overbuy Large planes |
| `crew.hiring.pilotLicenseBasePrice` / `pilotLicensePriceGrowth` (new) | | 10,000 / 2.0 | At 1.5 the bot bought 12 licenses and flooded the late game with Goose G10s |
| Goose G10 price | 110,000 | 100,000 | With more planes sharing Large jobs late on, the Goose took 125 to 145 flights to pay back (the check allows 130); now about 90 |

Measured: about 3,800/h at level 1, level 10 after 6.3 hours of play, level 52 at the end of the month with 18 planes and 24 pilots (7 licenses bought), and all seven checks pass.

## Cargo upgrades

Planes with both seats and a hold (Sparrow, Puffin, Kestrel, Pelican, Heron, Swift, Albatross, Goose) now have a fourth upgrade track, Cargo, that adds +1 hold slot a level next to the Seats track's +1 seat. Before, the only capacity upgrade on these planes added seats, so a seat could grow and a slot couldn't. Cargo-only planes keep taking slots on their capacity track, and passenger-only planes (Firefly) have no hold to grow. The cargo track uses the same three levels and the same 20% / 40% / 80% of the plane's price as the others, so a mixed plane can now add up to three seats and three slots.

The pay rates stay as they are. A slot already pays 0.14 a km against a seat's 0.10, which offsets cargo being 40% of every board, so a filled slot level is worth a little more than a seat level and an empty one less; which to buy depends on the routes you fly. The bot doesn't buy plane upgrades, so the balance run is unchanged.

## Job supply as the network grows

Before, every job picked a destination from all your airports by city size
alone, boards wiped every rotation, and board sizes ignored the network.
With 18 airports jobs spread so thin that a charter was almost never
possible: a fully upgraded Kestrel (7 seats) at a level 2 airport saw 5
passenger jobs a rotation, fewer than its seats.
`test/balance/job_supply_test.dart` measured 0% charters per rotation for
every fully upgraded plane on an 18-airport network.

Five rules now shape supply (all in `jobs.json` and `airports.json`):

- **Jobs build up.** Boards no longer wipe. Each rotation, jobs that have
  waited `jobLifetimeRotations` (3, so 15 minutes) leave and a batch of about
  a third of the board's size arrives, up to the board's size. Jobs to the
  same city pile up, so common routes show. A paid refresh (or a storm
  clearing) still swaps the whole board, giving the new jobs staggered
  timers so they don't all leave together. Jobs about to leave say "leaves
  soon" in the Load sheet.
- **Network growth.** Board size gains `networkJobsPerAirport` (0.5) jobs per
  airport beyond the first, before the city size scale. A level 2 board in a
  size 3 city holds 17 jobs at 18 airports instead of 9.
- **Hot destinations.** Each board picks 1 to 3 hot destinations (one per 5
  it can reach), weighted by size and closeness (`gravityKm`: a city that far
  away pulls half as hard). They get `hotShare` (60%) of new jobs and hold for
  `hotRotations` (2) rotations. A paid refresh keeps them.
- **Group bookings.** Passenger jobs can be groups of 2 to 4 seats that pay
  per seat. The chance is 2.5% per seat of the biggest passenger plane that
  can use the airport, capped at 35%, so groups follow the fleet.
- **Charter chance.** Each rotation (and paid refresh) has a 33% chance to top
  up one hot destination with enough jobs to fill a plane exactly, seats and
  hold: a plane parked there if any, else the fleet's biggest that fits.

The supply test parks a fully upgraded plane at Chicago, rolls 400
rotations, and flies every charter as soon as it is possible (taking those
jobs). Charter possible per rotation, 18 airports (old rules in brackets):
Sparrow 45% (0%), Kestrel 35% (0%), Pelican 41% (0%), Heron 32% (0%),
Albatross 41% (0%), Goose 33% (0%). Smaller networks run 38% to 57%.
