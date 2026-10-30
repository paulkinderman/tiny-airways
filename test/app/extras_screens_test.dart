import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/app/app.dart';
import 'package:tiny_airways/app/bootstrap.dart';
import 'package:tiny_airways/app/providers.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/save/cloud_sync.dart';
import 'package:tiny_airways/core/save/save_repository.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/ui/challenges_screen.dart';
import 'package:tiny_airways/ui/cloud_conflict_screen.dart';
import 'package:tiny_airways/ui/feel_layer.dart';

void main() {
  late FakeClock clock;
  late MemorySaveStorage storage;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 10, 30, 20));
    storage = MemorySaveStorage();
  });

  GameState airline({int level = 3, int money = 5000, ExtrasState? extras}) {
    final now = clock.now();
    return GameState(
      createdAt: now,
      lastSeenAt: now,
      player: PlayerState(money: money, xp: 0, level: level),
      homeCityId: 'chicago',
      airports: const [
        AirportState(cityId: 'chicago', level: 3),
        AirportState(cityId: 'toronto', level: 2),
      ],
      planes: const [Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'chicago')],
      nextId: 10,
      simulatedTo: now,
      boardRotation: now.millisecondsSinceEpoch ~/ (5 * 60 * 1000),
      extras: extras ?? ExtrasState.empty,
    );
  }

  Future<ProviderContainer> start(
    WidgetTester tester, {
    GameState? saved,
    CloudSaveStore? cloud,
    TextStore? marker,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (saved != null) {
      storage.primary = SaveRepository(
        storage: storage,
        clock: clock,
      ).encode(saved);
    }
    final overrides = (await tester.runAsync(
      () => bootstrap(
        configSource: DirectoryConfigSource('assets'),
        clock: clock,
        saveStorage: storage,
        cloud: cloud,
        syncMarker: marker,
      ),
    ))!;
    final container = ProviderContainer(
      overrides: [
        ...overrides,
        utcOffsetProvider.overrideWithValue(Duration.zero),
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

  testWidgets('the level opens the challenge board; a milestone is claimed', (
    tester,
  ) async {
    final container = await start(tester, saved: airline());
    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await frames(tester);
    // The board rolled on the first tick, and level 3 is a milestone.
    expect(container.read(gameSessionProvider).extras.dailies, hasLength(3));
    // (The trophy badge itself needs more room than the test font gives.)
    expect(
      container
          .read(simulationProvider)
          .challenges
          .claimable(container.read(gameSessionProvider)),
      greaterThan(0),
    );

    await tester.tap(find.byKey(const Key('topBar.challenges')));
    await frames(tester);
    expect(find.byType(ChallengesScreen), findsOneWidget);
    expect(find.text('DAILY'), findsOneWidget);
    expect(find.byKey(const Key('challenges.daily.0')), findsOneWidget);
    expect(find.byKey(const Key('challenges.weekly')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('challenges.tab.milestones')));
    await frames(tester);
    final money = container.read(gameSessionProvider).player.money;
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('milestone.level_3')),
        matching: find.text('CLAIM'),
      ),
    );
    await frames(tester);
    final state = container.read(gameSessionProvider);
    expect(state.extras.isClaimed('level_3'), isTrue);
    expect(state.player.money, greaterThan(money));

    // The milestone's XP levels the airline up and earns a new title: close
    // the level-up card and let the promotion banner go by.
    await tester.tap(find.byKey(const Key('levelUp.ok')));
    await tester.pump(FeelLayer.promotionTime);
    await frames(tester);
    await tester.tap(find.byKey(const Key('sheet.back')));
    await frames(tester);
    expect(find.byType(ChallengesScreen), findsNothing);
  });

  testWidgets('a full set of parts builds a special plane', (tester) async {
    final container = await start(
      tester,
      saved: airline(
        level: 10,
        extras: const ExtrasState(
          parts: {
            'barnstormer.engine': 2,
            'barnstormer.wings': 1,
            'barnstormer.fuselage': 1,
            'barnstormer.tail': 1,
          },
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.byKey(const Key('topBar.challenges')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('challenges.tab.parts')));
    await frames(tester);

    final money = container.read(gameSessionProvider).player.money;
    await tester.tap(find.byKey(const Key('parts.barnstormer.engine.sell')));
    await frames(tester);
    expect(container.read(gameSessionProvider).player.money, money + 2500);

    await tester.tap(find.byKey(const Key('parts.barnstormer.build')));
    await frames(tester);
    final state = container.read(gameSessionProvider);
    expect(state.planes.map((p) => p.modelId), contains('barnstormer'));
    expect(find.text('BUILT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cloud conflict asks which airline to keep', (tester) async {
    final repo = SaveRepository(storage: MemorySaveStorage(), clock: clock);
    final cloud = MemoryCloudSaveStore(
      text: repo.encode(airline(money: 99000, level: 12)),
    );
    final container = await start(
      tester,
      saved: airline(money: 4000),
      cloud: cloud,
    );
    await frames(tester);
    expect(find.byType(CloudConflictScreen), findsOneWidget);
    expect(find.text('99,000'), findsOneWidget);
    expect(find.text('4,000'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('conflict.keepCloud')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await frames(tester);
    expect(find.byType(CloudConflictScreen), findsNothing);
    expect(container.read(gameSessionProvider).player.money, 99000);
  });

  testWidgets('a new install takes the iCloud airline without asking', (
    tester,
  ) async {
    final repo = SaveRepository(storage: MemorySaveStorage(), clock: clock);
    final cloud = MemoryCloudSaveStore(
      text: repo.encode(airline(money: 77000)),
    );
    final container = await start(tester, cloud: cloud);
    await frames(tester);
    expect(find.byType(CloudConflictScreen), findsNothing);
    expect(container.read(gameSessionProvider).player.money, 77000);
  });
}
