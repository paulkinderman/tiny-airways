# Crew and staff

The design doc's "Crew and staff" section, built as pure Dart in `lib/logic/` with the Crew tab in `lib/ui/`. Package 7.

## Using it

The rules ask crew questions through `CrewEffects` (`lib/logic/crew_effects.dart`). `GameCrew` (`lib/logic/crew.dart`) answers them from the crew in the save, and `simulationProvider` plugs it in:

```dart
final sim = Simulation(Rules(config, crew: GameCrew(config)));
```

Tests that don't care about crew keep using `NoCrew` (or `TestCrew`), which acts as one level 1 rookie pilot per plane.

Crew actions are `Simulation` extension methods from `lib/logic/crew_desk.dart`. Like every other action they run the world up to now first, throw `RuleException` when refused, and screens call them through `GameSession.act`:

```dart
final shelves = sim.crew.shelves(state, now);      // rookies, pilot school, veteran
state = sim.hireCrew(state, shelves.rookies.first.id, now);
state = sim.hirePilot(state, now);
state = sim.assignCrewToPlane(state, memberId, planeId, now);
state = sim.assignCrewToAirport(state, memberId, cityId, now);
state = sim.unassignCrew(state, memberId, now);
state = sim.learnSkill(state, memberId, 'range.1', now);
state = sim.respecCrew(state, memberId, now);
state = sim.buyStaffTier(state, memberId, 'marketing', now);
state = sim.startAutopilot(state, planeId, ['toronto'], now);
state = sim.stopAutopilot(state, planeId, now);
```

`sim.crew` (a `CrewDesk`) also has the queries screens need: `unspentPoints`, `learnProblem`, `respecCost`, `staffTierCost`, `seats`, `hasSeatFor`, `staffSlots`, `canMove`.

## Save schema (version 3)

`GameState.crew` (`lib/core/state/crew_state.dart`) holds every `CrewMember` (role, signature, home city, level, XP, learned nodes, free Legacy nodes, staff tiers, the plane or airport they work at, and their last flight's XP breakdown), the shelf offers already hired, the planes that have had their free pilot, and planes on autopilot. A version 2 save comes back with no crew; its planes get their free pilot on the first tick.

The shelves aren't saved. They are worked out from the time and the airline's creation time, so they look the same every time they're opened in a period and only the hires need remembering.

## Rules as built

| Rule | How it works |
| --- | --- |
| Pilots | Small and Medium planes need 1, Large 2. A plane short of pilots can't depart (`RuleError.crewMissing`). The highest-level pilot is captain; other pilots are first officers and give their percentages and slots at 50% (`xp.firstOfficerSkillFactor`). |
| Seats | Pilot seats per class, plus open seats for any role (Small 0, Medium 1, Large 2). |
| Free pilot | Every plane gets one rookie pilot the first time the rules see it (`settle`, run after every simulation step, at the end of `advance` and in `startAirline`). Planes bought by package 6 need nothing extra. |
| Moving crew | Flight crew move only while their plane (and the target plane) is parked. Staff move any time, into a free staff slot (1, 2 from airport level 3, 3 at level 5). Crew on a plane or airport that's gone are unassigned. |
| Base bonuses | Pilot +8% speed, navigator +12% range, flight attendant +10% passenger pay, loadmaster +10% cargo pay (on their plane); airport manager +5% on jobs appearing at their airport; station agent +10% on jobs dropped there to connect. |
| Crew XP | Each crew member aboard earns `km / 10 x plane factor x load factor x (1 + bonuses)` when a leg lands. Load factor is seats and slots used over capacity, at least 0.25. Bonuses: +25% cross-region leg, +20% if it delivers a VIP or bulk job, +10% per earlier stop on the trip, Mentor, Codeshare. Level L to L+1 takes `100 x L^1.5`; the top level is 12. |
| Skill points | 1 per level (a level 1 rookie has 1 to spend). Nodes unlock top to bottom within a branch; a member can learn their role's three branches and their own signature. Respec refunds every point for half the hire price. |
| Hiring | 3 non-pilot rookies on offer, new ones every 8 hours, 2,000 rising 25% for each non-pilot on staff. The pilot school is always open, priced by the fleet's biggest plane class (1,500 / 3,000 / 6,000). A new pilot goes straight to a parked plane short of one. |
| Veterans | One a day, counted from when the airline started. The 40 named crew come round in a shuffled order that changes each lap, skipping anyone hired, so nobody repeats until all have appeared. Level 6 to 10, 15,000 per level. Their points are spent: favourite branch to its capstone, then their signature, then the other branches. |
| Airport staff | No XP. Three paths of three tiers each, 2,000 / 8,000 / 25,000 scaled by the size of the city they work in (they must be working somewhere to buy). Tiers stay with them when they move. |

### Skill effects

| Effect | Where it acts |
| --- | --- |
| Range, Ferry (+50% on empty legs), Long haul | `PlaneStats` range |
| Fuel saver | Fuel cost |
| Shortcuts (flight time) | Folded into speed: -15% time is +17.6% speed |
| Tailwind | The jet stream never costs extra fuel; tailwinds still help |
| All-weather | Lands in fog whatever the captain's level |
| Passenger, cargo, fragile, in-region, cross-region, long-flight, home-leg pay | Added to the job's pay on delivery. "Flights over 2 hours" means the job's whole trip at the plane model's speed (scheduled hours, as in the simulation docs). "Cross-region" means the job's origin and destination are on different continents. |
| Five star, Packing | Extra on the charter or full-hold bonus |
| Duty free | +10 coins per passenger, as a percentage of that job's pay |
| Red carpet | VIP deadlines an hour later on this plane |
| Talk show, Heavy lift | VIP and bulk jobs pay 4x instead of 3x |
| Tight ship | A hold one slot short of full still counts as full |
| Packer, Tetris | +1 cargo slot per node (on planes that carry cargo); bulk crates take 1 slot |
| Celebrity, VIP service, Charmer, Hub pride | Percentage points added to the VIP chance for jobs appearing where the plane is parked (or at the manager's airport). They bring VIP jobs even before special jobs unlock. |
| Kid gloves | Doubles the fragile chance where the plane is parked |
| Bigger board, Lost and found | Extra board slots; Lost and found also favours far destinations, as connection jobs |
| Connections | Extra pay on jobs dropped there to connect |
| Codeshare | Extra XP for crew whose plane stops there mid-trip or drops jobs there |
| Lucky, Jackpot | A chance per delivered job of 2x (3x) pay, rolled on the saved random generator so replays match |
| Red-eye | +25% on deliveries that land a minute or more before the simulation catches up, which is when the player isn't watching |
| Local hero | Their home airport's board tops up its empty slots halfway between rotations as well |
| Mentor | +10% XP per node for the other crew aboard |
| Passport | That member's XP doubles on cross-region legs |
| Legacy | A crew member reaching level 6 while flying with a Legacy mentor gets the first node of the mentor's signature they don't have, free and kept through a respec |
| Autopilot | See below |

### Autopilot

A plane whose captain has Autopilot can be set from the route picker ("Repeat on autopilot"). The route loops: from where the plane is, through each stop, and back. At each airport it unloads, loads the best-paying plain jobs bound for the next stop (never special jobs or part crates), pays fuel and flies on. Jobs pay 70% and never earn the charter or full-hold bonus. It keeps going offline, since it runs inside the simulation's steps. It stops when the player taps Stop on the plane card, or when the next leg can't be flown (weather, range, money, crew, a diversion), and the plane waits at the gate. The welcome-back summary lists what autopilot earned and any plane that came off it.

## Screens

The Crew tab (`crew_screen.dart`) has three segments: Roster (planes and their crew, airports and their staff, anyone unassigned, and a warning with a Hire button for any plane short of pilots), Rookies (the shelf and the pilot school) and Veterans (the veteran of the day with their bio). Tapping someone opens `crew_detail.dart`: the XP bar, the skill tree in the CrewTree mockup's layout (tap a node to read it, then Learn), the last flight's XP breakdown, staff upgrade paths for airport staff, where they work and where they could move, their bio, and Reset skills.

## Design calls

- **Airport staff have no signature.** The doc gives every crew member one, but signatures are skill-tree branches and staff have no tree (see game-data.md). Their three money paths are what make them different.
- **The rookie shelf holds non-pilots; pilots come from the always-open pilot school.** Otherwise a player with a Large plane could wait days for a pilot to roll.
- **Pilot price** is the class price of the biggest plane in the fleet, since that's the plane a new pilot is usually for.
- **Captain** is the highest-level pilot aboard, so there's nothing extra to manage.
- **Veteran airport staff** come with `level - 3` tiers bought (3 to 7 of 9), favourite path first, to match a flight-crew veteran's head start.
- **A free pilot's hire price** is the pilot price for that plane's class, so respec costs something.
- **Rookies' home cities** are the player's own airports, so Homebody and Local hero always mean something.

## Left for later packages

- Portraits (package 8): the screens show initials.
- Balance (package 9): the crew payoff table in the doc ("a veteran becomes the better deal around airline level 8 to 10") is a target for the bot player.
