# Balance (package 9)

The design doc's balance targets are checked by a bot player, `test/balance/bot.dart`, which `test/balance/balance_test.dart` runs on the shipped config in every CI run. The bot plays 30 in-game days as three 30-minute sessions a day (45 hours of play), with the game closed in between so the offline catch-up runs. While playing it checks the game once a minute, plans trips of up to three stops the way a player would (fill for the best stop, add stops while the trip makes more per hour), and spends on the biggest plane about three hours of income buys (plus the second pilot a Large plane needs), the hangar slots and airport levels that plane needs, new airports and region licenses, and claims every finished challenge and milestone. It doesn't train crew, buy upgrade paths or build terminals, so a real player d## Targets and what the bot measured

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

## Rules tests and tuning

The rules tests in `test/logic` are written against exact numbers, so they load `testConfig()`, which pins `airports`, `economy`, `extras`, `jobs`, `planes` and `rivals` to the pre-tuning copies in `test/fixtures/rules_config/`. Retuning the shipped files only moves the balance test and the shipped-data checks in `test/core/config`; the rules tests keep passing. Re-run `flutter test test/balance` after any change to `assets/config`.
