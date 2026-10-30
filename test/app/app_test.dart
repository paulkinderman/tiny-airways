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
import 'package:tiny_airways/ui/home_screen.dart';

void main() {
  late FakeClock clock;
  late MemorySaveStorage storage;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 10, 30, 20));
    storage = MemorySaveStorage();
  });

  Future<ProviderContainer> start(WidgetTester tester) async {
    final overrides = (await tester.runAsync(
      () => bootstrap(
        configSource: DirectoryConfigSource('assets/config'),
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
    await tester.pump();
    return container;
  }

  testWidgets('a first launch starts a new airline and saves it', (
    tester,
  ) async {
    await start(tester);

    expect(find.text('Tiny Airways'), findsOneWidget);
    expect(find.text('2,500 coins'), findsOneWidget);
    expect(find.text('Lv 1'), findsOneWidget);
    expect(storage.primary, isNotNull);
  });

  testWidgets('a returning player gets their saved airline back', (
    tester,
  ) async {
    storage.primary = jsonEncode({
      'version': 1,
      'savedAt': '2026-10-30T19:00:00.000Z',
      'state': {
        'createdAt': '2026-10-29T09:15:00.000Z',
        'lastSeenAt': '2026-10-30T19:00:00.000Z',
        'player': {'money': 12500, 'xp': 340, 'level': 4},
      },
    });
    await start(tester);

    expect(find.text('12,500 coins'), findsOneWidget);
    expect(find.text('Lv 4'), findsOneWidget);
  });

  testWidgets('every change auto-saves with the time it happened', (
    tester,
  ) async {
    final container = await start(tester);
    clock.advance(const Duration(minutes: 3));

    await tester.runAsync(
      () => container
          .read(gameSessionProvider.notifier)
          .update((s) => s.copyWith(player: s.player.copyWith(money: 9000))),
    );
    await tester.pump();

    expect(find.text('9,000 coins'), findsOneWidget);
    final saved = jsonDecode(storage.primary!) as Map<String, dynamic>;
    final state = saved['state'] as Map<String, dynamic>;
    expect((state['player'] as Map)['money'], 9000);
    expect(state['lastSeenAt'], '2026-10-30T20:03:00.000Z');
  });

  test('formatCoins groups thousands', () {
    expect(formatCoins(0), '0');
    expect(formatCoins(999), '999');
    expect(formatCoins(1000), '1,000');
    expect(formatCoins(1234567), '1,234,567');
    expect(formatCoins(-2500), '-2,500');
  });

  testWidgets('the top bar fits on a small iPhone', (tester) async {
    tester.view.physicalSize = const Size(320, 568) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await start(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(TopBar), findsOneWidget);
  });
}
