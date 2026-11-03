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
import 'package:tiny_airways/ui/ui_state.dart';
import 'package:tiny_airways/ui/walkthrough.dart';

void main() {
  late FakeClock clock;
  late MemorySaveStorage storage;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 10, 30, 20));
    storage = MemorySaveStorage();
  });

  Future<ProviderContainer> launch(
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
    final container = ProviderContainer(
      overrides: [
        ...overrides,
        walkthroughEnabledProvider.overrideWithValue(true),
      ],
    );
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

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> startAirline(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('start.startAirline')));
    await frames(tester);
  }

  /// The save, once pending writes finish.
  Future<Map<String, dynamic>> savedState(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.runAsync(container.read(gameSessionProvider.notifier).persist);
    return (jsonDecode(storage.primary!) as Map<String, dynamic>)['state']
        as Map<String, dynamic>;
  }

  testWidgets('a new airline gets a tour of every main screen, once', (
    tester,
  ) async {
    final container = await launch(tester);
    expect(find.byKey(const Key('tour')), findsNothing); // not on the picker
    await startAirline(tester);

    expect(find.byKey(const Key('tour')), findsOneWidget);
    final tabs = <HomeTab>[];
    for (var i = 0; i < tourSteps.length; i++) {
      expect(
        tester.widget<Text>(find.byKey(const Key('tour.title'))).data,
        tourSteps[i].title.toUpperCase(),
      );
      tabs.add(container.read(uiProvider).tab);
      await tester.tap(find.byKey(const Key('tour.next')));
      await frames(tester);
    }
    expect(tabs, [for (final s in tourSteps) s.tab]);
    expect(tabs.toSet(), HomeTab.values.toSet()); // every tab is visited

    expect(find.byKey(const Key('tour')), findsNothing);
    expect(container.read(uiProvider).tab, HomeTab.map);
    expect(container.read(gameSessionProvider).tourSeen, isTrue);
    expect((await savedState(tester, container))['tourSeen'], isTrue);

    // Taps reach the game again.
    expect(find.text('READY AT GATE'), findsOneWidget);
  });

  testWidgets('skip ends the tour and it stays gone after a relaunch', (
    tester,
  ) async {
    final container = await launch(tester);
    await startAirline(tester);
    await tester.tap(find.byKey(const Key('tour.next')));
    await tester.tap(find.byKey(const Key('tour.next')));
    await tester.tap(find.byKey(const Key('tour.next')));
    await frames(tester);
    expect(container.read(uiProvider).tab, HomeTab.fleet);

    await tester.tap(find.byKey(const Key('tour.skip')));
    await frames(tester);
    expect(find.byKey(const Key('tour')), findsNothing);
    expect(container.read(uiProvider).tab, HomeTab.map);
    expect((await savedState(tester, container))['tourSeen'], isTrue);

    await tester.pumpWidget(const SizedBox());
    await launch(tester);
    await frames(tester);
    expect(find.byKey(const Key('topBar.money')), findsOneWidget);
    expect(find.byKey(const Key('tour')), findsNothing);
  });

  testWidgets('back returns to the previous card', (tester) async {
    final container = await launch(tester);
    await startAirline(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('tour.next')));
      await frames(tester, 2);
    }
    expect(container.read(uiProvider).tab, HomeTab.crew);
    await tester.tap(find.byKey(const Key('tour.back')));
    await frames(tester);
    expect(container.read(uiProvider).tab, HomeTab.fleet);
    expect(
      tester.widget<Text>(find.byKey(const Key('tour.title'))).data,
      'FLEET',
    );
  });

  testWidgets('every card fits a 320-point-wide iPhone', (tester) async {
    await launch(tester, size: const Size(320, 568));
    await startAirline(tester);
    for (var i = 0; i < tourSteps.length; i++) {
      expect(tester.takeException(), isNull, reason: 'step $i');
      await tester.tap(find.byKey(const Key('tour.next')));
      await frames(tester);
    }
    expect(find.byKey(const Key('tour')), findsNothing);
  });

  testWidgets('reset airline starts over, walkthrough included', (
    tester,
  ) async {
    final container = await launch(tester);
    await startAirline(tester);
    await tester.tap(find.byKey(const Key('tour.skip')));
    await frames(tester);
    expect((await savedState(tester, container))['homeCityId'], isNotNull);

    Future<void> openReset() async {
      await tester.tap(find.byKey(const Key('topBar.airline')));
      await frames(tester, 30);
      await tester.scrollUntilVisible(
        find.byKey(const Key('airline.reset')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('airline.reset')));
      await frames(tester, 30);
    }

    // Cancel keeps the airline.
    await openReset();
    await tester.tap(find.byKey(const Key('reset.cancel')));
    await frames(tester, 30);
    expect(container.read(gameSessionProvider).hasStarted, isTrue);

    expect(find.byKey(const Key('airline.reset')), findsOneWidget);
    await tester.tapAt(const Offset(20, 60)); // above the sheet: closes it
    await frames(tester, 30);

    await openReset();
    await tester.tap(find.byKey(const Key('reset.confirm')));
    await frames(tester);
    final state = container.read(gameSessionProvider);
    expect(state.hasStarted, isFalse);
    expect(state.tourSeen, isFalse);
    expect(state.planes, isEmpty);
    final saved = await savedState(tester, container);
    expect(saved['homeCityId'], isNull);
    expect(saved['tourSeen'], isFalse);

    // Back on the picker; starting again brings the tour back.
    expect(find.byKey(const Key('start.startAirline')), findsOneWidget);
    await startAirline(tester);
    expect(find.byKey(const Key('tour')), findsOneWidget);
    expect(container.read(uiProvider).tab, HomeTab.map);
  });

  test('saves from before the tour read as not seen yet', () {
    final state = GameState.newGame(
      now: DateTime.utc(2026, 10, 30),
      startingMoney: 3000,
    ).copyWith(tourSeen: true);
    final json = state.toJson();
    expect(GameState.fromJson(json).tourSeen, isTrue);
    json.remove('tourSeen');
    expect(GameState.fromJson(json).tourSeen, isFalse);
  });
}
