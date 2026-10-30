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

  testWidgets('the hangar sells planes and expands', (tester) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('nav.hangar')));
    await frames(tester);
    expect(find.text('HANGAR'), findsOneWidget);
    expect(find.text('1 of 3 slots used'), findsOneWidget);
    expect(find.text('LV 3'), findsWidgets); // Kestrel K3 is locked

    await tester.tap(find.byKey(const Key('hangar.buy.hauler_h2')));
    await frames(tester);
    expect(state(c).planes, hasLength(2));
    expect(state(c).planes.last.modelId, 'hauler_h2');
    expect(find.text('Hauler H2 is waiting at Chicago.'), findsOneWidget);
    expect(find.text('2 of 3 slots used'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('hangar.expand')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('hangar.list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const Key('hangar.expand')));
    await frames(tester);
    expect(find.text('2 of 4 slots used'), findsOneWidget);
  });

  testWidgets('a plane can be upgraded and renamed', (tester) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('nav.hangar')));
    await frames(tester);
    final id = state(c).planes.single.id;
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
    expect(
      find.text('Lv 3: 3 gates, 12 jobs, Medium planes, +1 upgrade point'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('airport.upgrade')));
    await tester.tap(find.byKey(const Key('airport.upgrade')));
    await frames(tester);
    expect(state(c).airport('chicago')!.level, 3);

    await tester.ensureVisible(find.byKey(const Key('airport.paths')));
    await tester.tap(find.byKey(const Key('airport.paths')));
    await frames(tester, 30);
    expect(find.text('0 / 3 USED'), findsOneWidget);
    await tester.tap(find.byKey(const Key('paths.buy.cargo')));
    await frames(tester);
    expect(state(c).airport('chicago')!.tier('cargo'), 1);
    expect(find.text('1 / 3 USED'), findsOneWidget);
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
}

/// The map's game loop never settles, so pump frames by hand.
Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
