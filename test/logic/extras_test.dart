import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

Matcher refusedWith(RuleError error) =>
    throwsA(isA<RuleException>().having((e) => e.error, 'error', error));

void main() {
  late GameConfig config;
  late Simulation sim;

  setUpAll(() async {
    config = await testConfig();
    sim = Simulation(Rules(config));
  });

  GameState midwest({
    List<Job> board = const [],
    List<Plane>? planes,
    int level = 1,
    int money = 10000,
    ExtrasState extras = ExtrasState.empty,
    int homeLevel = 3,
  }) => airline(
    airports: [
      AirportState(cityId: 'chicago', level: homeLevel, board: board),
      const AirportState(cityId: 'toronto', level: 2),
      const AirportState(cityId: 'minneapolis', level: 2),
      const AirportState(cityId: 'nashville', level: 2),
    ],
    planes:
        planes ??
        const [Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago')],
    level: level,
    money: money,
  ).copyWith(extras: extras);

  /// Flies [planeId] through [stops] and runs the clock until it parks.
  GameState fly(GameState state, String planeId, List<String> stops) {
    var next = sim.depart(state, planeId, stops, next0(state));
    for (var i = 0; i < 20; i++) {
      final plane = next.plane(planeId)!;
      if (plane.status == PlaneStatus.parked) return next;
      next = runTo(sim, next, plane.leg!.arriveAt);
    }
    fail('$planeId never parked');
  }

  final allParts = ExtrasState(
    parts: {
      for (final k in ['engine', 'wings', 'fuselage', 'tail'])
        'barnstormer.$k': 1,
    },
  );

  group('part crates', () {
    List<Job> cargoBoard(int level) {
      var state = midwest(level: level, homeLevel: 5);
      // Roll lots of boards to see what turns up.
      final jobs = <Job>[];
      for (var i = 0; i < 60; i++) {
        state = sim.boards.rotate(state, 'chicago', t0);
        jobs.addAll(state.airport('chicago')!.board);
      }
      return [
        for (final j in jobs)
          if (j.type == JobType.cargo) j,
      ];
    }

    test('appear from level 10, about 1 in 40 cargo jobs, paying nothing', () {
      expect(cargoBoard(9).where((j) => j.kind == JobKind.partCrate), isEmpty);
      final cargo = cargoBoard(10);
      final crates = cargo.where((j) => j.kind == JobKind.partCrate).toList();
      expect(crates, isNotEmpty);
      expect(crates.length / cargo.length, closeTo(1 / 40, 0.03));
      expect(crates.every((j) => j.payout == 0), isTrue);
    });

    test('delivering one adds a part to the collection instead of money', () {
      var state = midwest(
        board: [
          Job(
            id: 'crate',
            type: JobType.cargo,
            kind: JobKind.partCrate,
            originCityId: 'chicago',
            destCityId: 'toronto',
            payout: 0,
            createdAt: t0,
          ),
        ],
      );
      state = sim.loadJob(state, 'p1', 'crate', t0);
      final moneyAfterFuel =
          state.player.money - sim.quote(state, 'p1', ['toronto'], t0).fuel;
      state = fly(state, 'p1', ['toronto']);
      expect(state.player.money, moneyAfterFuel);
      expect(state.extras.parts.values.fold(0, (a, b) => a + b), 1);
      expect(state.extras.counter('partsCollected'), 1);
    });

    test('a crate usually holds a part the player is missing', () {
      final parts = sim.parts;
      final state = midwest();
      final picks = [
        for (var seed = 0; seed < 200; seed++) parts.crateContents(state, seed),
      ];
      expect(picks.toSet().length, config.extras.partIds.length);
      // Every part is missing, so all of them count as new.
      final almostDone = midwest(
        extras: ExtrasState(
          parts: {
            for (final id in config.extras.partIds)
              if (id != 'cloud_nine.tail') id: 1,
          },
        ),
      );
      final hits = [
        for (var seed = 0; seed < 200; seed++)
          parts.crateContents(almostDone, seed),
      ].where((id) => id == 'cloud_nine.tail').length;
      expect(hits / 200, greaterThan(0.5));
    });
  });

  group('special planes', () {
    test('a full set builds the plane at home, once', () {
      var state = midwest(extras: allParts);
      state = sim.buildSpecialPlane(state, 'barnstormer', t0);
      final built = state.planes.last;
      expect(built.modelId, 'barnstormer');
      expect(built.cityId, 'chicago');
      expect(built.status, PlaneStatus.parked);
      expect(state.extras.parts, isEmpty);
      expect(state.extras.builtPlanes, ['barnstormer']);
      expect(
        () => sim.buildSpecialPlane(state, 'barnstormer', t0),
        refusedWith(RuleError.alreadyBuilt),
      );
    });

    test('needs one of every part', () {
      final state = midwest(
        extras: const ExtrasState(parts: {'mach_one.engine': 3}),
      );
      expect(
        () => sim.buildSpecialPlane(state, 'mach_one', t0),
        refusedWith(RuleError.missingParts),
      );
    });

    test('parks at another airport when home has no free gate', () {
      final state = midwest(
        extras: allParts,
        homeLevel: 1,
        planes: [
          for (var i = 0; i < 4; i++)
            Plane(id: 'p$i', modelId: 'sparrow_s1', cityId: 'chicago'),
        ],
      );
      final gates = config.airports.level(1).gates;
      expect(gates, lessThanOrEqualTo(4));
      final built = sim.buildSpecialPlane(state, 'barnstormer', t0);
      expect(built.planes.last.cityId, isNot('chicago'));
    });

    test('spare parts sell; the one a build needs does not', () {
      var state = midwest(
        extras: const ExtrasState(
          parts: {'cloud_nine.wings': 2},
          builtPlanes: [],
        ),
      );
      expect(sim.parts.spares(state, 'cloud_nine.wings'), 1);
      state = sim.sellSparePart(state, 'cloud_nine.wings', t0);
      expect(state.player.money, 10000 + config.extras.duplicatePartSellPrice);
      expect(
        () => sim.sellSparePart(state, 'cloud_nine.wings', t0),
        refusedWith(RuleError.noSparePart),
      );
      // Once the plane is built, every part of it is spare.
      final built = state.copyWith(
        extras: state.extras.copyWith(builtPlanes: ['cloud_nine']),
      );
      expect(sim.parts.spares(built, 'cloud_nine.wings'), 1);
    });

    test('Mach One burns 3x fuel; Cloud Nine burns none', () {
      final state = midwest(
        planes: const [
          Plane(id: 'm', modelId: 'mach_one', cityId: 'chicago'),
          Plane(id: 'c', modelId: 'cloud_nine', cityId: 'chicago'),
          Plane(id: 's', modelId: 'sparrow_s1', cityId: 'chicago'),
        ],
        homeLevel: 5,
      );
      final economy = Economy(sim.rules);
      int fuel(String id) =>
          economy.fuelCost(state, state.plane(id)!, 'chicago', 'toronto', t0);
      expect(fuel('c'), 0);
      expect(fuel('m'), greaterThan(fuel('s') * 3));
    });
  });

  group('sightseeing', () {
    final barnstormer = const Plane(
      id: 'b1',
      modelId: 'barnstormer',
      cityId: 'chicago',
    );

    test('tours appear only while the fleet has a Barnstormer', () {
      List<Job> boards(GameState s) {
        final jobs = <Job>[];
        for (var i = 0; i < 20; i++) {
          s = sim.boards.rotate(s, 'chicago', t0);
          jobs.addAll(s.airport('chicago')!.board);
        }
        return jobs;
      }

      expect(
        boards(midwest()).where((j) => j.kind == JobKind.sightseeing),
        isEmpty,
      );
      final tours = boards(midwest(planes: [barnstormer]))
          .where((j) => j.kind == JobKind.sightseeing)
          .toList();
      expect(tours, isNotEmpty);
      for (final j in tours) {
        expect(j.type, JobType.passenger);
        expect(j.destCityId, 'chicago');
        expect(
          j.payout,
          (config.economy.passengerRatePerKm *
                  config.extras.sightseeingTourKm *
                  3)
              .round(),
        );
      }
    });

    Job tour() => Job(
      id: 'tour',
      type: JobType.passenger,
      kind: JobKind.sightseeing,
      originCityId: 'chicago',
      destCityId: 'chicago',
      payout: 900,
      createdAt: t0,
    );

    test('only the Barnstormer takes them, and they never connect', () {
      final state = midwest(
        board: [tour()],
        planes: [
          barnstormer,
          const Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago'),
        ],
      );
      expect(
        () => sim.loadJob(state, 'p1', 'tour', t0),
        refusedWith(RuleError.wrongPlaneForJob),
      );
      expect(
        () => sim.loadJob(state, 'b1', 'tour', t0, dropAtCityId: 'toronto'),
        refusedWith(RuleError.badDropCity),
      );
    });

    test('pays when the plane lands back home', () {
      var state = midwest(board: [tour()], planes: [barnstormer]);
      state = sim.loadJob(state, 'b1', 'tour', t0);
      final quote = sim.quote(state, 'b1', ['toronto', 'chicago'], t0);
      expect(quote.canDepart, isTrue);
      expect(quote.expectedPayout, 900);
      final before = state.player.money - quote.fuel;
      state = fly(state, 'b1', ['toronto', 'chicago']);
      expect(state.player.money, before + 900);
      expect(state.extras.counter('sightseeingTours'), 1);
      expect(state.extras.counter('multiStopTrips'), 1);
    });
  });

  group('challenges', () {
    final level3 = midwest(level: 3);

    test('the board opens at level 3 with 3 dailies and a weekly', () {
      expect(sim.challenges.refresh(midwest(level: 2), t0).extras.dailies, []);
      final state = sim.challenges.refresh(level3, t0);
      final extras = state.extras;
      expect(extras.dailies, hasLength(3));
      expect(extras.dailies.map((c) => c.defId).toSet(), hasLength(3));
      expect(extras.weekly, isNotNull);
      expect(extras.weekly!.bonus, 'crewXp');
      expect(extras.rerollsLeft, 1);
      // Same day: nothing changes, and the state object is the same.
      expect(identical(sim.challenges.refresh(state, t0), state), isTrue);
    });

    test('rewards scale with level: a daily is 15% of the XP bar', () {
      final reward = sim.challenges.dailyReward(11);
      expect(reward.xp, (config.progression.xpToNext(11) * 0.15).round());
      expect(reward.money, 500 * 11);
      final weekly = sim.challenges.dailyReward(11, 5);
      expect(weekly.money, reward.money * 5);
    });

    test('targets round to friendly numbers', () {
      expect(Challenges.friendly(19), 19);
      expect(Challenges.friendly(23.4), 23);
      expect(Challenges.friendly(1234), 1200);
      expect(Challenges.friendly(17890), 18000);
    });

    test('progress counts, a finished daily is claimed and replaced', () {
      var state = sim.challenges.refresh(level3, t0);
      final daily = state.extras.dailies.first;
      final metric = config.extras.challenges.def(daily.defId)!.metric;
      state = sim.challenges.record(state, metric, daily.target - 1);
      expect(state.extras.dailies.first.isDone, isFalse);
      expect(
        () => sim.claimDaily(state, 0, t0),
        refusedWith(RuleError.challengeNotDone),
      );
      state = sim.challenges.record(state, metric, 5);
      expect(state.extras.dailies.first.progress, daily.target);

      final money = state.player.money;
      state = sim.claimDaily(state, 0, t0);
      expect(state.player.money, money + daily.money);
      expect(state.extras.dailies, hasLength(3));
      expect(state.extras.dailies.first.defId, isNot(daily.defId));
      expect(state.extras.counter('dailiesClaimed'), 1);
      expect(state.extras.log.first.kind, 'daily');
    });

    test('one free reroll a day, only for unfinished dailies', () {
      var state = sim.challenges.refresh(level3, t0);
      final first = state.extras.dailies.first.defId;
      state = sim.rerollDaily(state, 0, t0);
      expect(state.extras.dailies.first.defId, isNot(first));
      expect(
        () => sim.rerollDaily(state, 1, t0),
        refusedWith(RuleError.noRerollsLeft),
      );
    });

    test('at midnight unfinished dailies reroll and finished ones stay', () {
      var state = sim.challenges.refresh(level3, t0);
      final done = state.extras.dailies.first;
      final metric = config.extras.challenges.def(done.defId)!.metric;
      state = sim.challenges.record(state, metric, done.target);
      state = sim.rerollDaily(state, 1, t0);
      final tomorrow = sim.challenges.nextDayAt(t0);
      final next = sim.challenges.refresh(state, tomorrow);
      expect(next.extras.dailies.first.defId, done.defId);
      expect(next.extras.dailies.first.isDone, isTrue);
      expect(next.extras.rerollsLeft, 1);
      expect(next.extras.dailies, hasLength(3));
    });

    test('days start at the player\'s midnight', () {
      final tokyo = Challenges(sim.rules, utcOffset: const Duration(hours: 9));
      // 2026-03-02 15:00 UTC is midnight in Tokyo.
      final midnight = DateTime.utc(2026, 3, 2, 15);
      expect(
        tokyo.dayIndex(midnight),
        tokyo.dayIndex(midnight.subtract(const Duration(seconds: 1))) + 1,
      );
      expect(tokyo.nextDayAt(midnight), DateTime.utc(2026, 3, 3, 15));
    });

    test('weeks start on Monday', () {
      // 2026-03-02 is a Monday.
      final monday = sim.challenges.dayIndex(DateTime.utc(2026, 3, 2));
      final sunday = sim.challenges.dayIndex(DateTime.utc(2026, 3, 1));
      expect(Challenges.weekIndex(monday), Challenges.weekIndex(sunday) + 1);
      expect(Challenges.weekIndex(monday + 6), Challenges.weekIndex(monday));
    });

    test('a weekly from level 10 pays a part crate', () {
      var state = sim.challenges.refresh(midwest(level: 10), t0);
      final weekly = state.extras.weekly!;
      expect(weekly.bonus, 'partCrate');
      final metric = config.extras.challenges.def(weekly.defId)!.metric;
      state = sim.challenges.record(state, metric, weekly.target);
      state = sim.claimWeekly(state, t0);
      expect(state.extras.weekly!.claimed, isTrue);
      expect(state.extras.counter('partsCollected'), 1);
      expect(
        () => sim.claimWeekly(state, t0),
        refusedWith(RuleError.alreadyClaimed),
      );
    });

    test('flying counts toward charters, landings and money', () {
      var state = sim.challenges.refresh(
        midwest(
          level: 3,
          board: [
            job('a', 'chicago', 'toronto', payout: 300),
            job('b', 'chicago', 'toronto', payout: 300),
          ],
        ),
        t0,
      );
      state = sim.fillTo(state, 'p1', 'toronto', t0);
      state = fly(state, 'p1', ['toronto']);
      final c = state.extras.counters;
      expect(c['charters'], 1);
      expect(c['landings'], 1);
      expect(c['passengersDelivered'], 2);
      expect(c['jobsDelivered'], 2);
      expect(c['moneyEarned'], greaterThanOrEqualTo(600));
      expect(c['bestLandingPay'], c['moneyEarned']);
    });
  });

  group('milestones', () {
    test('are tracked from level 1 and claimed once', () {
      var state = midwest(board: [job('a', 'chicago', 'toronto')]);
      final first = config.extras.milestone('first_delivery')!;
      expect(sim.challenges.milestoneReady(state, first), isFalse);
      state = sim.loadJob(state, 'p1', 'a', t0);
      state = fly(state, 'p1', ['toronto']);
      expect(sim.challenges.milestoneReady(state, first), isTrue);
      expect(sim.challenges.claimable(state), greaterThanOrEqualTo(1));

      final xpBefore = state.player.xp;
      state = sim.claimMilestone(state, 'first_delivery', t0);
      expect(state.extras.isClaimed('first_delivery'), isTrue);
      expect(state.player.xp, isNot(xpBefore));
      expect(
        () => sim.claimMilestone(state, 'first_delivery', t0),
        refusedWith(RuleError.alreadyClaimed),
      );
    });

    test('state milestones read the airline, and add their unlocks', () {
      var state = midwest(level: 10);
      final m = config.extras.milestone('level_10')!;
      expect(sim.challenges.progress(state, m), 10);
      state = sim.claimMilestone(state, 'level_10', t0);
      expect(state.extras.unlocks, [m.unlock]);
      expect(
        sim.challenges.progress(state, config.extras.milestone('airports_5')!),
        4,
      );
    });

    test('there are about 60', () {
      expect(config.extras.milestones.length, inInclusiveRange(55, 65));
    });
  });

  test('extras survive a save round trip', () {
    var state = sim.challenges.refresh(midwest(level: 10), t0);
    state = state.copyWith(
      extras: state.extras.copyWith(
        parts: {'barnstormer.tail': 2},
        builtPlanes: ['mach_one'],
        claimedMilestones: ['level_3'],
        unlocks: ['badge:Workhorse'],
        pendingCrewXp: 500,
      ),
    );
    final back = GameState.fromJson(state.toJson());
    expect(back, state);
    expect(back.extras.weekly!.defId, state.extras.weekly!.defId);
  });

  test('a save without extras loads with an empty collection', () {
    final json = midwest().toJson()..remove('extras');
    final back = GameState.fromJson(json);
    expect(back.extras.parts, isEmpty);
    expect(back.extras.dailies, isEmpty);
  });
}

/// The time a test acts at: the state's simulated time.
DateTime next0(GameState state) => state.simulatedTo;
