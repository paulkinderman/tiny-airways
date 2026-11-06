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
    final pilot = state().crew.members.first;

    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('crew.tab.roster')));
    await frames(tester);
    expect(find.text('CREW'), findsOneWidget);
    expect(find.text('3 crew · 3/4 pilots'), findsOneWidget);
    expect(find.byKey(Key('crew.member.${pilot.id}')), findsOneWidget);
    // Each starting pilot has a point: an UPGRADE pill in "Ready to
    // upgrade" and on their plane, and a count on the Crew tab.
    expect(find.byKey(const Key('crew.ready')), findsOneWidget);
    expect(find.byKey(Key('crew.ready.${pilot.id}')), findsOneWidget);
    expect(find.byKey(Key('crew.upgrade.${pilot.id}')), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('nav.crew.badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('crew.ready.${pilot.id}')));
    await frames(tester);
    expect(find.text('1 POINT TO SPEND'), findsOneWidget);
    expect(find.byKey(const Key('crew.treeBanner')), findsOneWidget);
    expect(find.byKey(const Key('crew.nodeReady.range.1')), findsOneWidget);
    expect(find.byKey(const Key('crew.nodeReady.range.2')), findsNothing);
    await tester.tap(find.byKey(const Key('crew.node.range.1')));
    await frames(tester);
    expect(find.text('+5% range'), findsWidgets);
    await tester.tap(find.byKey(const Key('crew.learn')));
    await frames(tester);
    expect(state().crew.member(pilot.id)!.nodes, ['range.1']);
    expect(find.text('0 POINTS TO SPEND'), findsOneWidget);
    expect(find.byKey(const Key('crew.treeBanner')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('nav.crew.badge')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

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
    expect(state().crew.members.where((m) => m.roleId == 'pilot').length, 4);
    expect(find.byKey(const Key('crew.tab.veterans')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plane without a pilot shows on the roster', (tester) async {
    final container = await start(tester);
    final session = container.read(gameSessionProvider.notifier);
    final pilot = container.read(gameSessionProvider).crew.members.first;
    session.act((sim, s, now) => sim.unassignCrew(s, pilot.id, now));
    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('crew.tab.roster')));
    await frames(tester);
    final plane = container.read(gameSessionProvider).plane(pilot.planeId!)!;
    expect(find.byKey(Key('crew.short.${plane.id}')), findsOneWidget);
    expect(find.textContaining('needs a pilot to fly'), findsOneWidget);

    // Parked in the hangar, it isn't flying, so the roster stops warning.
    session.act((sim, s, now) => sim.storePlane(s, plane.id, now));
    await frames(tester);
    expect(find.byKey(Key('crew.short.${plane.id}')), findsNothing);
  });

  testWidgets('the Planes view seats a pilot from an empty seat', (
    tester,
  ) async {
    final container = await start(tester);
    GameState state() => container.read(gameSessionProvider);
    final session = container.read(gameSessionProvider.notifier);
    final pilot = state().crew.members.first;
    final planeId = pilot.planeId!;
    session.act((sim, s, now) => sim.unassignCrew(s, pilot.id, now));
    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    // Planes is the Crew tab's first view; the grounded plane is on top.
    expect(find.byKey(Key('crew.planeSeats.$planeId')), findsOneWidget);
    expect(find.textContaining("1 plane can't fly"), findsOneWidget);
    await tester.tap(find.byKey(Key('crew.seat.$planeId.0')));
    await frames(tester);
    expect(find.byKey(Key('crew.seatPick.${pilot.id}')), findsOneWidget);
    await tester.tap(find.byKey(Key('crew.seatPick.${pilot.id}')));
    await frames(tester);
    expect(state().crew.member(pilot.id)!.planeId, planeId);
    expect(find.byKey(Key('crew.seatPick.${pilot.id}')), findsNothing);
  });

  testWidgets('planes in the hangar stay out of the Planes view', (
    tester,
  ) async {
    final container = await start(tester);
    final session = container.read(gameSessionProvider.notifier);
    final planeId = container.read(gameSessionProvider).planes.first.id;
    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    expect(find.byKey(Key('crew.planeSeats.$planeId')), findsOneWidget);
    session.act((sim, s, now) {
      final named = sim.renamePlane(s, planeId, 'Mothball', now);
      return sim.storePlane(named, planeId, now);
    });
    await frames(tester);
    expect(find.byKey(Key('crew.planeSeats.$planeId')), findsNothing);

    // The roster's Planes section leaves it out too.
    await tester.tap(find.byKey(const Key('crew.tab.roster')));
    await frames(tester);
    expect(find.text('Mothball'), findsNothing);
  });

  testWidgets('auto-fill seats idle pilots, and a seat can be swapped', (
    tester,
  ) async {
    final container = await start(tester);
    GameState state() => container.read(gameSessionProvider);
    final session = container.read(gameSessionProvider.notifier);
    final pilots = [
      for (final m in state().crew.members)
        if (m.roleId == 'pilot' && m.planeId != null) m,
    ];
    final a = pilots[0];
    session.act((sim, s, now) => sim.unassignCrew(s, a.id, now));
    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('crew.seats.autoFill')));
    await frames(tester);
    expect(state().crew.member(a.id)!.planeId, a.planeId);

    if (pilots.length > 1) {
      final b = pilots[1];
      await tester.tap(find.byKey(Key('crew.seat.${a.planeId}.0')));
      await frames(tester);
      await tester.tap(find.byKey(Key('crew.swap.${b.id}')));
      await frames(tester);
      expect(state().crew.member(a.id)!.planeId, b.planeId);
      expect(state().crew.member(b.id)!.planeId, a.planeId);
    }
  });

  testWidgets('a captain with Autopilot can loop a route from the picker', (
    tester,
  ) async {
    final container = await start(tester, size: const Size(320, 568));
    GameState state() => container.read(gameSessionProvider);
    final session = container.read(gameSessionProvider.notifier);
    final pilot = state().crew.members.first;
    final plane = state().plane(pilot.planeId!)!;
    final other = state().airports[1].cityId;
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

  testWidgets('a level-up toast opens the pilot\'s skill tree', (tester) async {
    final container = await start(tester);
    GameState state() => container.read(gameSessionProvider);
    final pilot = state().crew.members.first;
    final session = container.read(gameSessionProvider.notifier);
    await tester.runAsync(
      () => session.update(
        (s) => s.copyWith(
          crew: s.crew.updateMember(pilot.id, (m) => m.copyWith(level: 3)),
        ),
      ),
    );
    await frames(tester);
    expect(find.byKey(const Key('crew.levelToast')), findsOneWidget);
    expect(find.textContaining('${pilot.name} reached Lv 3'), findsOneWidget);
    await tester.tap(find.text('Upgrade'));
    await frames(tester, 30);
    expect(container.read(uiProvider).tab, HomeTab.crew);
    expect(find.byKey(const Key('crew.treeBanner')), findsOneWidget);
    expect(find.text('3 POINTS TO SPEND'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the crew screens fit on a small iPhone', (tester) async {
    final container = await start(tester, size: const Size(320, 568));
    await tester.tap(find.byKey(const Key('nav.crew')));
    await frames(tester);
    expect(tester.takeException(), isNull);
    for (final tab in ['rookies', 'planes', 'roster']) {
      await tester.tap(find.byKey(Key('crew.tab.$tab')));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: tab);
    }
    final pilot = container.read(gameSessionProvider).crew.members.first;
    await tester.tap(find.byKey(Key('crew.ready.${pilot.id}')));
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
