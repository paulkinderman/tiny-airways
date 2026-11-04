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

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(DateTime.utc(2026, 10, 30, 20)));

  /// Launches the app and starts an airline in Chicago with [money].
  Future<ProviderContainer> start(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    int money = 100000,
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
    container.read(gameSessionProvider.notifier).act((sim, s, now) {
      final started = sim.startAirline(s, 'chicago', now);
      return started.copyWith(player: started.player.copyWith(money: money));
    });
    await frames(tester);
    return container;
  }

  GameState state(ProviderContainer c) => c.read(gameSessionProvider);

  testWidgets('the hangar sells any number of planes; pilots are capped', (
    tester,
  ) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('nav.hangar')));
    await frames(tester);
    expect(find.text('HANGAR'), findsOneWidget);
    expect(find.text('3 planes · 3 of 4 pilots'), findsOneWidget);
    expect(find.text('LV 3'), findsWidgets); // Kestrel K3 is locked

    await tester.tap(find.byKey(const Key('hangar.buy.hauler_h2')));
    await frames(tester);
    expect(state(c).planes, hasLength(4));
    expect(state(c).planes.last.modelId, 'hauler_h2');
    expect(find.textContaining('is waiting at '), findsOneWidget);
    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await frames(tester);
    expect(find.text('4 planes · 4 of 4 pilots'), findsOneWidget);

    // A fifth plane is still for sale; it waits parked for a pilot.
    await tester.ensureVisible(find.byKey(const Key('hangar.buy.hauler_h2')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('hangar.buy.hauler_h2')));
    await frames(tester);
    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await frames(tester);
    expect(state(c).planes, hasLength(5));
    expect(find.text('5 planes · 4 of 4 pilots'), findsOneWidget);
    final waiting = state(c).planes.last.id;
    expect(state(c).crew.onPlane(waiting), isEmpty);

    // A pilot license opens a slot and its free pilot turns up.
    // (The delivery card covers the tab bar, so switch tabs directly.)
    c.read(uiProvider.notifier).showTab(HomeTab.crew);
    await frames(tester);
    await tester.tap(find.byKey(const Key('crew.tab.rookies')));
    await frames(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('crew.buyPilotLicense')),
      200,
    );
    await frames(tester);
    expect(find.text('PILOTS FULL'), findsOneWidget);
    await tester.tap(find.byKey(const Key('crew.buyPilotLicense')));
    await frames(tester);
    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await frames(tester);
    expect(state(c).player.pilotLicenses, 1);
    expect(state(c).crew.onPlane(waiting).single.roleId, 'pilot');
    expect(find.text('5 crew · 5/5 pilots'), findsOneWidget);
  });

  testWidgets('a plane can be renamed from the hangar list', (tester) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('nav.hangar')));
    await frames(tester);
    final id = state(c).planes.first.id;
    await tester.scrollUntilVisible(
      find.byKey(Key('hangar.rename.$id')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('hangar.list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(Key('hangar.rename.$id')));
    await frames(tester);
    await tester.enterText(find.byKey(const Key('rename.field')), 'Night Owl');
    await tester.tap(find.byKey(const Key('rename.save')));
    await frames(tester);
    expect(state(c).plane(id)!.nickname, 'Night Owl');
    expect(find.textContaining('Night Owl'), findsWidgets);
  });

  testWidgets('a plane can be upgraded and renamed', (tester) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('nav.hangar')));
    await frames(tester);
    final id = state(c).planes.first.id;
    await tester.scrollUntilVisible(
      find.byKey(Key('hangar.plane.$id')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('hangar.list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(Key('hangar.plane.$id')));
    await frames(tester, 30);

    await tester.tap(find.byKey(const Key('plane.upgrade.speed')));
    await frames(tester);
    expect(state(c).plane(id)!.upgrades.speed, 1);

    await tester.enterText(find.byKey(const Key('plane.name')), 'Blue Jay');
    await tester.tap(find.byKey(const Key('plane.rename')));
    await frames(tester);
    expect(state(c).plane(id)!.nickname, 'Blue Jay');
  });

  /// Parks a Sparrow at Chicago with both seats taken and a Toronto
  /// passenger waiting, then opens its loading sheet.
  Future<String> fullSparrow(WidgetTester tester, ProviderContainer c) async {
    final t = clock.now();
    Job pax(String id) => Job(
      id: id,
      type: JobType.passenger,
      originCityId: 'chicago',
      destCityId: 'toronto',
      payout: 100,
      // Old enough that no rival has first look at it.
      createdAt: t.subtract(const Duration(hours: 1)),
    );
    c.read(gameSessionProvider.notifier).act((sim, s, now) {
      final id = s.planes.firstWhere((p) => p.cityId == 'chicago').id;
      return s
          .updatePlane(
            id,
            (p) => Plane(
              id: p.id,
              modelId: 'sparrow_s1',
              cityId: 'chicago',
              load: [pax('seat1'), pax('seat2')],
            ),
          )
          .updateAirport('chicago', (a) => a.copyWith(board: [pax('extra')]));
    });
    final id = state(c).planes.firstWhere((p) => p.cityId == 'chicago').id;
    c.read(uiProvider.notifier).open(LoadingPanel(id));
    await frames(tester);
    return id;
  }

  testWidgets('the loading sheet upgrades a plane in place', (tester) async {
    final c = await start(tester);
    final id = await fullSparrow(tester, c);

    // The header's Upgrade button opens the tray.
    await tester.tap(find.byKey(const Key('load.upgrade')));
    await frames(tester);
    expect(find.byKey(const Key('load.tray')), findsOneWidget);
    await tester.tap(find.byKey(const Key('load.tray.upgrade.capacity')));
    await frames(tester);
    expect(state(c).plane(id)!.upgrades.capacity, 1);
    expect(find.text('Seats 2/3'), findsOneWidget);

    // The header button closes and reopens it; so does its close arrow.
    await tester.tap(find.byKey(const Key('load.upgrade')));
    await frames(tester);
    expect(find.byKey(const Key('load.tray')), findsNothing);
    await tester.tap(find.byKey(const Key('load.upgrade')));
    await frames(tester);
    expect(find.byKey(const Key('load.tray')), findsOneWidget);
    await tester.tap(find.byKey(const Key('load.tray.close')));
    await frames(tester);
    expect(find.byKey(const Key('load.tray')), findsNothing);
  });

  testWidgets('a full plane offers to add a seat and load the job', (
    tester,
  ) async {
    final c = await start(tester);
    final id = await fullSparrow(tester, c);
    final money = state(c).player.money;

    // Not now leaves everything as it was.
    await tester.tap(find.byKey(const Key('load.job.extra')));
    await frames(tester);
    expect(find.text('SEATS ARE FULL'), findsOneWidget);
    await tester.tap(find.byKey(const Key('load.upgradeAndLoad.cancel')));
    await frames(tester);
    expect(state(c).plane(id)!.load, hasLength(2));
    expect(state(c).player.money, money);

    await tester.tap(find.byKey(const Key('load.job.extra')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('load.upgradeAndLoad')));
    await frames(tester);
    final plane = state(c).plane(id)!;
    expect(plane.upgrades.capacity, 1);
    expect(plane.load.map((j) => j.id), contains('extra'));
    expect(state(c).player.money, lessThan(money));
    expect(find.text('Seats 3/3'), findsOneWidget);
  });

  testWidgets('the airport shop buys the nearest city and shows licenses', (
    tester,
  ) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('nav.airports')));
    await frames(tester);
    expect(find.text('AIRPORTS'), findsOneWidget);
    final owned = state(c).airports.length;
    final buy = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('shop.buy.'),
    );
    final first = tester.widget(buy.first).key! as ValueKey<String>;
    final cityId = first.value.substring('shop.buy.'.length);
    await tester.tap(buy.first);
    await frames(tester);
    expect(state(c).airports, hasLength(owned + 1));
    expect(state(c).airport(cityId)!.board, isNotEmpty);

    await tester.tap(find.byKey(const Key('shop.view.regions')));
    await frames(tester);
    expect(
      find.text('Your next license unlocks at airline Lv 5.'),
      findsOneWidget,
    );

    c
        .read(gameSessionProvider.notifier)
        .act((sim, s, now) => s.copyWith(player: s.player.copyWith(level: 5)));
    await frames(tester, 30);
    // Dismiss the level-up card.
    await tester.tap(find.byKey(const Key('levelUp.ok')));
    await frames(tester, 30);
    await tester.tap(find.byKey(const Key('shop.license.europe')));
    await frames(tester);
    expect(state(c).player.licenses, ['europe']);
  });

  testWidgets('the airport panel upgrades the airport and its paths', (
    tester,
  ) async {
    final c = await start(tester);
    c.read(uiProvider.notifier).open(const AirportPanel('chicago'));
    await frames(tester, 30);
    expect(find.text('Lv 3: 6 gates, 15 jobs, Medium planes'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('airport.upgrade')));
    await tester.tap(find.byKey(const Key('airport.upgrade')));
    await frames(tester);
    expect(state(c).airport('chicago')!.level, 3);

    await tester.ensureVisible(find.byKey(const Key('airport.paths')));
    await tester.tap(find.byKey(const Key('airport.paths')));
    await frames(tester, 30);
    expect(find.text('0 / 12'), findsOneWidget);
    await tester.tap(find.byKey(const Key('paths.buy.cargo')));
    await frames(tester);
    expect(state(c).airport('chicago')!.tier('cargo'), 1);
    expect(find.text('1 / 12'), findsOneWidget);
    await tester.tap(find.byKey(const Key('paths.sell.cargo')));
    await frames(tester);
    expect(state(c).airport('chicago')!.tier('cargo'), 0);
  });

  testWidgets('a city card buys its airport', (tester) async {
    final c = await start(tester);
    final cityId = [
      'denver',
      'dallas',
    ].firstWhere((id) => !state(c).ownsAirport(id));
    c.read(uiProvider.notifier).open(CityPanel(cityId));
    await frames(tester, 30);
    await tester.tap(find.byKey(const Key('city.buy')));
    await frames(tester, 30);
    expect(state(c).ownsAirport(cityId), isTrue);
    expect(c.read(uiProvider).panel, isA<AirportPanel>());
  });

  testWidgets('levelling up shows what it unlocked', (tester) async {
    final c = await start(tester);
    c
        .read(gameSessionProvider.notifier)
        .act((sim, s, now) => Economy(sim.rules).grantXp(s, 100 + 303 + 580));
    await frames(tester, 30);
    expect(state(c).player.level, greaterThanOrEqualTo(3));
    expect(find.textContaining('LEVEL '), findsOneWidget);
    expect(find.text('Kestrel K3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('levelUp.ok')));
    await frames(tester, 30);

    await tester.tap(find.byKey(const Key('topBar.airline')));
    await frames(tester, 30);
    expect(find.text('COMING UP'), findsOneWidget);
    expect(find.text('NETWORK'), findsOneWidget);
  });

  testWidgets('the growth screens fit a small iPhone', (tester) async {
    await start(tester, size: const Size(320, 568), money: 10);
    for (final tab in ['hangar', 'airports']) {
      await tester.tap(find.byKey(Key('nav.$tab')));
      await frames(tester);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const Key('shop.view.regions')));
    await frames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loading sheet\'s upgrade tray fits a small iPhone', (
    tester,
  ) async {
    final c = await start(tester, size: const Size(320, 568));
    await fullSparrow(tester, c);
    await tester.tap(find.byKey(const Key('load.upgrade')));
    await frames(tester);
    expect(find.byKey(const Key('load.tray')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The map's game loop never settles, so pump frames by hand.
Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
