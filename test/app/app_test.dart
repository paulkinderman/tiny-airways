import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/app/app.dart';
import 'package:tiny_airways/app/bootstrap.dart';
import 'package:tiny_airways/app/providers.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/ui/format.dart';
import 'package:tiny_airways/ui/start_screen.dart';
import 'package:tiny_airways/ui/top_bar.dart';
import 'package:tiny_airways/ui/ui_state.dart';

void main() {
  late FakeClock clock;
  late MemorySaveStorage storage;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 10, 30, 20));
    storage = MemorySaveStorage();
  });

  Future<ProviderContainer> start(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final overrides = (await tester.runAsync(
      () => bootstrap(
        configSource: DirectoryConfigSource('assets'),
        clock: clock,
        saveStorage: storage,
      ),
    ))!;
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TinyAirwaysApp(),
      ),
    );
    await tester.pump();
    return container;
  }

  /// The map's game loop never settles, so pump frames by hand.
  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a first launch asks for a home and saves a new game', (
    tester,
  ) async {
    await start(tester);

    expect(find.byType(StartScreen), findsOneWidget);
    expect(find.text('CHOOSE YOUR HOME'), findsOneWidget);
    expect(storage.primary, isNotNull);
  });

  testWidgets('starting an airline opens the map with the top bar', (
    tester,
  ) async {
    final container = await start(tester);

    await tester.tap(find.byKey(const Key('start.region.europe')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start.city.london')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start.city.london')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);

    final state = container.read(gameSessionProvider);
    expect(state.homeCityId, 'london');
    expect(state.airports, hasLength(4));
    expect(state.planes, hasLength(3));
    expect(find.byType(TopBar), findsOneWidget);
    expect(find.text('3,000'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^(Airline )?Lv 1$')), findsOneWidget);
    expect(find.text('3 waiting'), findsOneWidget);
    expect(find.text('READY AT GATE'), findsOneWidget);
    await tester.runAsync(container.read(gameSessionProvider.notifier).persist);
    final saved = jsonDecode(storage.primary!) as Map<String, dynamic>;
    expect((saved['state'] as Map)['homeCityId'], 'london');
  });

  testWidgets('a plane in the air shows its profit and steps to the next', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    GameState state() => container.read(gameSessionProvider);
    final home = state().homeCityId!;
    final dests = [
      for (final a in state().airports)
        if (a.cityId != home) a.cityId,
    ];
    final planes = state().planes.take(2).toList();
    final config = container.read(gameConfigProvider);
    final error = container.read(gameSessionProvider.notifier).act((
      sim,
      s,
      now,
    ) {
      var next = s;
      for (final (i, p) in planes.indexed) {
        next = next.updatePlane(
          p.id,
          (p) => p.copyWith(
            load: [
              Job(
                id: 'fly$i',
                type: config.planes.model(p.modelId).seats > 0
                    ? JobType.passenger
                    : JobType.cargo,
                originCityId: home,
                destCityId: dests[i],
                payout: 400,
                createdAt: now,
              ),
            ],
          ),
        );
        next = sim.depart(next, p.id, [dests[i]], now);
      }
      return next;
    });
    expect(error, isNull);
    await frames(tester);
    final flying = container.read(simulationProvider).flights.inTheAir(state());
    expect(flying, hasLength(2));
    expect(flying.first.tripFuel, greaterThan(0));

    container.read(uiProvider.notifier).open(PlanePanel(flying.first.id));
    await frames(tester);
    expect(find.text('FLIGHT 1 OF 2'), findsOneWidget);
    expect(find.byKey(const Key('plane.profit')), findsOneWidget);
    final trip = container
        .read(simulationProvider)
        .flights
        .tripProfit(state(), flying.first, clock.now());
    expect(trip.expected, greaterThan(0));
    expect(
      tester.widget<Text>(find.byKey(const Key('plane.profit'))).data,
      formatCoins(trip.profit),
    );

    await tester.tap(find.byKey(const Key('plane.nextFlight')));
    await frames(tester);
    expect(
      container.read(uiProvider).panel,
      isA<PlanePanel>().having((p) => p.planeId, 'planeId', flying[1].id),
    );
    expect(find.text('FLIGHT 2 OF 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plane.nextFlight')));
    await frames(tester);
    expect(find.text('FLIGHT 1 OF 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plane.prevFlight')));
    await frames(tester);
    expect(find.text('FLIGHT 2 OF 2'), findsOneWidget);
  });

  testWidgets('layover jobs wear a badge, and "Unload all" lays a plane over', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    GameState state() => container.read(gameSessionProvider);
    final plane = state().planes.first;
    final home = state().homeCityId!;
    final others = [
      for (final a in state().airports)
        if (a.cityId != home) a.cityId,
    ];
    Job waiting(String id, {DateTime? since}) => Job(
      id: id,
      type: JobType.passenger,
      originCityId: others[0],
      destCityId: others[1],
      payout: 9999,
      createdAt: clock.now(),
      connectingSince: since,
    );
    container
        .read(gameSessionProvider.notifier)
        .act(
          (sim, s, now) => s
              .updateAirport(
                home,
                (a) => a.copyWith(
                  board: [
                    ...a.board,
                    waiting('lay1', since: now),
                  ],
                ),
              )
              .updatePlane(
                plane.id,
                (p) => p.copyWith(load: [waiting('ride1')]),
              ),
        );
    await frames(tester);

    await tester.tap(find.byKey(Key('board.load.${plane.id}')));
    await frames(tester, 40);
    final list = find
        .descendant(
          of: find.byKey(const Key('load.list')),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> show(String key, {bool up = false}) async {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        up ? -100 : 100,
        scrollable: list,
      );
      await frames(tester, 2);
    }

    await show('load.layover.lay1');
    expect(find.byKey(const Key('load.layover.lay1')), findsOneWidget);
    expect(find.byKey(const Key('load.layover.ride1')), findsNothing);

    // "Unload all" sits over the jobs aboard, above the board.
    await show('load.unloadAll', up: true);
    await tester.tap(find.byKey(const Key('load.unloadAll')));
    await frames(tester);
    expect(state().plane(plane.id)!.load, isEmpty);
    final board = state().airport(home)!.board;
    expect(board.firstWhere((j) => j.id == 'ride1').isConnecting, isTrue);
    await show('load.layover.ride1');
    expect(find.byKey(const Key('load.layover.ride1')), findsOneWidget);
  });

  testWidgets('a layover job can be removed after a quick confirm', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    GameState state() => container.read(gameSessionProvider);
    final plane = state().planes.first;
    final home = state().homeCityId!;
    final others = [
      for (final a in state().airports)
        if (a.cityId != home) a.cityId,
    ];
    container
        .read(gameSessionProvider.notifier)
        .act(
          (sim, s, now) => s.updateAirport(
            home,
            (a) => a.copyWith(
              board: [
                ...a.board,
                Job(
                  id: 'lay1',
                  type: JobType.passenger,
                  originCityId: others[0],
                  destCityId: others[1],
                  payout: 9999,
                  createdAt: now,
                  connectingSince: now,
                ),
              ],
            ),
          ),
        );
    await frames(tester);

    await tester.tap(find.byKey(Key('board.load.${plane.id}')));
    await frames(tester, 40);
    final list = find
        .descendant(
          of: find.byKey(const Key('load.list')),
          matching: find.byType(Scrollable),
        )
        .first;
    const remove = Key('layover.remove.lay1');
    await tester.scrollUntilVisible(find.byKey(remove), 100, scrollable: list);
    await frames(tester, 2);
    bool onBoard() => state().airport(home)!.board.any((j) => j.id == 'lay1');

    // Keeping it changes nothing.
    await tester.tap(find.byKey(remove));
    await frames(tester, 20);
    expect(find.text('REMOVE LAYOVER?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('layover.remove.cancel')));
    await frames(tester, 20);
    expect(onBoard(), isTrue);

    await tester.tap(find.byKey(remove));
    await frames(tester, 20);
    await tester.tap(find.byKey(const Key('layover.remove.confirm')));
    await frames(tester, 20);
    expect(onBoard(), isFalse);
    expect(find.byKey(remove), findsNothing);
    // The airport's own jobs have no remove button.
    expect(find.byKey(const Key('load.job.lay1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('load.list')),
        matching: find.byIcon(Icons.close),
      ),
      findsNothing,
    );
  });

  testWidgets('the core loop plays end to end: load, route, depart, land', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    GameState state() => container.read(gameSessionProvider);
    final plane = state().planes.first;
    final home = state().homeCityId!;

    // Load: the gate panel's Load button opens the loading sheet.
    await tester.tap(find.byKey(Key('board.load.${plane.id}')));
    await frames(tester);
    expect(find.textContaining('LOAD '), findsWidgets);
    await tester.tap(find.byKey(const Key('load.makeCharter')));
    await frames(tester);
    final loaded = state().plane(plane.id)!.load;
    expect(loaded, isNotEmpty);
    // A charter fills the plane for one of the starting airports.
    final other = loaded.first.destCityId;
    expect(other, isNot(home));
    expect(state().ownsAirport(other), isTrue);
    expect(loaded.every((j) => j.destCityId == other), isTrue);
    // A charter badges every passenger aboard with its bonus.
    final summary = container
        .read(simulationProvider)
        .loading
        .summary(state(), state().plane(plane.id)!, clock.now());
    expect(summary.isCharter, isTrue);
    for (final j in loaded.where((j) => j.type == JobType.passenger)) {
      expect(find.byKey(Key('load.bonus.${j.id}')), findsOneWidget);
    }
    expect(find.text('+25%'), findsWidgets);

    // Route: everything is bound for one airport, so it is picked already.
    await tester.tap(find.byKey(const Key('load.chooseRoute')));
    await frames(tester);
    expect(find.text('CHOOSE ROUTE'), findsOneWidget);
    expect(find.byKey(const Key('route.profit')), findsOneWidget);
    final money = state().player.money;
    await tester.tap(find.byKey(const Key('route.depart')));
    await frames(tester);
    final flying = state().plane(plane.id)!;
    expect(flying.status, PlaneStatus.flying);
    expect(state().player.money, lessThan(money)); // fuel
    expect(find.text('2 waiting'), findsOneWidget);

    // Land: the clock passes the arrival and the next tick pays out.
    final paidBefore = state().player.money;
    clock.advance(flying.leg!.arriveAt.difference(clock.now()));
    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await frames(tester);
    expect(state().plane(plane.id)!.status, PlaneStatus.parked);
    expect(state().plane(plane.id)!.cityId, other);
    expect(state().player.money, greaterThan(paidBefore));
    expect(find.text('3 waiting'), findsOneWidget);
  });

  testWidgets('a route can take several stops, and any can come off', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    GameState state() => container.read(gameSessionProvider);
    RoutePanel route() => container.read(uiProvider).panel as RoutePanel;
    final plane = state().planes.first;
    final [home, second, third, ...] = [
      for (final a in state().airports) a.cityId,
    ];
    expect(plane.cityId, home);
    container.read(uiProvider.notifier).open(RoutePanel(plane.id));
    await frames(tester);

    // Tap the next-stop chips in order: there and on, then back home.
    for (final city in [second, third, home]) {
      await tester.tap(find.byKey(Key('route.option.$city')));
      await frames(tester);
    }
    expect(route().stops, [second, third, home]);
    expect(find.byKey(const Key('route.remove.2')), findsOneWidget);
    expect(find.byKey(const Key('route.pickUp')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Taking the middle stop off joins the legs either side.
    await tester.tap(find.byKey(const Key('route.remove.1')));
    await frames(tester);
    expect(route().stops, [second, home]);

    await tester.tap(find.byKey(const Key('route.pickUp')));
    await frames(tester);
    expect(route().pickUp, isFalse);
    await tester.tap(find.byKey(const Key('route.pickUp')));
    await frames(tester);

    await tester.tap(find.byKey(const Key('route.depart')));
    await frames(tester);
    final flying = state().plane(plane.id)!;
    expect(flying.status, PlaneStatus.flying);
    expect(flying.leg!.toCityId, second);
    expect(flying.remainingStops, [home]);
    expect(flying.pickUpAtStops, isTrue);
  });

  testWidgets('time away ends in a welcome-back summary', (tester) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    final session = container.read(gameSessionProvider.notifier);
    final plane = container.read(gameSessionProvider).planes.first;
    // The third starting airport: its gate is free (the second has a Sparrow).
    final other = container.read(gameSessionProvider).airports[2].cityId;
    session.act((sim, s, now) {
      final loaded = sim.fillTo(s, plane.id, other, now);
      return sim.depart(loaded, plane.id, [other], now);
    });
    await tester.runAsync(session.persist);

    // Close the app, come back two hours later.
    await tester.pumpWidget(const SizedBox());
    clock.advance(const Duration(hours: 2));
    await start(tester);
    await frames(tester, 20);

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.textContaining('While you were away (2h 0m)'), findsOneWidget);
    expect(find.textContaining('Earned'), findsOneWidget);
    expect(find.textContaining('3 planes waiting'), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcomeBack.ok')));
    await frames(tester, 40);
    expect(find.text('WELCOME BACK'), findsNothing);
  });

  testWidgets('the departures board lists planes ready and in the air', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);

    await tester.tap(find.byKey(const Key('nav.fleet')));
    await frames(tester);
    expect(find.text('FLEET'), findsOneWidget);
    expect(find.text('Nothing in the air right now.'), findsOneWidget);

    final session = container.read(gameSessionProvider.notifier);
    final s = container.read(gameSessionProvider);
    session.act(
      (sim, s0, now) =>
          sim.depart(s0, s.planes.first.id, [s.airports[1].cityId], now),
    );
    await frames(tester);
    expect(find.text('EN ROUTE'), findsOneWidget);
    expect(find.text('No planes at a gate.'), findsNothing);
  });

  testWidgets('every change auto-saves with the time it happened', (
    tester,
  ) async {
    final container = await start(tester);
    clock.advance(const Duration(minutes: 3));

    await tester.runAsync(
      () => container
          .read(gameSessionProvider.notifier)
          .update((s) => s.copyWith(player: s.player.copyWith(money: 9000))),
    );
    await tester.pump();

    final saved = jsonDecode(storage.primary!) as Map<String, dynamic>;
    final state = saved['state'] as Map<String, dynamic>;
    expect((state['player'] as Map)['money'], 9000);
    expect(state['lastSeenAt'], '2026-10-30T20:03:00.000Z');
  });

  testWidgets('the start screen and map fit on a small iPhone', (tester) async {
    await start(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(TopBar), findsOneWidget);
  });
}
