import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/simulation.dart';

import 'logic_test_helpers.dart';

Matcher refusedWith(RuleError error) =>
    throwsA(isA<RuleException>().having((e) => e.error, 'error', error));

void main() {
  late Simulation sim;

  setUpAll(() async {
    sim = Simulation(Rules(await testConfig()));
  });

  // A Sparrow S1 has 2 seats and 1 cargo slot.
  GameState sparrowAtChicago(
    List<Job> board, {
    String modelId = 'sparrow_s1',
  }) => airline(
    airports: [
      AirportState(cityId: 'chicago', level: 5, board: board),
      const AirportState(cityId: 'toronto'),
      const AirportState(cityId: 'minneapolis'),
    ],
    planes: [Plane(id: 'p1', modelId: modelId, cityId: 'chicago')],
  );

  test('loading moves a job from the board into a seat or slot', () {
    var state = sparrowAtChicago([
      job('a', 'chicago', 'toronto'),
      cargo('c', 'chicago', 'toronto'),
    ]);
    state = sim.loadJob(state, 'p1', 'a', t0);
    state = sim.loadJob(state, 'p1', 'c', t0);
    expect(state.airport('chicago')!.board, isEmpty);
    expect(state.plane('p1')!.load.map((j) => j.id), ['a', 'c']);
    final load = sim.loading.summary(state, state.plane('p1')!, t0);
    expect(load.seatsUsed, 1);
    expect(load.cargoSlotsUsed, 1);
    expect(load.freeSeats, 1);
    expect(load.freeCargoSlots, 0);
  });

  test('a full plane takes no more of that type', () {
    var state = sparrowAtChicago([
      job('a', 'chicago', 'toronto'),
      job('b', 'chicago', 'toronto'),
      job('c', 'chicago', 'toronto'),
      cargo('x', 'chicago', 'toronto'),
      cargo('y', 'chicago', 'toronto'),
    ]);
    state = sim.loadJob(state, 'p1', 'a', t0);
    state = sim.loadJob(state, 'p1', 'b', t0);
    expect(
      () => sim.loadJob(state, 'p1', 'c', t0),
      refusedWith(RuleError.noRoom),
    );
    state = sim.loadJob(state, 'p1', 'x', t0);
    expect(
      () => sim.loadJob(state, 'p1', 'y', t0),
      refusedWith(RuleError.noRoom),
    );
  });

  test('bulk crates take two slots', () {
    final state = sparrowAtChicago([
      job(
        'b',
        'chicago',
        'toronto',
        type: JobType.cargo,
        kind: JobKind.bulk,
        slots: 2,
      ),
    ]);
    expect(
      () => sim.loadJob(state, 'p1', 'b', t0),
      refusedWith(RuleError.noRoom),
    );
    final hauler = sparrowAtChicago([
      job(
        'b',
        'chicago',
        'toronto',
        type: JobType.cargo,
        kind: JobKind.bulk,
        slots: 2,
      ),
    ], modelId: 'hauler_h2');
    final loaded = sim.loadJob(hauler, 'p1', 'b', t0);
    expect(
      sim.loading.summary(loaded, loaded.plane('p1')!, t0).cargoSlotsUsed,
      2,
    );
  });

  test('fragile jobs need a loadmaster aboard', () {
    final board = [
      job(
        'f',
        'chicago',
        'toronto',
        type: JobType.cargo,
        kind: JobKind.fragile,
      ),
    ];
    expect(
      () => sim.loadJob(sparrowAtChicago(board), 'p1', 'f', t0),
      refusedWith(RuleError.fragileNeedsLoadmaster),
    );
    final withLoadmaster = Simulation(
      Rules(
        sim.rules.config,
        crew: const TestCrew(roles: {'pilot', 'loadmaster'}),
      ),
    );
    expect(
      withLoadmaster
          .loadJob(sparrowAtChicago(board), 'p1', 'f', t0)
          .plane('p1')!
          .load,
      hasLength(1),
    );
  });

  test('only jobs on the board where the plane is parked can be loaded', () {
    final state = sparrowAtChicago([]).updateAirport(
      'toronto',
      (a) => a.copyWith(board: [job('t', 'toronto', 'chicago')]),
    );
    expect(
      () => sim.loadJob(state, 'p1', 't', t0),
      refusedWith(RuleError.jobNotHere),
    );
  });

  test('a plane in the air cannot be loaded', () {
    var state = sparrowAtChicago([
      job('a', 'chicago', 'toronto'),
      job('b', 'chicago', 'toronto'),
    ]);
    state = sim.depart(state, 'p1', ['toronto'], t0);
    state = state.updateAirport(
      'chicago',
      (a) => a.copyWith(board: [job('b', 'chicago', 'toronto')]),
    );
    expect(
      () => sim.loadJob(state, 'p1', 'b', t0),
      refusedWith(RuleError.planeNotParked),
    );
  });

  test('a job can be marked to drop at an owned airport to connect', () {
    final state = sparrowAtChicago([job('a', 'chicago', 'toronto')]);
    final loaded = sim.loadJob(
      state,
      'p1',
      'a',
      t0,
      dropAtCityId: 'minneapolis',
    );
    expect(loaded.plane('p1')!.load.single.dropAtCityId, 'minneapolis');
    expect(
      () => sim.loadJob(state, 'p1', 'a', t0, dropAtCityId: 'denver'),
      refusedWith(RuleError.badDropCity),
    );
    expect(
      () => sim.loadJob(state, 'p1', 'a', t0, dropAtCityId: 'chicago'),
      refusedWith(RuleError.badDropCity),
    );
    // Dropping at its own destination is just a normal delivery.
    final direct = sim.loadJob(state, 'p1', 'a', t0, dropAtCityId: 'toronto');
    expect(direct.plane('p1')!.load.single.dropAtCityId, isNull);
  });

  test('unloading puts a job back on the board; one from elsewhere waits to connect', () {
    var state = sparrowAtChicago([job('a', 'chicago', 'toronto')]);
    state = sim.loadJob(state, 'p1', 'a', t0);
    state = state.updatePlane(
      'p1',
      (p) => p.copyWith(load: [...p.load, job('m', 'minneapolis', 'toronto')]),
    );
    state = sim.unloadJob(state, 'p1', 'a', t0);
    state = sim.unloadJob(state, 'p1', 'm', t0);
    final board = state.airport('chicago')!.board;
    expect(board.firstWhere((j) => j.id == 'a').isConnecting, isFalse);
    expect(board.firstWhere((j) => j.id == 'm').connectingSince, t0);
    expect(state.plane('p1')!.load, isEmpty);
  });

  test('"unload all" lays jobs over until the layover slots are full', () {
    final slots = sim.rules.config.airports.level(5).layoverSlots;
    var state = sparrowAtChicago([
      for (var i = 0; i < slots - 1; i++)
        job('w$i', 'nashville', 'toronto', connectingSince: t0),
    ]);
    state = state.updatePlane(
      'p1',
      (p) => p.copyWith(
        load: [
          job('low', 'minneapolis', 'toronto', payout: 50),
          job('high', 'minneapolis', 'toronto', payout: 300),
        ],
      ),
    );
    expect(sim.loading.freeLayoverSlots(state, 'chicago'), 1);
    state = sim.unloadAll(state, 'p1', t0);
    expect(state.plane('p1')!.load.map((j) => j.id), ['low']);
    final high = state
        .airport('chicago')!
        .board
        .firstWhere((j) => j.id == 'high');
    expect(high.connectingSince, t0);
    expect(
      () => sim.unloadJob(state, 'p1', 'low', t0),
      refusedWith(RuleError.layoverFull),
    );
    expect(
      () => sim.unloadAll(state, 'p1', t0),
      refusedWith(RuleError.layoverFull),
    );
  });

  test('a layover job can be removed from the board, freeing its slot', () {
    final slots = sim.rules.config.airports.level(5).layoverSlots;
    var state = sparrowAtChicago([
      job('own', 'chicago', 'toronto'),
      job('lay', 'nashville', 'toronto', connectingSince: t0),
    ]);
    expect(sim.loading.freeLayoverSlots(state, 'chicago'), slots - 1);
    state = sim.removeLayover(state, 'chicago', 'lay', t0);
    expect(state.airport('chicago')!.board.map((j) => j.id), ['own']);
    expect(sim.loading.freeLayoverSlots(state, 'chicago'), slots);
    expect(
      () => sim.removeLayover(state, 'chicago', 'own', t0),
      refusedWith(RuleError.jobNotHere),
    );
    expect(
      () => sim.removeLayover(state, 'chicago', 'lay', t0),
      refusedWith(RuleError.jobNotHere),
    );
  });

  test('"fill to" loads the best-paying jobs for one city until full', () {
    final state = sim.fillTo(
      sparrowAtChicago([
        job('low', 'chicago', 'toronto', payout: 50),
        job('high', 'chicago', 'toronto', payout: 300),
        job('mid', 'chicago', 'toronto', payout: 200),
        job('other', 'chicago', 'minneapolis', payout: 999),
        cargo('box', 'chicago', 'toronto'),
      ]),
      'p1',
      'toronto',
      t0,
    );
    expect(state.plane('p1')!.load.map((j) => j.id), ['high', 'mid', 'box']);
  });

  test('"fill to" fills every seat when the charter bonus beats a big '
      'booking', () {
    // A Kestrel has 4 seats. Best-first would take the 3-seat group (300)
    // and strand a seat; two pairs fill the plane for a 25% charter.
    final state = sim.fillTo(
      sparrowAtChicago(modelId: 'kestrel_k3', [
        job('group', 'chicago', 'toronto', payout: 300, slots: 3),
        job('pairA', 'chicago', 'toronto', payout: 140, slots: 2),
        job('pairB', 'chicago', 'toronto', payout: 130, slots: 2),
      ]),
      'p1',
      'toronto',
      t0,
    );
    final plane = state.plane('p1')!;
    expect(plane.load.map((j) => j.id).toSet(), {'pairA', 'pairB'});
    expect(sim.loading.summary(state, plane, t0).isCharter, isTrue);
  });

  test('"fill to" skips a charter that would pay less than the best jobs', () {
    final state = sim.fillTo(
      sparrowAtChicago(modelId: 'kestrel_k3', [
        job('vip', 'chicago', 'toronto', payout: 900, slots: 3),
        job('a', 'chicago', 'toronto', payout: 20, slots: 2),
        job('b', 'chicago', 'toronto', payout: 20, slots: 2),
      ]),
      'p1',
      'toronto',
      t0,
    );
    expect(state.plane('p1')!.load.map((j) => j.id), ['vip']);
  });

  test('the best fill goes to the city that pays most, not the busiest', () {
    final state = sparrowAtChicago([
      job('n1', 'chicago', 'minneapolis', payout: 40),
      job('n2', 'chicago', 'minneapolis', payout: 40),
      job('n3', 'chicago', 'minneapolis', payout: 40),
      job('n4', 'chicago', 'minneapolis', payout: 40),
      job('far1', 'chicago', 'toronto', payout: 200),
      job('far2', 'chicago', 'toronto', payout: 180),
      cargo('box', 'chicago', 'toronto', payout: 90),
    ]);
    final plan = sim.loading.bestFill(state, 'p1', t0)!;
    expect(plan.cityId, 'toronto');
    expect(plan.jobs.map((j) => j.id).toSet(), {'far1', 'far2', 'box'});
    expect(plan.charter, isTrue);
    expect(plan.fullHold, isTrue);
    expect(plan.value, ((200 + 180) * 1.25 + 90 * 1.15).round());
  });

  test('the loading sheet shows how close the load is to a charter', () {
    var state = airline(
      airports: [
        AirportState(
          cityId: 'chicago',
          level: 5,
          board: [
            job('a', 'chicago', 'toronto'),
            job('b', 'chicago', 'toronto'),
            job('c', 'chicago', 'toronto'),
            job('d', 'chicago', 'toronto'),
            job('e', 'chicago', 'minneapolis'),
          ],
        ),
        const AirportState(cityId: 'toronto'),
        const AirportState(cityId: 'minneapolis'),
      ],
      planes: const [Plane(id: 'p1', modelId: 'pelican_p4', cityId: 'chicago')],
    );
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      state = sim.loadJob(state, 'p1', id, t0);
    }
    final load = sim.loading.summary(state, state.plane('p1')!, t0);
    expect(load.charterCityId, 'toronto');
    expect(load.charterCount, 4);
    expect(load.seats, 6);
    expect(load.isCharter, isFalse);
  });

  test('a heat wave leaves Large planes 2 seats short', () {
    final heat = WeatherEvent(
      id: 'w1',
      typeId: 'heat_wave',
      regionId: 'north_america',
      cityId: 'chicago',
      forecastAt: t0,
      startsAt: t0,
      endsAt: t0.add(const Duration(hours: 1)),
    );
    final state = airline(
      airports: const [
        AirportState(cityId: 'chicago', level: 5),
        AirportState(cityId: 'toronto', level: 5),
      ],
      planes: const [
        Plane(id: 'p1', modelId: 'albatross_l6', cityId: 'chicago'),
      ],
      weather: [heat],
    );
    expect(sim.loading.summary(state, state.plane('p1')!, t0).seats, 14 - 2);
    final after = sim.loading.summary(
      state,
      state.plane('p1')!,
      t0.add(const Duration(hours: 1)),
    );
    expect(after.seats, 14);
  });
}
