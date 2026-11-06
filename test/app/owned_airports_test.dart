import 'dart:async';

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
import 'package:tiny_airways/ui/feel_layer.dart';
import 'package:tiny_airways/ui/ui_state.dart';

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(DateTime.utc(2026, 10, 30, 20)));

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Chicago (home, 3 planes parked, a comfortable lead), Toronto (Velvet
  /// Air leads) and Minneapolis (a close lead), at airline Lv [level].
  Future<ProviderContainer> start(WidgetTester tester, {int level = 10}) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
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
    final session = container.read(gameSessionProvider.notifier);
    session.act((sim, s, now) {
      final next = sim.startAirline(s, 'chicago', now);
      return next.copyWith(
        player: next.player.copyWith(level: level, money: 10000000),
      );
    });
    CityShare share(Map<String, double> points) => CityShare(points: points);
    unawaited(
      session.update(
        (s) => s.copyWith(
          airports: [
            s.airport('chicago')!,
            const AirportState(cityId: 'toronto'),
            const AirportState(cityId: 'minneapolis'),
          ],
          planes: [for (final p in s.planes) p.copyWith(cityId: 'chicago')],
          rivals: s.rivals
              .updateCity(
                'chicago',
                (_) => share({'player': 70, 'skysaver': 30}),
              )
              .updateCity(
                'toronto',
                (_) => share({'player': 20, 'velvet_air': 60}),
              )
              .updateCity(
                'minneapolis',
                (_) => share({'player': 50, 'skysaver': 46}),
              ),
        ),
      ),
    );
    await tester.pump();
    final ok = find.byKey(const Key('levelUp.ok'));
    if (ok.evaluate().isNotEmpty) await tester.tap(ok);
    await tester.pump(FeelLayer.promotionTime);
    await tester.pump(const Duration(milliseconds: 300));
    await frames(tester);
    return container;
  }

  double top(WidgetTester tester, String cityId) =>
      tester.getTopLeft(find.byKey(Key('shop.owned.$cityId'))).dy;

  testWidgets('Yours sums up the network and sorts by what needs you', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byKey(const Key('nav.airports')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('shop.view.yours')));
    await frames(tester);

    final summary = find.byKey(const Key('shop.owned.summary'));
    expect(
      find.descendant(of: summary, matching: find.text('YOU LEAD')),
      findsOneWidget,
    );
    expect(find.text('Velvet Air leads · 75%'), findsOneWidget);
    expect(find.text('you 25%'), findsOneWidget);
    expect(find.textContaining('· close'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);

    // Needs you: the rival-led city, then three idle planes, then the
    // close race.
    expect(top(tester, 'toronto'), lessThan(top(tester, 'chicago')));
    expect(top(tester, 'chicago'), lessThan(top(tester, 'minneapolis')));

    await tester.ensureVisible(find.byKey(const Key('shop.sort.name')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('shop.sort.name')));
    await frames(tester);
    expect(top(tester, 'chicago'), lessThan(top(tester, 'minneapolis')));
    expect(top(tester, 'minneapolis'), lessThan(top(tester, 'toronto')));
  });

  testWidgets('the airport panel steps through owned airports in order', (
    tester,
  ) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('nav.airports')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('shop.view.yours')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('shop.owned.toronto')));
    await frames(tester, 30);
    AirportPanel panel() => c.read(uiProvider).panel as AirportPanel;
    expect(panel().cityId, 'toronto');
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('airport.next')));
    await frames(tester, 30);
    expect(panel().cityId, 'chicago');
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('airport.prev')));
    await frames(tester, 30);
    await tester.tap(find.byKey(const Key('airport.prev')));
    await frames(tester, 30);
    expect(panel().cityId, 'minneapolis', reason: 'wraps around');

    await tester.tap(find.byKey(const Key('airport.strip.chicago')));
    await frames(tester, 30);
    expect(panel().cityId, 'chicago');
  });

  testWidgets('before city share unlocks, Yours shows planes and jobs', (
    tester,
  ) async {
    await start(tester, level: 3);
    await tester.tap(find.byKey(const Key('nav.airports')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('shop.view.yours')));
    await frames(tester);
    expect(find.text('PLANES IN'), findsOneWidget);
    expect(find.text('City share unlocks at Lv 5'), findsOneWidget);
    expect(find.byKey(const Key('shop.sort.share')), findsNothing);
  });

  testWidgets('selling an airport asks first, pays half and closes it', (
    tester,
  ) async {
    final c = await start(tester);
    final ui = c.read(uiProvider.notifier);
    ui.open(const AirportPanel('chicago'));
    await frames(tester, 30);
    await tester.ensureVisible(find.byKey(const Key('airport.sell')));
    expect(find.text('Your home airport can\'t be sold'), findsOneWidget);
    expect(find.byKey(const Key('airport.sell.button')), findsNothing);

    ui.open(const AirportPanel('toronto'));
    await frames(tester, 30);
    final money = c.read(gameSessionProvider).player.money;
    final button = find.byKey(const Key('airport.sell.button'));
    await tester.ensureVisible(button);
    await frames(tester);
    await tester.tap(button);
    await frames(tester);
    expect(find.byKey(const Key('sell.dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sell.cancel')));
    await frames(tester);
    expect(c.read(gameSessionProvider).ownsAirport('toronto'), isTrue);

    await tester.tap(button);
    await frames(tester);
    await tester.tap(find.byKey(const Key('sell.confirm')));
    await frames(tester);
    final s = c.read(gameSessionProvider);
    expect(s.ownsAirport('toronto'), isFalse);
    // Toronto is size 4, bought as the third airport: 6,000 x 1.2 / 2.
    expect(s.player.money, greaterThanOrEqualTo(money + 3600));
    expect(c.read(uiProvider).panel, isNot(isA<AirportPanel>()));
  });
}
