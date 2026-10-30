# Balance (package 9)

The design doc's balance targets are checked by a bot player, `test/balance/bot.dart`, which `test/balance/balance_test.dart` runs on the shipped config in every CI run. The bot plays 30 in-game days as three 30-minute sessions a day (45 hours of play), with the game closed in between so the offline catch-up runs. While playing it checks the game once a minute, plans trips of up to three stops the way a player would (fill for the best stop, add stops while the trip makes more per hour), and spends on the biggest plane about three hours of income buys, the hangar slots and airport levels that plane needs, new airports and region licenses. It doesn't hire crew, claim challenges or build terminals, so a real player does a little better.

The test prints the bot's report. To see it: `flutter test test/balance`.

## Targets and what the bot measured

| Target (design doc) | Check | Measured after tuning |
| --- | --- | --- |
| First new plane affordable within about 10 minutes | 15 minutes or less | 6 minutes |
| First airport upgrade within the first session | The cheapest upgrade costs less than the starting money plus 30 minutes of income | Yes (the free nearby airport, 1,000 to 2,500) |
| A full plane on a sensible route pays back in 20 to 40 flights | Every plane the bot flew 20+ times pays back in 10 to 60 flights; the median in 15 to 45 | Sparrow 14, Hauler 24, Pelican 18, Heron 34 to 39, Swift 36 to 44 |
| Money never goes negative | Lowest balance is 0 or more and no action was refused | Yes |
| Income per hour of play: 1,000 at level 1, 15,000 at level 10 | Level 1 income in 1,000 to 4,000; level 10 reached after 5 to 20 hours of play; level 25 to 50 after 30 days | 2,300/h at level 1, about 10,000/h at level 10 (reached at 12 hours, day 8), 40,000 to 55,000/h at level 30 (day 26), level 34 at day 30 |
| Crew payoff: a level 8 veteran (120,000) becomes the better deal around airline level 8 to 10, when saving for one takes less than the 15 hours a rookie needs to grow | Over 15 hours of income at level 5, under 15 by level 9 to 11 | 32 hours at level 5, 12 hours at level 10 |
| A rival can win and lose a city in a simulated week; nothing the player owns is taken | The player leads 70% to 97% of the city-hours that have a leader, and leads change hands 10+ times | 88% on Cruising Altitude, 93% on Blimp Mode, 79% on Dogfight; Chicago and Atlanta change hands every few days |

The doc's later income targets (60,000/h at level 20, 150,000/h at level 30) assumed far more planes than a 1.5-hour-a-day player buys in a month; the bot's curve is flatter and the prices that depend on income (veterans, airport levels 4 and 5, terminals, large planes) still line up with it, so those targets were left as estimates.

## What changed from the package 2 numbers

| Number | Was | Now | Why |
| --- | --- | --- | --- |
| `economy.rates.passengerPerKm` | 0.35 | 0.10 | Income was about 8x the doc's level 1 target and planes paid back in 2 to 6 flights |
| `economy.rates.cargoPerKm` | 0.45 | 0.14 | The same |
| Every plane's `fuelPerKm` | | 15% of its full pay per km at the new rates | Keeps the doc's "fuel is about 15% of a full plane's payout" |
| `economy.startingMoney` | 2,500 | 3,000 | With the Sparrow at 3,200 the first new plane is a few minutes away, not free on day one |
| Sparrow S1, Hauler H2, Puffin PF2, Kestrel K3 | 1,500, 3,000, 4,200, 6,500 | 3,200, 6,000, 9,000, 12,000 | Small planes paid back in 2 flights; now 14 to 24 |
| Heron M5, Mule MC6, Swift SJ7 | 45,000, 32,000, 70,000 | 30,000, 14,000, 42,000 | Medium planes rarely fly full (a board's jobs spread over many cities), so at the old prices they took 50 to 150 flights |
| `jobs.airlineXpPerCoin` | 0.1 | 0.2 | XP comes from pay, so lower pay needed more XP per coin to keep a steady level pace |
| `rivals.share.perCoinDelivered` | 0.01 | 0.033 | Keeps the share a delivery earns about the same at the lower pay |
| `rivals.pace.sharePerHourPerLevel` | 3 | 9 | At 3 the player led over 95% of their cities all month and rivals never mattered |
| `rivals.contracts.prizePerCitySize` | 10,000 | 1,500 | A contract prize was worth several hours of income and jumped the airline 3 levels at once |
| Dogfight's `tierStrength` | 0.85 / 1.1 / 1.6 | 1.0 / 1.35 / 1.9 | Dogfight played the same as Cruising Altitude |

Everything else (airport prices and upgrades, path tiers, crew prices, hangar slots, challenge rewards, weather) keeps its package 2 to 11 value.

## Rules tests and tuning

The rules tests in `test/logic` are written against exact numbers, so they load `testConfig()`, which pins `economy`, `jobs`, `planes` and `rivals` to the pre-tuning copies in `test/fixtures/rules_config/`. Retuning the shipped files only moves the balance test and the shipped-data checks in `test/core/config`; the rules tests keep passing. Re-run `flutter test test/balance` after any change to `assets/config`.
