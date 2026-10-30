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
import 'package:tiny_airways/logic/simulation.dart';
import 'package:tiny_airways/ui/ui_state.dart';

/// The Crew tab end to end: the free pilot on the roster, hiring from the
/// shelves, assigning, and spending a skill point.
void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(DateTime.utc(2026, 10, 30, 20)));

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
        saveStorage: MemorySaveStorage(),
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
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
    return container;
  }

  testWidgets('the free pilot is on the roster and can learn a skill', (
    tester,
  ) async {
    final container = await start(tester);
    GameState state() => container.read(gameSessionProvider);
    final pilot = state().crew.members.single;

    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    expect(find.text('CREW'), findsOneWidget);
    expect(find.text('1 crew on staff'), findsOneWidget);
    expect(find.byKey(Key('crew.member.${pilot.id}')), findsOneWidget);
    expect(find.text('1 PT'), findsOneWidget);

    await tester.tap(find.byKey(Key('crew.member.${pilot.id}')));
    await frames(tester);
    expect(find.text('1 POINT TO SPEND'), findsOneWidget);
    await tester.tap(find.byKey(const Key('crew.node.range.1')));
    await frames(tester);
    expect(find.text('+5% range'), findsWidgets);
    await tester.tap(find.byKey(const Key('crew.learn')));
    await frames(tester);
    expect(state().crew.member(pilot.id)!.nodes, ['range.1']);
    expect(find.text('0 POINTS TO SPEND'), findsOneWidget);

    // Locked: the next node of another branch needs the one above it.
    await tester.tap(find.byKey(const Key('crew.node.fuel_saver.2')));
    await frames(tester);
    expect(find.text('Learn the skill above it first.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hire a rookie, put staff to work, hire a pilot', (tester) async {
    final container = await start(tester);
    GameState state() => container.read(gameSessionProvider);
    final session = container.read(gameSessionProvider.notifier);
    await tester.runAsync(
      () => session.update(
        (s) => s.copyWith(player: s.player.copyWith(money: 50000)),
      ),
    );

    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('crew.tab.rookies')));
    await frames(tester);
    expect(find.textContaining('New rookies in'), findsOneWidget);
    final sim = container.read(simulationProvider);
    final offers = sim.crew.shelves(state(), clock.now()).rookies;
    expect(offers, hasLength(3));
    final offer = offers.first;
    await tester.tap(find.byKey(Key('crew.hire.${offer.id}')));
    await frames(tester);
    final hired = state().crew.members.last;
    expect(hired.name, offer.member.name);
    expect(state().player.money, 50000 - 2000);

    // The detail opens on the new hire, ready to put to work.
    expect(find.text(hired.name.toUpperCase()), findsOneWidget);
    expect(find.text('Not working anywhere yet.'), findsOneWidget);
    final flight = sim.rules.config.crew.role(hired.roleId).isFlightCrew;
    if (!flight) {
      final home = state().homeCityId!;
      await tester.scrollUntilVisible(
        find.byKey(Key('crew.assign.$home')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.byKey(Key('crew.assign.$home')));
      await frames(tester);
      await tester.tap(find.byKey(Key('crew.assign.$home')));
      await frames(tester);
      expect(state().crew.member(hired.id)!.cityId, home);
    } else {
      // The starting plane is Small: no open seat.
      expect(find.text('No parked plane has a free seat for them.'), findsOne);
    }
    await tester.tap(find.byKey(const Key('crew.back')));
    // Let the "Hired" toast go.
    await tester.pump(const Duration(seconds: 3));
    await frames(tester);

    await tester.tap(find.byKey(const Key('crew.tab.rookies')));
    await frames(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('crew.hirePilot')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('crew.hirePilot')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('crew.hirePilot')));
    await frames(tester);
    expect(state().crew.members.where((m) => m.roleId == 'pilot').length, 2);

    await tester.tap(find.byKey(const Key('crew.tab.veterans')));
    await frames(tester);
    expect(find.text('VETERAN OF THE DAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plane without a pilot shows on the roster', (tester) async {
    final container = await start(tester);
    final session = container.read(gameSessionProvider.notifier);
    final pilot = container.read(gameSessionProvider).crew.members.single;
    session.act((sim, s, now) => sim.unassignCrew(s, pilot.id, now));
    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    final plane = container.read(gameSessionProvider).planes.single;
    expect(find.byKey(Key('crew.short.${plane.id}')), findsOneWidget);
    expect(find.textContaining('needs a pilot to fly'), findsOneWidget);
  });

  testWidgets('a captain with Autopilot can loop a route from the picker', (
    tester,
  ) async {
    final container = await start(tester, size: const Size(320, 568));
    GameState state() => container.read(gameSessionProvider);
    final session = container.read(gameSessionProvider.notifier);
    final pilot = state().crew.members.single;
    final plane = state().planes.single;
    final other = state().airports.last.cityId;
    await tester.runAsync(
      () => session.update(
        (s) => s.copyWith(
          crew: s.crew.updateMember(
            pilot.id,
            (m) => m.copyWith(
              level: 5,
              nodes: [
                'fuel_saver.1',
                'fuel_saver.2',
                'fuel_saver.3',
                'fuel_saver.4',
                'autopilot',
              ],
            ),
          ),
        ),
      ),
    );
    container
        .read(uiProvider.notifier)
        .open(RoutePanel(plane.id, stops: [other]));
    await frames(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('route.autopilot')));
    await frames(tester);
    expect(state().crew.autopilot.keys, [plane.id]);
    expect(state().plane(plane.id)!.status, PlaneStatus.flying);

    container.read(uiProvider.notifier).open(PlanePanel(plane.id));
    await frames(tester);
    expect(find.textContaining('round and round'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plane.stopAutopilot')));
    await frames(tester);
    expect(state().crew.autopilot, isEmpty);
  });

  testWidgets('the crew screens fit on a small iPhone', (tester) async {
    final container = await start(tester, size: const Size(320, 568));
    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    expect(tester.takeException(), isNull);
    for (final tab in ['rookies', 'veterans', 'roster']) {
      await tester.tap(find.byKey(Key('crew.tab.$tab')));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: tab);
    }
    final pilot = container.read(gameSessionProvider).crew.members.single;
    await tester.tap(find.byKey(Key('crew.member.${pilot.id}')));
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
}

/// The map's game loop never settles, so pump frames by hand.
Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
