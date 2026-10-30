import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

Matcher refusedWith(RuleError error) =>
    throwsA(isA<RuleException>().having((e) => e.error, 'error', error));

void main() {
  late GameConfig config;
  late GameCrew crew;
  late Rules rules;
  late Simulation sim;
  late CrewDesk desk;

  setUpAll(() async {
    config = await shippedConfig();
    crew = GameCrew(config);
    rules = Rules(config, crew: crew);
    sim = Simulation(rules);
    desk = sim.crew;
  });

  CrewMember member(
    String id,
    String role, {
    String? plane,
    String? city,
    int level = 1,
    List<String> nodes = const [],
    String? signature,
    String home = 'chicago',
    int price = 2000,
    Map<String, int> tiers = const {},
  }) => CrewMember(
    id: id,
    name: id,
    roleId: role,
    signatureId: signature,
    homeCityId: home,
    hirePrice: price,
    level: level,
    nodes: nodes,
    planeId: plane,
    cityId: city,
    staffTiers: tiers,
  );

  Plane plane(String id, String model, {String city = 'chicago'}) =>
      Plane(id: id, modelId: model, cityId: city);

  /// Chicago (level 4) and friends, with [members] on staff and every
  /// plane already given its free pilot.
  GameState hub({
    List<Plane> planes = const [],
    List<CrewMember> members = const [],
    List<Job> board = const [],
    int money = 100000,
    int chicagoLevel = 4,
  }) {
    final s = airline(
      airports: [
        AirportState(cityId: 'chicago', level: chicagoLevel, board: board),
        const AirportState(cityId: 'toronto', level: 4),
        const AirportState(cityId: 'minneapolis', level: 3),
        const AirportState(cityId: 'london', level: 4),
        const AirportState(cityId: 'new_york', level: 4),
      ],
      planes: planes,
      money: money,
    );
    return s.copyWith(
      crew: CrewState(
        members: members,
        staffedPlaneIds: [for (final p in planes) p.id],
      ),
    );
  }

  Plane p1(GameState s) => s.plane('p1')!;

  group('pilots and seats', () {
    test('a new airline\'s plane comes with a free rookie pilot', () {
      final s = sim.startAirline(
        GameState.newGame(now: t0, startingMoney: 5000),
        'chicago',
        t0,
      );
      final pilot = s.crew.members.single;
      expect(pilot.roleId, 'pilot');
      expect(pilot.planeId, s.planes.single.id);
      expect(pilot.level, 1);
      expect(pilot.signatureId, isNotNull);
      expect(s.crew.staffedPlaneIds, [s.planes.single.id]);
      expect(s.player.money, 5000);
    });

    test('a plane bought later gets its free pilot on the next tick', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [member('c1', 'pilot', plane: 'p1')],
      );
      s = s.copyWith(planes: [...s.planes, plane('p2', 'pelican_p4')]);
      s = runTo(sim, s, t0.add(const Duration(seconds: 1)));
      expect(s.crew.onPlane('p2').single.roleId, 'pilot');
      expect(s.crew.onPlane('p2').single.hirePrice, 3000);
      // Only once: moving the pilot off doesn't summon another.
      s = desk.unassign(s, s.crew.onPlane('p2').single.id, s.simulatedTo);
      s = runTo(sim, s, t0.add(const Duration(seconds: 2)));
      expect(s.crew.onPlane('p2'), isEmpty);
    });

    test('a plane without enough pilots can\'t depart', () {
      final s = hub(planes: [plane('p1', 'sparrow_s1')]);
      expect(
        sim.quote(s, 'p1', ['toronto'], t0).problems,
        contains(RuleError.crewMissing),
      );
      expect(
        () => sim.depart(s, 'p1', ['toronto'], t0),
        refusedWith(RuleError.crewMissing),
      );
    });

    test('Large planes need a captain and a first officer', () {
      var s = hub(
        planes: [plane('p1', 'albatross_l6')],
        members: [member('c1', 'pilot', plane: 'p1')],
      );
      expect(crew.departureProblem(s, p1(s)), 'Needs 2 pilots');
      s = s.copyWith(
        crew: s.crew.copyWith(
          members: [...s.crew.members, member('c2', 'pilot', level: 3)],
        ),
      );
      s = desk.assignToPlane(s, 'c2', 'p1', t0);
      expect(crew.departureProblem(s, p1(s)), isNull);
      final aboard = crew.aboard(s, p1(s));
      expect(aboard.captain!.id, 'c2', reason: 'the higher level captains');
    });

    test('Small planes have no open seats; Medium 1, Large 2', () {
      var s = hub(
        planes: [
          plane('p1', 'sparrow_s1'),
          plane('p2', 'pelican_p4'),
          plane('p3', 'albatross_l6'),
        ],
        members: [
          member('pa', 'pilot', plane: 'p1'),
          member('pb', 'pilot', plane: 'p2'),
          member('pc', 'pilot', plane: 'p3'),
          member('n1', 'navigator'),
          member('n2', 'navigator'),
          member('n3', 'flight_attendant'),
        ],
      );
      expect(
        () => desk.assignToPlane(s, 'n1', 'p1', t0),
        refusedWith(RuleError.noCrewSeat),
      );
      s = desk.assignToPlane(s, 'n1', 'p2', t0);
      expect(
        () => desk.assignToPlane(s, 'n2', 'p2', t0),
        refusedWith(RuleError.noCrewSeat),
      );
      s = desk.assignToPlane(s, 'n2', 'p3', t0);
      s = desk.assignToPlane(s, 'n3', 'p3', t0);
      // A first officer still fits the Large plane's second pilot seat, but
      // nobody else does.
      expect(desk.hasSeatFor(s, p1(s), member('x', 'pilot')), isFalse);
      expect(desk.hasSeatFor(s, s.plane('p3')!, member('x', 'pilot')), isTrue);
      expect(
        desk.hasSeatFor(s, s.plane('p3')!, member('y', 'loadmaster')),
        isFalse,
      );
    });

    test('crew only move while their plane is parked', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1'), plane('p2', 'sparrow_s1')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member('c2', 'pilot'),
        ],
      );
      s = sim.depart(s, 'p1', ['toronto'], t0);
      expect(() => desk.unassign(s, 'c1', t0), refusedWith(RuleError.crewBusy));
      expect(
        () => desk.assignToPlane(s, 'c2', 'p1', t0),
        refusedWith(RuleError.crewBusy),
      );
      s = desk.assignToPlane(s, 'c2', 'p2', t0);
      expect(s.crew.member('c2')!.planeId, 'p2');
    });

    test('flight crew go on planes, staff at airports', () {
      final s = hub(
        planes: [plane('p1', 'pelican_p4')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member('m1', 'airport_manager'),
          member('n1', 'navigator'),
        ],
      );
      expect(
        () => desk.assignToPlane(s, 'm1', 'p1', t0),
        refusedWith(RuleError.wrongRole),
      );
      expect(
        () => desk.assignToAirport(s, 'n1', 'chicago', t0),
        refusedWith(RuleError.wrongRole),
      );
    });

    test('airports have 1 staff slot, 2 from level 3, 3 at level 5', () {
      var s = hub(
        chicagoLevel: 2,
        members: [
          member('m1', 'airport_manager'),
          member('m2', 'station_agent'),
        ],
      );
      s = desk.assignToAirport(s, 'm1', 'chicago', t0);
      expect(
        () => desk.assignToAirport(s, 'm2', 'chicago', t0),
        refusedWith(RuleError.noStaffSlot),
      );
      s = desk.assignToAirport(s, 'm2', 'minneapolis', t0);
      expect(desk.staffSlots(s, 'minneapolis'), 2);
      expect(desk.staffSlots(s, 'london'), 2);
    });

    test('crew on a plane that is gone are unassigned', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [member('c1', 'pilot', plane: 'p1')],
      );
      s = s.copyWith(planes: []);
      s = runTo(sim, s, t0.add(const Duration(seconds: 1)));
      expect(s.crew.member('c1')!.isAssigned, isFalse);
    });
  });

  group('base bonuses', () {
    test('pilot +8% speed, navigator +12% range, first officer at 50%', () {
      final s = hub(
        planes: [plane('p1', 'albatross_l6')],
        members: [
          member('c1', 'pilot', plane: 'p1', level: 2),
          member('c2', 'pilot', plane: 'p1'),
          member('n1', 'navigator', plane: 'p1'),
        ],
      );
      expect(crew.speedPct(s, p1(s)), closeTo(8 + 4, 1e-9));
      expect(crew.rangePct(s, p1(s)), 12);
      final stats = PlaneStats.of(rules, s, p1(s));
      expect(stats.speedKmh, closeTo(650 * 1.12, 1e-9));
      expect(stats.rangeKm, closeTo(9000 * 1.12, 1e-9));
    });

    test('flight attendants and loadmasters add to pay on their plane', () {
      final s = hub(
        planes: [plane('p1', 'pelican_p4')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member('f1', 'flight_attendant', plane: 'p1'),
        ],
      );
      final pax = job('a', 'chicago', 'toronto');
      final box = cargo('b', 'chicago', 'toronto');
      expect(crew.deliveryPayPct(s, p1(s), pax), 10);
      expect(crew.deliveryPayPct(s, p1(s), box), 0);
      expect(sim.flights.deliveryPay(s, p1(s), pax, t0), 110);
    });

    test('a loadmaster aboard lets fragile cargo load', () {
      final fragile = job(
        'f',
        'chicago',
        'toronto',
        type: JobType.cargo,
        kind: JobKind.fragile,
      );
      var s = hub(
        planes: [plane('p1', 'pelican_p4')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member('l1', 'loadmaster'),
        ],
        board: [fragile],
      );
      expect(
        () => sim.loadJob(s, 'p1', 'f', t0),
        refusedWith(RuleError.fragileNeedsLoadmaster),
      );
      s = desk.assignToPlane(s, 'l1', 'p1', t0);
      s = sim.loadJob(s, 'p1', 'f', t0);
      expect(p1(s).load.single.id, 'f');
    });

    test('an airport manager makes new jobs there pay +5%', () {
      final s = hub(
        members: [member('m1', 'airport_manager', city: 'chicago')],
      );
      expect(crew.boardPayPct(s, 'chicago', JobType.passenger), 5);
      expect(crew.boardPayPct(s, 'toronto', JobType.passenger), 0);
    });

    test('a station agent makes jobs dropped there to connect pay +10%', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member('s1', 'station_agent', city: 'toronto'),
        ],
        board: [job('a', 'chicago', 'new_york')],
      );
      s = sim.loadJob(s, 'p1', 'a', t0, dropAtCityId: 'toronto');
      s = sim.depart(s, 'p1', ['toronto'], t0);
      s = runTo(sim, s, t0.add(const Duration(hours: 1)));
      final waiting = s
          .airport('toronto')!
          .board
          .firstWhere((j) => j.id == 'a');
      expect(waiting.bonusPct, 10);
    });
  });

  group('crew XP', () {
    test('XP = km / 10 x plane factor x load factor, full Pelican', () {
      final jobs = [
        for (var i = 0; i < 6; i++) job('p$i', 'chicago', 'toronto'),
        for (var i = 0; i < 4; i++) cargo('c$i', 'chicago', 'toronto'),
      ];
      var s = hub(
        planes: [plane('p1', 'pelican_p4')],
        members: [member('c1', 'pilot', plane: 'p1')],
        board: jobs,
      );
      s = sim.fillTo(s, 'p1', 'toronto', t0);
      expect(p1(s).load, hasLength(10));
      s = sim.depart(s, 'p1', ['toronto'], t0);
      s = runTo(sim, s, t0.add(const Duration(hours: 1)));
      final km = rules.distanceKm('chicago', 'toronto');
      final expected = (km / 10 * 1.5).round();
      final pilot = s.crew.member('c1')!;
      expect(expected, inInclusiveRange(104, 106));
      expect(pilot.lastFlight!.xp, expected);
      expect(pilot.lastFlight!.loadFactor, 1);
      // Level 1 to 2 takes 100 XP.
      expect(pilot.level, 2);
      expect(pilot.xp, expected - 100);
    });

    test('an almost empty plane earns a quarter; cross-region legs +25%', () {
      var s = hub(
        planes: [plane('p1', 'albatross_l6')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member('c2', 'pilot', plane: 'p1'),
        ],
      );
      s = sim.depart(s, 'p1', ['london'], t0);
      s = runTo(sim, s, t0.add(const Duration(hours: 3)));
      final km = rules.distanceKm('chicago', 'london');
      final flight = s.crew.member('c2')!.lastFlight!;
      expect(flight.loadFactor, 0.25);
      expect(flight.bonusPct, 25);
      expect(flight.xp, (km / 10 * 2 * 0.25 * 1.25).round());
      expect(s.crew.member('c1')!.lastFlight!.xp, flight.xp);
    });

    test('each earlier stop on a trip adds 10%', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [member('c1', 'pilot', plane: 'p1')],
      );
      s = sim.depart(s, 'p1', ['minneapolis', 'chicago', 'toronto'], t0);
      s = runTo(sim, s, t0.add(const Duration(hours: 2)));
      expect(s.crew.member('c1')!.lastFlight!.bonusPct, 20);
      expect(s.crew.member('c1')!.lastFlight!.toCityId, 'toronto');
    });

    test('levels follow 100 x level^1.5 and stop at 12', () {
      expect(config.crew.xpToNext(1), 100);
      expect(config.crew.xpToNext(2), 283);
      var m = member('c1', 'pilot');
      m = crew.gainXp(m, 100000);
      expect(m.level, 12);
      expect(m.xp, 0);
    });

    test('Mentor gives other crew aboard +10% per node', () {
      var s = hub(
        planes: [plane('p1', 'pelican_p4')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member(
            'n1',
            'navigator',
            plane: 'p1',
            level: 3,
            signature: 'mentor',
            nodes: ['mentor.1', 'mentor.2'],
          ),
        ],
      );
      s = sim.depart(s, 'p1', ['toronto'], t0);
      s = runTo(sim, s, t0.add(const Duration(hours: 1)));
      expect(s.crew.member('c1')!.lastFlight!.bonusPct, 20);
      expect(s.crew.member('n1')!.lastFlight!.bonusPct, 0);
    });

    test('Passport doubles that member\'s XP on cross-region legs', () {
      var s = hub(
        planes: [plane('p1', 'albatross_l6')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member(
            'c2',
            'pilot',
            plane: 'p1',
            signature: 'globetrotter',
            level: 4,
            nodes: [
              'globetrotter.1',
              'globetrotter.2',
              'globetrotter.3',
              'passport',
            ],
          ),
        ],
      );
      s = sim.depart(s, 'p1', ['london'], t0);
      s = runTo(sim, s, t0.add(const Duration(hours: 3)));
      final plain = s.crew.member('c1')!.lastFlight!.xp;
      expect(s.crew.member('c2')!.lastFlight!.xp, closeTo(plain * 2, 1));
    });

    test('Legacy: reaching level 6 with a Legacy mentor gives a free node', () {
      final mentor = member(
        'n1',
        'navigator',
        plane: 'p1',
        level: 4,
        signature: 'mentor',
        nodes: ['mentor.1', 'mentor.2', 'mentor.3', 'legacy'],
      );
      var s = hub(planes: [plane('p1', 'pelican_p4')], members: [mentor]);
      final rookie = member('c1', 'pilot', plane: 'p1', level: 5);
      final grown = crew.gainXp(rookie, 2000);
      expect(grown.level, greaterThanOrEqualTo(6));
      s = s.copyWith(
        crew: s.crew.copyWith(
          members: [
            ...s.crew.members,
            rookie.copyWith(xp: config.crew.xpToNext(5) - 1),
          ],
        ),
      );
      s = sim.depart(s, 'p1', ['toronto'], t0);
      s = runTo(sim, s, t0.add(const Duration(hours: 1)));
      final c1 = s.crew.member('c1')!;
      expect(c1.level, 6);
      expect(c1.bonusNodes, ['mentor.1']);
      expect(c1.nodes, isEmpty);
      expect(desk.unspentPoints(c1), 6);
    });
  });

  group('skill trees', () {
    test('1 point per level; nodes unlock top to bottom', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [
          member('c1', 'pilot', plane: 'p1', level: 2, signature: 'lucky'),
        ],
      );
      expect(desk.unspentPoints(s.crew.member('c1')!), 2);
      expect(
        () => desk.learn(s, 'c1', 'range.2', t0),
        refusedWith(RuleError.nodeLocked),
      );
      expect(
        () => desk.learn(s, 'c1', 'comfort.1', t0),
        refusedWith(RuleError.wrongRole),
      );
      expect(
        () => desk.learn(s, 'c1', 'night_owl.1', t0),
        refusedWith(RuleError.wrongRole),
        reason: 'only their own signature',
      );
      s = desk.learn(s, 'c1', 'range.1', t0);
      s = desk.learn(s, 'c1', 'lucky.1', t0);
      expect(
        () => desk.learn(s, 'c1', 'range.2', t0),
        refusedWith(RuleError.noSkillPoints),
      );
      expect(crew.rangePct(s, p1(s)), 5);
    });

    test('respec refunds every point for half the hire price', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [
          member(
            'c1',
            'pilot',
            plane: 'p1',
            level: 2,
            nodes: ['range.1', 'range.2'],
            price: 1500,
          ),
        ],
        money: 1000,
      );
      s = desk.respec(s, 'c1', t0);
      expect(s.player.money, 1000 - 750);
      expect(s.crew.member('c1')!.nodes, isEmpty);
      expect(desk.unspentPoints(s.crew.member('c1')!), 2);
    });
  });

  group('hiring', () {
    test('three rookies on offer, the same until they refresh 8 hours on', () {
      final s = hub();
      final a = desk.shelves(s, t0);
      final b = desk.shelves(s, t0.add(const Duration(minutes: 30)));
      expect(a.rookies, hasLength(3));
      expect(
        a.rookies.map((o) => o.member.name),
        b.rookies.map((o) => o.member.name),
      );
      expect(a.rookies.every((o) => o.member.roleId != 'pilot'), isTrue);
      final later = desk.shelves(s, a.rookiesRefreshAt);
      expect(later.rookies.first.id, isNot(a.rookies.first.id));
      expect(a.rookiesRefreshAt.difference(t0).inHours, lessThanOrEqualTo(8));
    });

    test('non-pilots cost 2,000, then 25% more for each on staff', () {
      var s = hub();
      final offers = desk.shelves(s, t0).rookies;
      expect(offers.first.price, 2000);
      s = desk.hire(s, offers[0].id, t0);
      expect(s.player.money, 100000 - 2000);
      expect(desk.shelves(s, t0).rookies[1].price, 2500);
      s = desk.hire(s, offers[1].id, t0);
      expect(desk.shelves(s, t0).rookies[2].price, 3125);
      expect(
        () => desk.hire(s, offers[0].id, t0),
        refusedWith(RuleError.offerTaken),
      );
      final hired = s.crew.members.last;
      expect(hired.isAssigned, isFalse);
      expect(hired.hirePrice, 2500);
      expect(s.crew.hiredOffers, [offers[0].id, offers[1].id]);
    });

    test('pilots are priced by the fleet\'s biggest class', () {
      var s = hub(planes: [plane('p1', 'sparrow_s1')]);
      expect(desk.shelves(s, t0).pilotPrice, 1500);
      s = s.copyWith(planes: [...s.planes, plane('p2', 'albatross_l6')]);
      expect(desk.shelves(s, t0).pilotPrice, 6000);
      s = desk.hirePilot(s, t0);
      expect(s.player.money, 100000 - 6000);
      // The new pilot goes straight to the plane short of one.
      expect(s.crew.members.last.planeId, 'p1');
    });

    test('a veteran of the day: level 6 to 10, 15,000 per level, grown', () {
      final s = hub();
      final vets = <String>{};
      for (var d = 0; d < 40; d++) {
        final shelf = desk.shelves(s, t0.add(Duration(days: d)));
        final v = shelf.veteran!;
        vets.add(v.member.namedId!);
        expect(v.member.level, inInclusiveRange(6, 10));
        expect(v.price, 15000 * v.member.level);
        expect(v.member.isVeteran, isTrue);
        expect(v.bio, isNotEmpty);
        if (config.crew.role(v.member.roleId).isFlightCrew) {
          expect(v.member.nodes, hasLength(v.member.level));
          expect(desk.unspentPoints(v.member), 0);
        } else {
          final tiers = v.member.staffTiers.values.fold(0, (a, b) => a + b);
          expect(tiers, v.member.level - 3);
        }
      }
      expect(vets, hasLength(40), reason: 'no repeats until all 40 appear');
    });

    test(
      'Amara Okafor at level 8 has her Range capstone and Night owl 3/4',
      () {
        final amara = config.crew.named.firstWhere(
          (n) => n.id == 'amara_okafor',
        );
        final v = desk.veteran(amara, 8);
        expect(v.nodes, [
          'range.1',
          'range.2',
          'range.3',
          'range.4',
          'ferry',
          'night_owl.1',
          'night_owl.2',
          'night_owl.3',
        ]);
      },
    );

    test('a hired veteran stays off the shelf', () {
      var s = hub();
      final v = desk.shelves(s, t0).veteran!;
      s = desk.hire(s, v.id, t0);
      expect(s.crew.members.last.namedId, v.member.namedId);
      expect(desk.shelves(s, t0).veteran!.taken, isTrue);
      for (var d = 1; d < 45; d++) {
        final next = desk.shelves(s, t0.add(Duration(days: d))).veteran!;
        expect(next.member.namedId, isNot(v.member.namedId));
      }
    });
  });

  group('airport staff upgrades', () {
    test('tiers cost 2,000 / 8,000 / 25,000 scaled by city size', () {
      var s = hub(
        members: [member('m1', 'airport_manager', city: 'minneapolis')],
      );
      final m = s.crew.member('m1')!;
      expect(desk.staffTierCost(s, m, 'marketing'), 2000);
      s = desk.buyStaffTier(s, 'm1', 'marketing', t0);
      expect(s.player.money, 98000);
      // Chicago is size 4: x1.5.
      s = desk.assignToAirport(s, 'm1', 'chicago', t0);
      expect(desk.staffTierCost(s, s.crew.member('m1')!, 'marketing'), 12000);
      s = desk.buyStaffTier(s, 'm1', 'marketing', t0);
      s = desk.buyStaffTier(s, 'm1', 'marketing', t0);
      expect(
        () => desk.buyStaffTier(s, 'm1', 'marketing', t0),
        refusedWith(RuleError.maxTier),
      );
      expect(crew.boardPayPct(s, 'chicago', JobType.cargo), 5 + 15);
    });

    test('staff must work somewhere to be upgraded', () {
      final s = hub(members: [member('m1', 'airport_manager')]);
      expect(
        () => desk.buyStaffTier(s, 'm1', 'marketing', t0),
        refusedWith(RuleError.notAssigned),
      );
    });

    test('Bigger board and Lost and found add board slots', () {
      final s = hub(
        members: [
          member(
            'm1',
            'airport_manager',
            city: 'chicago',
            tiers: {'bigger_board': 2},
          ),
          member(
            's1',
            'station_agent',
            city: 'chicago',
            tiers: {'lost_and_found': 1},
          ),
        ],
      );
      expect(crew.extraBoardSlots(s, 'chicago'), 5);
      expect(crew.favoursConnections(s, 'chicago'), isTrue);
      final size = sim.boards.boardSize(s, s.airport('chicago')!);
      final base = config.airports.level(4).jobBoardSize;
      expect(size.passenger + size.cargo, base + 5);
    });

    test('Hub pride and VIP crew parked here raise the VIP chance', () {
      final s = hub(
        planes: [plane('p1', 'pelican_p4')],
        members: [
          member(
            'm1',
            'airport_manager',
            city: 'chicago',
            tiers: {'hub_pride': 2},
          ),
          member('c1', 'pilot', plane: 'p1'),
          member(
            'f1',
            'flight_attendant',
            plane: 'p1',
            nodes: ['vip_service.1'],
          ),
        ],
      );
      expect(crew.specialChancePct(s, 'chicago', JobKind.vip), 10 + 3);
      expect(crew.specialChancePct(s, 'toronto', JobKind.vip), 0);
    });

    test('Codeshare staff give connecting crew more XP', () {
      var s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [
          member('c1', 'pilot', plane: 'p1'),
          member(
            's1',
            'station_agent',
            city: 'minneapolis',
            tiers: {'codeshare': 2},
          ),
        ],
      );
      s = sim.depart(s, 'p1', ['minneapolis', 'chicago'], t0);
      s = runTo(sim, s, p1(s).leg!.arriveAt);
      final first = s.crew.member('c1')!.lastFlight!;
      expect(first.toCityId, 'minneapolis');
      expect(first.bonusPct, 20);
    });
  });

  group('capstones and signatures', () {
    GameState withNodes(
      String role,
      List<String> nodes, {
      String model = 'pelican_p4',
      String? signature,
      List<Job> board = const [],
    }) => hub(
      planes: [plane('p1', model)],
      members: [
        if (role != 'pilot') member('c0', 'pilot', plane: 'p1'),
        member(
          'c1',
          role,
          plane: 'p1',
          level: 12,
          nodes: nodes,
          signature: signature,
        ),
      ],
      board: board,
    );

    test('Ferry: +50% range when flying empty', () {
      final s = withNodes('pilot', [
        'range.1',
        'range.2',
        'range.3',
        'range.4',
        'ferry',
      ]);
      expect(crew.rangePct(s, p1(s)), 25 + 50);
      final loaded = p1(s).copyWith(load: [job('a', 'chicago', 'toronto')]);
      expect(crew.rangePct(s, loaded), 25);
    });

    test('Fuel saver lowers fuel; Shortcuts cut flight time', () {
      var s = withNodes('pilot', ['fuel_saver.1', 'fuel_saver.2']);
      expect(crew.fuelPct(s, p1(s)), -10);
      s = withNodes('navigator', [
        'shortcuts.1',
        'shortcuts.2',
        'shortcuts.3',
        'shortcuts.4',
      ]);
      // Pilot +8% speed, and 15% less time.
      final plain = withNodes('navigator', []);
      final km = rules.distanceKm('chicago', 'london');
      Duration time(GameState s) => config.flights.realDuration(
        km,
        PlaneStats.of(rules, s, p1(s)).speedKmh,
      );
      expect(
        time(s).inMilliseconds / time(plain).inMilliseconds,
        closeTo(0.85, 0.01),
      );
    });

    test('All-weather lands in fog whatever the captain\'s level', () {
      final s = withNodes('navigator', [
        'region_expert.1',
        'region_expert.2',
        'region_expert.3',
        'region_expert.4',
        'all_weather',
      ]);
      expect(crew.landsInFog(s, p1(s)), isTrue);
      expect(crew.captainLevel(s, p1(s)), 1);
    });

    test('Tailwind never pays the headwind', () {
      final s = withNodes('navigator', ['shortcuts.1']);
      final tail = withNodes('navigator', [
        'shortcuts.1',
        'shortcuts.2',
        'shortcuts.3',
        'shortcuts.4',
        'tailwind',
      ]);
      expect(crew.ignoresHeadwind(s, p1(s)), isFalse);
      expect(crew.ignoresHeadwind(tail, p1(tail)), isTrue);
    });

    test('Five star: charters pay +40% instead of +25%', () {
      final s = withNodes('flight_attendant', [
        'comfort.1',
        'comfort.2',
        'comfort.3',
        'comfort.4',
        'five_star',
      ]);
      final charter = job('a', 'chicago', 'toronto').copyWith(loadBonusPct: 25);
      // Base 10 + comfort 15 + Five star 15, plus the job's own 25.
      expect(crew.deliveryPayPct(s, p1(s), charter), 10 + 15 + 15);
      expect(sim.flights.deliveryPay(s, p1(s), charter, t0), 100 * 165 ~/ 100);
    });

    test('Duty free: +10 coins a passenger', () {
      final s = withNodes('flight_attendant', [
        'upsell.1',
        'upsell.2',
        'upsell.3',
        'upsell.4',
        'duty_free',
      ]);
      final pax = job('a', 'chicago', 'toronto', payout: 200);
      // Chicago to Toronto is under 2 hours, so Upsell doesn't apply.
      expect(sim.flights.deliveryPay(s, p1(s), pax, t0), 200 + 20 + 10);
    });

    test('Red carpet gives VIP jobs an extra hour', () {
      final s = withNodes('flight_attendant', [
        'vip_service.1',
        'vip_service.2',
        'vip_service.3',
        'vip_service.4',
        'red_carpet',
      ]);
      final vip = job(
        'v',
        'chicago',
        'toronto',
        kind: JobKind.vip,
        deadline: t0,
      );
      final late = t0.add(const Duration(minutes: 30));
      expect(sim.flights.isLate(s, p1(s), vip, late), isFalse);
      expect(
        sim.flights.isLate(s, p1(s), vip, t0.add(const Duration(minutes: 61))),
        isTrue,
      );
    });

    test('Tight ship counts a hold one slot short as full', () {
      final s = withNodes('loadmaster', [
        'packing.1',
        'packing.2',
        'packing.3',
        'packing.4',
        'tight_ship',
      ]);
      final loaded = p1(s).copyWith(
        load: [for (var i = 0; i < 3; i++) cargo('c$i', 'chicago', 'toronto')],
      );
      final load = sim.loading.summary(s, loaded, t0);
      expect(load.cargoSlots, 4);
      expect(load.isFullHold, isTrue);
      expect(
        crew.deliveryPayPct(
          s,
          loaded,
          cargo('x', 'chicago', 'toronto').copyWith(loadBonusPct: 15),
        ),
        10 + 25,
      );
    });

    test('Kid gloves doubles fragile jobs where the plane is parked', () {
      final s = withNodes('loadmaster', [
        'fragile_goods.1',
        'fragile_goods.2',
        'fragile_goods.3',
        'fragile_goods.4',
        'kid_gloves',
      ]);
      expect(
        crew.specialChancePct(s, 'chicago', JobKind.fragile),
        config.jobs.special['fragile']!.chancePct,
      );
      expect(
        crew.deliveryPayPct(
          s,
          p1(s),
          job(
            'f',
            'chicago',
            'toronto',
            type: JobType.cargo,
            kind: JobKind.fragile,
          ),
        ),
        10 + 50,
      );
    });

    test('Heavy lift and Talk show pay 4x instead of 3x', () {
      final heavy = withNodes('loadmaster', [
        'bulk_freight.1',
        'bulk_freight.2',
        'bulk_freight.3',
        'bulk_freight.4',
        'heavy_lift',
      ]);
      final bulk = job(
        'b',
        'chicago',
        'toronto',
        type: JobType.cargo,
        kind: JobKind.bulk,
        slots: 2,
      );
      expect(crew.payMultiplier(heavy, p1(heavy), bulk), closeTo(4 / 3, 1e-9));
      final talk = withNodes('flight_attendant', [
        'charmer.1',
        'charmer.2',
        'charmer.3',
        'talk_show',
      ], signature: 'charmer');
      final vip = job('v', 'chicago', 'toronto', kind: JobKind.vip);
      expect(crew.payMultiplier(talk, p1(talk), vip), closeTo(4 / 3, 1e-9));
      expect(crew.specialChancePct(talk, 'chicago', JobKind.vip), 12);
    });

    test('Packer adds cargo slots; Tetris packs bulk crates into one', () {
      final s = withNodes('loadmaster', [
        'packer.1',
        'packer.2',
        'packer.3',
        'tetris',
      ], signature: 'packer');
      expect(PlaneStats.of(rules, s, p1(s)).cargoSlots, 4 + 2);
      final bulk = job(
        'b',
        'chicago',
        'toronto',
        type: JobType.cargo,
        kind: JobKind.bulk,
        slots: 2,
      );
      expect(crew.jobSlots(s, p1(s), bulk), 1);
    });

    test('Homebody pays more on legs touching their home city', () {
      final s = withNodes('navigator', [
        'homebody.1',
        'homebody.2',
      ], signature: 'homebody');
      final home = job('a', 'toronto', 'chicago');
      final away = job('b', 'toronto', 'new_york');
      expect(crew.deliveryPayPct(s, p1(s), home), 10);
      expect(crew.deliveryPayPct(s, p1(s), away), 0);
    });

    test('Local hero tops up their home board halfway between rotations', () {
      var s = withNodes('navigator', [
        'homebody.1',
        'homebody.2',
        'homebody.3',
        'local_hero',
      ], signature: 'homebody');
      expect(crew.boardRefillsPerRotation(s, 'chicago'), 2);
      expect(crew.boardRefillsPerRotation(s, 'toronto'), 1);
      s = sim.boards.fill(s, 'chicago', t0);
      final full = s.airport('chicago')!.board.length;
      // Take a job off the board onto the plane.
      s = sim.loadJob(s, 'p1', s.airport('chicago')!.board.first.id, t0);
      expect(s.airport('chicago')!.board, hasLength(full - 1));
      s = runTo(sim, s, t0.add(const Duration(minutes: 2, seconds: 31)));
      expect(s.airport('chicago')!.board, hasLength(full));
    });

    test('Night owl pays more on long flights; Globetrotter cross-region', () {
      final s = withNodes(
        'pilot',
        ['night_owl.1', 'night_owl.2'],
        model: 'albatross_l6',
        signature: 'night_owl',
      );
      final long = job('a', 'chicago', 'london');
      final short = job('b', 'chicago', 'toronto');
      expect(crew.deliveryPayPct(s, p1(s), long), 10);
      expect(crew.deliveryPayPct(s, p1(s), short), 0);
      final g = withNodes('pilot', [
        'globetrotter.1',
      ], signature: 'globetrotter');
      expect(crew.deliveryPayPct(g, p1(g), long), 8);
    });

    test('Red-eye pays +25% for landings while the player is away', () {
      GameState flown(bool away) {
        var s = withNodes(
          'navigator',
          ['night_owl.1', 'night_owl.2', 'night_owl.3', 'red_eye'],
          signature: 'night_owl',
          board: [job('a', 'chicago', 'toronto', payout: 1000)],
        );
        s = sim.loadJob(s, 'p1', 'a', t0);
        s = sim.depart(s, 'p1', ['toronto'], t0);
        final lands = p1(s).leg!.arriveAt;
        if (!away) {
          return runTo(sim, s, lands.add(const Duration(seconds: 1)));
        }
        return runTo(sim, s, lands.add(const Duration(hours: 2)));
      }

      final watching = flown(false).player.money;
      final away = flown(true).player.money;
      expect(away - watching, 250);
    });

    test('Lucky and Jackpot sometimes pay 3x', () {
      var s = withNodes('navigator', [
        'lucky.1',
        'lucky.2',
        'lucky.3',
        'jackpot',
      ], signature: 'lucky');
      final p = p1(s).copyWith(load: [job('a', 'chicago', 'toronto')]);
      final leg = FlightLeg(
        fromCityId: 'chicago',
        toCityId: 'toronto',
        departAt: t0,
        arriveAt: t0,
        distanceKm: 700,
      );
      var lucky = 0;
      for (var i = 0; i < 400; i++) {
        final (next, extra) = crew.afterLanding(
          s,
          p,
          leg,
          [(job: job('a', 'chicago', 'toronto'), pay: 100)],
          t0,
          unattended: false,
        );
        if (extra > 0) {
          expect(extra, 200);
          lucky++;
        }
        s = next.copyWith(crew: s.crew);
      }
      // 6% chance.
      expect(lucky, inInclusiveRange(10, 45));
    });
  });

  group('autopilot', () {
    GameState autopilotPlane({int money = 100000}) {
      final s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [
          member(
            'c1',
            'pilot',
            plane: 'p1',
            level: 5,
            nodes: [
              'fuel_saver.1',
              'fuel_saver.2',
              'fuel_saver.3',
              'fuel_saver.4',
              'autopilot',
            ],
          ),
        ],
        money: money,
      );
      return sim.boards.fill(sim.boards.fill(s, 'chicago', t0), 'toronto', t0);
    }

    test('needs a captain with Autopilot', () {
      final s = hub(
        planes: [plane('p1', 'sparrow_s1')],
        members: [member('c1', 'pilot', plane: 'p1')],
      );
      expect(
        () => sim.startAutopilot(s, 'p1', ['toronto'], t0),
        refusedWith(RuleError.noAutopilot),
      );
    });

    test('loops the route, loading plain jobs, at 70% pay, while away', () {
      var s = autopilotPlane();
      s = sim.startAutopilot(s, 'p1', ['toronto'], t0);
      expect(p1(s).status, PlaneStatus.flying);
      expect(p1(s).leg!.toCityId, 'toronto');
      expect(
        p1(s).load.every(
          (j) => j.destCityId == 'toronto' && j.kind == JobKind.standard,
        ),
        isTrue,
      );
      final (later, report) = sim.advance(s, t0.add(const Duration(hours: 2)));
      expect(later.crew.autopilot, contains('p1'));
      expect(report.autopilotEarned, greaterThan(0));
      expect(later.stats.legsFlown, greaterThan(4));
      expect(later.plane('p1')!.status, PlaneStatus.flying);
    });

    test('pays 70% and never the charter bonus', () {
      var s = autopilotPlane();
      s = s.copyWith(
        crew: s.crew.copyWith(
          autopilot: {
            'p1': const AutopilotRoute(stops: ['chicago', 'toronto']),
          },
        ),
      );
      final charter = job('a', 'chicago', 'toronto').copyWith(loadBonusPct: 25);
      expect(sim.flights.deliveryPay(s, p1(s), charter, t0), 70);
    });

    test('stops when the route becomes impossible', () {
      var s = autopilotPlane();
      s = sim.startAutopilot(s, 'p1', ['toronto'], t0);
      // The next stop is no longer one of the player's airports.
      s = s.copyWith(
        airports: [
          for (final a in s.airports)
            if (a.cityId != 'chicago') a,
        ],
      );
      final (later, report) = sim.advance(s, t0.add(const Duration(hours: 1)));
      expect(later.crew.autopilot, isEmpty);
      expect(report.autopilotStoppedIds, ['p1']);
      expect(later.plane('p1')!.status, PlaneStatus.parked);
      expect(later.plane('p1')!.cityId, 'toronto');
    });

    test('can be stopped by the player', () {
      var s = autopilotPlane();
      s = sim.startAutopilot(s, 'p1', ['toronto'], t0);
      s = sim.stopAutopilot(s, 'p1', t0);
      final later = runTo(sim, s, t0.add(const Duration(hours: 1)));
      expect(later.plane('p1')!.status, PlaneStatus.parked);
    });
  });

  test('crew state survives a save round trip', () {
    var s = hub(
      planes: [plane('p1', 'sparrow_s1')],
      members: [
        member('c1', 'pilot', plane: 'p1', nodes: ['range.1']),
        member(
          'm1',
          'airport_manager',
          city: 'chicago',
          tiers: {'marketing': 2},
        ),
      ],
    );
    s = s.copyWith(
      crew: s.crew.copyWith(
        autopilot: {
          'p1': const AutopilotRoute(stops: ['chicago', 'toronto'], next: 1),
        },
        hiredOffers: ['r1.0'],
      ),
    );
    final back = GameState.fromJson(s.toJson());
    expect(back, s);
    expect(back.crew.autopilot['p1']!.stops, ['chicago', 'toronto']);
  });
}
