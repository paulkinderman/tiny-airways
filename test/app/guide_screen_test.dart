import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/app/app.dart';
import 'package:tiny_airways/app/bootstrap.dart';
import 'package:tiny_airways/app/providers.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/ui/ui_state.dart';

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(DateTime.utc(2026, 10, 30, 20)));

  /// Launches the app and starts an airline in Chicago.
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
    container
        .read(gameSessionProvider.notifier)
        .act((sim, s, now) => sim.startAirline(s, 'chicago', now));
    await frames(tester);
    return container;
  }

  testWidgets('the map\'s "?" opens the guide; tabs and search work', (
    tester,
  ) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('map.guide')));
    await frames(tester);
    expect(c.read(uiProvider).panel, isA<GuidePanel>());
    expect(find.text('GAME GUIDE'), findsOneWidget);
    // It opens on planes and airports.
    expect(find.byKey(const Key('guide.entry.Medium planes')), findsOneWidget);
    expect(
      find.textContaining('Need airport level 3 or higher to land.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('guide.tab.weather')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('guide.tab.weather')));
    await frames(tester);
    expect(
      find.byKey(const Key('guide.entry.Thunderstorm (airport closure)')),
      findsOneWidget,
    );

    // Search looks through every section.
    await tester.enterText(find.byKey(const Key('guide.search')), 'pilot cap');
    await frames(tester);
    expect(find.text('PILOTS & LICENSES'), findsOneWidget);
    expect(find.byKey(const Key('guide.entry.Pilot cap')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('guide.search')), 'zzzz');
    await frames(tester);
    expect(find.byKey(const Key('guide.noResults')), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide.clear')));
    await frames(tester);
    expect(find.byKey(const Key('guide.tab.weather')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sheet.back')));
    await frames(tester);
    expect(c.read(uiProvider).panel, isA<NoPanel>());
    expect(find.byKey(const Key('map.guide')), findsOneWidget);
  });

  testWidgets('the airline sheet opens the guide on its unlocks', (
    tester,
  ) async {
    final c = await start(tester);
    await tester.tap(find.byKey(const Key('topBar.airline')));
    await frames(tester, 40);
    await tester.tap(find.byKey(const Key('airline.guide')));
    await frames(tester, 40);
    expect(c.read(uiProvider).panel, isA<GuidePanel>());
    expect(find.text('UNLOCKS BY LEVEL'), findsOneWidget);
    expect(find.byKey(const Key('guide.entry.Level 1')), findsOneWidget);
    expect(find.byKey(const Key('airline.guide')), findsNothing);
  });

  testWidgets('the "?" hides while a panel is open', (tester) async {
    final c = await start(tester);
    c.read(uiProvider.notifier).open(const AirportPanel('chicago'));
    await frames(tester);
    expect(find.byKey(const Key('map.guide')), findsNothing);
  });

  testWidgets('every guide section fits a 320-point-wide iPhone', (
    tester,
  ) async {
    await start(tester, size: const Size(320, 568));
    await tester.tap(find.byKey(const Key('map.guide')));
    await frames(tester);
    for (final id in [
      'planes',
      'levels',
      'pilots',
      'upgrades',
      'jobs',
      'weather',
      'glossary',
    ]) {
      await tester.ensureVisible(find.byKey(Key('guide.tab.$id')));
      await frames(tester);
      await tester.tap(find.byKey(Key('guide.tab.$id')));
      await frames(tester);
      final list = find.descendant(
        of: find.byKey(const Key('guide.list')),
        matching: find.byType(Scrollable),
      );
      await tester.drag(list.first, const Offset(0, -3000));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: id);
    }
  });
}

/// The map's game loop never settles, so pump frames by hand.
Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}
