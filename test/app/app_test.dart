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
import 'package:tiny_airways/ui/start_screen.dart';
import 'package:tiny_airways/ui/top_bar.dart';

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
    expect(state.airports, hasLength(2));
    expect(find.byType(TopBar), findsOneWidget);
    expect(find.text('3,000'), findsOneWidget);
    expect(find.text('Airline Lv 1'), findsOneWidget);
    expect(find.text('1 waiting'), findsOneWidget);
    expect(find.text('READY AT GATE'), findsOneWidget);
    await tester.runAsync(container.read(gameSessionProvider.notifier).persist);
    final saved = jsonDecode(storage.primary!) as Map<String, dynamic>;
    expect((saved['state'] as Map)['homeCityId'], 'london');
  });

  testWidgets('the core loop plays end to end: load, route, depart, land', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    GameState state() => container.read(gameSessionProvider);
    final plane = state().planes.single;
    final home = state().homeCityId!;
    final other = state().airports
        .map((a) => a.cityId)
        .firstWhere((id) => id != home);

    // Load: the gate panel's Load button opens the loading sheet.
    await tester.tap(find.byKey(Key('board.load.${plane.id}')));
    await frames(tester);
    expect(find.textContaining('LOAD '), findsWidgets);
    await tester.tap(find.byKey(const Key('load.makeCharter')));
    await frames(tester);
    final loaded = state().plane(plane.id)!.load;
    expect(loaded, isNotEmpty);
    expect(loaded.every((j) => j.destCityId == other), isTrue);

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
    expect(find.text('0 waiting'), findsOneWidget);

    // Land: the clock passes the arrival and the next tick pays out.
    final paidBefore = state().player.money;
    clock.advance(flying.leg!.arriveAt.difference(clock.now()));
    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await frames(tester);
    expect(state().plane(plane.id)!.status, PlaneStatus.parked);
    expect(state().plane(plane.id)!.cityId, other);
    expect(state().player.money, greaterThan(paidBefore));
    expect(find.text('1 waiting'), findsOneWidget);
  });

  testWidgets('time away ends in a welcome-back summary', (tester) async {
    final container = await start(tester);
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    final session = container.read(gameSessionProvider.notifier);
    final plane = container.read(gameSessionProvider).planes.single;
    final other = container.read(gameSessionProvider).airports.last.cityId;
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
    expect(find.textContaining('1 plane waiting'), findsOneWidget);
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
          sim.depart(s0, s.planes.single.id, [s.airports.last.cityId], now),
    );
    await frames(tester);
    expect(find.text('EN ROUTE'), findsOneWidget);
    expect(find.text('No planes at a gate.'), findsOneWidget);
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
