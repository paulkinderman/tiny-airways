import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/app/bootstrap.dart';
import 'package:tiny_airways/app/providers.dart';
import 'package:tiny_airways/app/sounds.dart';
import 'package:tiny_airways/core/clock/clock.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/save/save_storage.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/ui/feel_layer.dart';
import 'package:tiny_airways/ui/ui_state.dart';

class RecordingSounds implements Sounds {
  final played = <Sfx>[];

  @override
  void play(Sfx sfx) => played.add(sfx);
}

void main() {
  late RecordingSounds sounds;

  Future<ProviderContainer> start(WidgetTester tester) async {
    sounds = RecordingSounds();
    final overrides = (await tester.runAsync(
      () => bootstrap(
        configSource: DirectoryConfigSource('assets'),
        clock: FakeClock(DateTime.utc(2026, 10, 30, 20)),
        saveStorage: MemorySaveStorage(),
      ),
    ))!;
    final container = ProviderContainer(
      overrides: [...overrides, soundsProvider.overrideWithValue(sounds)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FeelLayer(child: SizedBox.expand())),
      ),
    );
    return container;
  }

  // Not awaited, so the banner's timers run on the test's fake clock.
  void setLevel(ProviderContainer container, int level) => unawaited(
    container
        .read(gameSessionProvider.notifier)
        .update((s) => s.copyWith(player: s.player.copyWith(level: level))),
  );

  testWidgets('a new title flips in on the promotion banner', (tester) async {
    final container = await start(tester);
    expect(find.byKey(const Key('promotion.banner')), findsNothing);

    // Level 2 is still a Paper Plane: a chime, no banner.
    setLevel(container, 2);
    await tester.pump();
    expect(sounds.played, [Sfx.level]);
    expect(find.byKey(const Key('promotion.banner')), findsNothing);

    setLevel(container, 3);
    await tester.pump();
    expect(sounds.played.last, Sfx.promotion);
    expect(find.byKey(const Key('promotion.banner')), findsOneWidget);
    expect(find.text('PROMOTED · AIRLINE LV 3'), findsOneWidget);
    expect(find.text('PAPER PLANE'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('KITE RUNNER'), findsOneWidget);

    await tester.pump(FeelLayer.promotionTime);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('promotion.banner')), findsNothing);
  });

  testWidgets('take-offs, landings and the Fleet tab make sounds', (
    tester,
  ) async {
    final container = await start(tester);
    const plane = Plane(id: 'p1', modelId: 'sparrow_s1', cityId: 'london');
    final session = container.read(gameSessionProvider.notifier);
    await tester.runAsync(
      () => session.update((s) => s.copyWith(planes: const [plane])),
    );
    await tester.runAsync(
      () => session.update(
        (s) =>
            s.updatePlane('p1', (p) => p.copyWith(status: PlaneStatus.flying)),
      ),
    );
    await tester.runAsync(
      () => session.update(
        (s) =>
            s.updatePlane('p1', (p) => p.copyWith(status: PlaneStatus.parked)),
      ),
    );
    container.read(uiProvider.notifier).showTab(HomeTab.fleet);
    await tester.pump();

    expect(sounds.played, [Sfx.takeoff, Sfx.coins, Sfx.flap]);
  });
}
