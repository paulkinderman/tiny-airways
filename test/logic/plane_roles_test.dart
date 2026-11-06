import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/rng.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

/// Plane roles, takeoff fuel and cargo lots, checked against the shipped
/// config (the pinned rules config predates them).
void main() {
  late GameConfig config;
  late Rules rules;

  setUpAll(() async {
    config = await ConfigLoader(DirectoryConfigSource('assets')).load();
    rules = Rules(config);
  });

  Job job(
    String id,
    JobType type,
    String to, {
    String from = 'chicago',
    int payout = 100,
  }) => Job(
    id: id,
    type: type,
    originCityId: from,
    destCityId: to,
    payout: payout,
    createdAt: t0,
  );

  GameState withPlane(String modelId, {List<Job> load = const []}) => airline(
    airports: const [
      AirportState(cityId: 'chicago', level: 5),
      AirportState(cityId: 'toronto', level: 5),
      AirportState(cityId: 'new_york', level: 5),
      AirportState(cityId: 'london', level: 5),
    ],
    planes: [Plane(id: 'p1', modelId: modelId, cityId: 'chicago', load: load)],
  );

  test('every takeoff burns the class takeoff km of extra fuel', () {
    final km = rules.distanceKm('chicago', 'toronto');
    for (final id in ['sparrow_s1', 'heron_m5', 'goose_g10']) {
      final state = withPlane(id);
      final model = config.planes.model(id);
      final takeoff = config.planes.planeClass(model.classId).takeoffKm;
      expect(takeoff, greaterThan(0));
      expect(
        Economy(rules)
            .fuelCost(state, state.plane('p1')!, 'chicago', 'toronto', never),
        (model.fuelPerKm * (km + takeoff)).round(),
      );
    }
  });

  test('a Freighter pays more for cargo, an Express for passengers', () {
    final flights = Flights(rules);
    final crate = job('c', JobType.cargo, 'toronto');
    final seat = job('s', JobType.passenger, 'toronto');
    final mule = withPlane('mule_mc6').plane('p1')!;
    final swift = withPlane('swift_sj7').plane('p1')!;
    final sparrow = withPlane('sparrow_s1').plane('p1')!;
    expect(flights.rolePayPct(mule, crate), 25);
    expect(flights.rolePayPct(mule, seat), 0);
    expect(flights.rolePayPct(swift, seat), 30);
    expect(flights.rolePayPct(swift, crate), 0);
    expect(flights.rolePayPct(sparrow, crate), 0);
    final state = withPlane('mule_mc6');
    expect(flights.deliveryPay(state, mule, crate, t0), 125);
  });

  test('a Long haul plane pays more only on long jobs', () {
    final flights = Flights(rules);
    final goose = withPlane('goose_g10').plane('p1')!;
    expect(rules.distanceKm('chicago', 'london'), greaterThan(3000));
    expect(
      flights.rolePayPct(goose, job('a', JobType.passenger, 'london')),
      20,
    );
    expect(
      flights.rolePayPct(goose, job('b', JobType.passenger, 'toronto')),
      0,
    );
  });

  test('a Combi earns charter and full hold with mixed destinations', () {
    List<Job> mixed(int seats, int slots) => [
      for (var i = 0; i < seats; i++)
        job('s$i', JobType.passenger, i.isEven ? 'toronto' : 'new_york'),
      for (var i = 0; i < slots; i++)
        job('c$i', JobType.cargo, i.isEven ? 'toronto' : 'new_york'),
    ];
    final kestrel = config.planes.model('kestrel_k3');
    final combi = withPlane(
      'kestrel_k3',
      load: mixed(kestrel.seats, kestrel.cargoSlots),
    );
    final load = Loading(rules).summary(combi, combi.plane('p1')!, never);
    expect(load.isCharter, isTrue);
    expect(load.isFullHold, isTrue);

    final puffin = config.planes.model('puffin_pf2');
    final plain = withPlane(
      'puffin_pf2',
      load: mixed(puffin.seats, puffin.cargoSlots),
    );
    final other = Loading(rules).summary(plain, plain.plane('p1')!, never);
    expect(other.isCharter, isFalse);
    expect(other.isFullHold, isFalse);
  });

  test('a Bush plane lands where Small planes can', () {
    final pelican = config.planes.model('pelican_p4');
    final heron = config.planes.model('heron_m5');
    expect(rules.fitsAirportLevel(pelican, 1), isTrue);
    expect(rules.fitsAirportLevel(heron, 1), isFalse);
    expect(rules.fitsAirportLevel(heron, 3), isTrue);
  });

  test('big holds bring cargo lots that pay per slot', () {
    final boards = JobBoards(rules);
    final state = withPlane('condor_c9');
    final airport = state.airport('chicago')!;
    final rng = GameRng(7);
    final lots = <Job>[];
    for (var i = 0; i < 400; i++) {
      final j = boards.generate(
        state,
        rng,
        airport,
        JobType.cargo,
        t0,
        'j$i',
        double.infinity,
      )!;
      if (j.kind == JobKind.standard && j.slots > 1) lots.add(j);
    }
    expect(lots, isNotEmpty);
    expect(lots.every((j) => j.slots <= config.jobs.lotMaxSize), isTrue);
    expect(lots.map((j) => j.slots).toSet().length, greaterThan(1));
  });

  test('no lots when the fleet has no hold of two or more', () {
    final boards = JobBoards(rules);
    final state = withPlane('firefly_fx1');
    final airport = state.airport('chicago')!;
    final rng = GameRng(7);
    for (var i = 0; i < 200; i++) {
      final j = boards.generate(
        state,
        rng,
        airport,
        JobType.cargo,
        t0,
        'j$i',
        double.infinity,
      )!;
      if (j.kind == JobKind.standard) expect(j.slots, 1);
    }
  });
}
