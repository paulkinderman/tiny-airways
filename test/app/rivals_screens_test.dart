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
import 'package:tiny_airways/ui/rivals_screens.dart';
import 'package:tiny_airways/ui/ui_state.dart';

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(DateTime.utc(2026, 10, 30, 20)));

  /// Starts an airline in Chicago, then makes it level [level] with
  /// [change] applied, and opens [panel].
  Future<ProviderContainer> open(
    WidgetTester tester,
    Panel panel, {
    int level = 10,
    int money = 300000,
    GameState Function(GameState s)? change,
    Size size = const Size(430, 932),
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
    final session = container.read(gameSessionProvider.notifier);
    session.act((sim, s, now) => sim.startAirline(s, 'chicago', now));
    // Not awaited: saving finishes outside the test's fake clock.
    unawaited(
      session.update((s) {
        final up = s.copyWith(
          player: s.player.copyWith(level: level, money: money),
        );
        return change == null ? up : change(up);
      }),
    );
    await tester.pump();
    // Jumping to [level] shows the level-up card and the promotion banner;
    // clear both before opening the screen under test.
    final ok = find.byKey(const Key('levelUp.ok'));
    if (ok.evaluate().isNotEmpty) await tester.tap(ok);
    await tester.pump(FeelLayer.promotionTime);
    await tester.pump(const Duration(milliseconds: 300));
    container.read(uiProvider.notifier).open(panel);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return container;
  }

  GameState share(GameState s, String cityId, Map<String, double> points) {
    final t = clock.now().subtract(const Duration(days: 4));
    return s.copyWith(
      rivals: s.rivals.updateCity(
        cityId,
        (_) => CityShare(points: points, playerHubSince: t, playerLeadSince: t),
      ),
    );
  }

  testWidgets('the rivalry screen shows share, the hub and leader perks', (
    tester,
  ) async {
    await open(
      tester,
      const RivalryPanel('chicago'),
      change: (s) => share(s, 'chicago', {
        playerAirlineId: 46,
        'skysaver': 31,
        'velvet_air': 15,
      }),
    );
    expect(find.text('CHICAGO RIVALRY'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('SkySaver'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('build a terminal'), findsOneWidget);
    expect(find.text('+10%'), findsOneWidget);
  });

  testWidgets('a hub builds a terminal and spends points in its tree', (
    tester,
  ) async {
    final container = await open(
      tester,
      const TerminalPanel('chicago'),
      change: (s) => share(s, 'chicago', {playerAirlineId: 100}),
    );
    await tester.tap(find.byKey(const Key('terminal.build')));
    await tester.pump();
    final state = container.read(gameSessionProvider);
    expect(state.rivals.terminal('chicago'), isNotNull);
    expect(find.text('0 points to spend'), findsOneWidget);

    unawaited(
      container
          .read(gameSessionProvider.notifier)
          .update(
            (s) => s.copyWith(
              rivals: s.rivals.updateTerminal(
                'chicago',
                (t) => t.copyWith(jobs: 40),
              ),
            ),
          ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('terminal.fortress.0')));
    await tester.pump();
    expect(
      container.read(gameSessionProvider).rivals.terminal('chicago')!.nodes,
      {'fortress': 1},
    );
  });

  testWidgets('the leaderboard ranks airlines and changes the difficulty', (
    tester,
  ) async {
    final container = await open(
      tester,
      const LeaderboardPanel(),
      change: (s) => share(s, 'chicago', {'velvet_air': 10}),
    );
    expect(find.text('SEASON LEADERBOARD'), findsOneWidget);
    expect(find.byKey(const Key('leaderboard.row.velvet_air')), findsOneWidget);
    expect(find.byKey(const Key('leaderboard.row.player')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('difficulty.dogfight')),
      100,
    );
    await tester.tap(find.byKey(const Key('difficulty.dogfight')));
    await tester.pump();
    expect(container.read(gameSessionProvider).rivals.difficulty, 'dogfight');
  });

  testWidgets('a rival card and the contract tracker', (tester) async {
    final now = clock.now();
    await open(
      tester,
      const RivalCardPanel('skysaver'),
      change: (s) => s.copyWith(
        rivals: s.rivals.copyWith(
          contracts: [
            Contract(
              id: 'c1',
              cityId: 'chicago',
              jobsToWin: 15,
              prize: 50000,
              startsAt: now,
              endsAt: now.add(const Duration(hours: 3)),
              rivalIds: const ['skysaver'],
              scores: const {playerAirlineId: 9, 'skysaver': 11},
            ),
          ],
        ),
      ),
    );
    expect(find.text('SKYSAVER'), findsOneWidget);
    expect(find.textContaining('Hub Dallas'), findsOneWidget);
    expect(find.text('FRIENDLY RIVALRY'), findsOneWidget);
    expect(find.byType(ContractChip), findsOneWidget);
    expect(find.text('9–11'), findsOneWidget);
    await tester.tap(find.byKey(const Key('topBar.contract')));
    await tester.pump();
    expect(find.text('CHICAGO RIVALRY'), findsOneWidget);
    expect(find.text('CONTRACT · CHICAGO'), findsOneWidget);
  });

  testWidgets('the rival screens fit a small iPhone', (tester) async {
    const small = Size(320, 568);
    for (final panel in const [
      RivalryPanel('chicago'),
      TerminalPanel('chicago'),
      LeaderboardPanel(),
      RivalCardPanel('velvet_air'),
    ]) {
      await open(
        tester,
        panel,
        size: small,
        money: 9000,
        change: (s) => share(s, 'chicago', {
          playerAirlineId: 46,
          'skysaver': 31,
          'velvet_air': 15,
        }),
      );
      expect(tester.takeException(), isNull, reason: '$panel');
    }
  });

  testWidgets('relaunching after a day away catches the rivals up', (
    tester,
  ) async {
    final storage = MemorySaveStorage();
    Future<ProviderContainer> launch() async {
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
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      return container;
    }

    final first = await launch();
    final session = first.read(gameSessionProvider.notifier);
    session.act((sim, s, now) => sim.startAirline(s, 'chicago', now));
    unawaited(
      session.update(
        (s) => share(
          s.copyWith(player: s.player.copyWith(level: 10)),
          'chicago',
          {playerAirlineId: 100},
        ),
      ),
    );
    await tester.runAsync(session.persist);

    await tester.pumpWidget(const SizedBox());
    clock.advance(const Duration(days: 1));
    final second = await launch();
    final state = second.read(gameSessionProvider);
    expect(state.simulatedTo, clock.now());
    expect(state.rivals.lastStepAt, isNotNull);
    expect(state.rivals.cities.length, greaterThan(3));
  });
}
