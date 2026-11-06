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

void main() {
  late FakeClock clock;

  setUp(() => clock = FakeClock(DateTime.utc(2026, 10, 30, 20)));

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

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
    container.read(gameSessionProvider.notifier).act((sim, s, now) {
      final started = sim.startAirline(s, 'chicago', now);
      return started.copyWith(player: started.player.copyWith(money: 100000));
    });
    await frames(tester);
    return container;
  }

  GameState state(ProviderContainer c) => c.read(gameSessionProvider);

  /// An Albatross (14 seats, 8 slots) at Chicago with 7 jobs aboard (8
  /// seats, 1 slot) and a long board across several cities.
  Future<String> bigPlane(WidgetTester tester, ProviderContainer c) async {
    final t = clock.now().subtract(const Duration(hours: 1));
    var n = 0;
    Job job(
      String dest,
      int pay, {
      JobType type = JobType.passenger,
      JobKind kind = JobKind.standard,
      int slots = 1,
      String? id,
    }) => Job(
      id: id ?? 'j${n++}',
      type: type,
      kind: kind,
      slots: slots,
      originCityId: 'chicago',
      destCityId: dest,
      payout: pay,
      createdAt: t,
    );
    const cargo = JobType.cargo;
    c.read(gameSessionProvider.notifier).act((sim, s, now) {
      final id = s.planes.firstWhere((p) => p.cityId == 'chicago').id;
      return s
          .updatePlane(
            id,
            (p) => Plane(
              id: p.id,
              modelId: 'albatross_l6',
              cityId: 'chicago',
              load: [
                job('nashville', 192, slots: 3),
                job('nashville', 144, kind: JobKind.vip),
                job('nashville', 70),
                job('nashville', 66),
                job('denver', 131),
                job('denver', 129),
                job('toronto', 88, type: cargo),
              ],
            ),
          )
          .updateAirport(
            'chicago',
            (a) => a.copyWith(
              board: [
                job('nashville', 208, slots: 4, id: 'g4'),
                job('nashville', 150, kind: JobKind.vip),
                job('nashville', 132, slots: 3),
                job(
                  'nashville',
                  110,
                  type: cargo,
                  kind: JobKind.bulk,
                  slots: 2,
                ),
                job('nashville', 410, slots: 8, id: 'g8'),
                job('nashville', 72),
                job('nashville', 70),
                job('denver', 132, slots: 2),
                job('denver', 128),
                job('denver', 120),
                job('denver', 95, type: cargo),
                job('denver', 90, type: cargo),
                job('denver', 88),
                job('toronto', 99, type: cargo),
                job('toronto', 80, type: cargo),
                job('minneapolis', 120),
                job('minneapolis', 60),
                job('atlanta', 150, slots: 2),
                job('new_orleans', 210, slots: 2),
                job(
                  'boston',
                  140,
                  type: cargo,
                  kind: JobKind.fragile,
                  id: 'fragile',
                ),
              ],
            ),
          );
    });
    final id = state(c).planes.firstWhere((p) => p.cityId == 'chicago').id;
    c.read(uiProvider.notifier).open(LoadingPanel(id));
    await frames(tester);
    return id;
  }

  testWidgets('a big load folds by city, and a city opens to de-plane', (
    tester,
  ) async {
    final c = await start(tester);
    final id = await bigPlane(tester, c);
    expect(find.byKey(const Key('load.aboardCity.nashville')), findsOneWidget);
    expect(
      find.textContaining('×4 · 6 seats', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const Key('load.aboard.j0')), findsNothing);
    await tester.tap(find.byKey(const Key('load.aboardCity.nashville')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('load.pay.j0')));
    await frames(tester);
    expect(state(c).plane(id)!.load.map((j) => j.id), isNot(contains('j0')));
    expect(find.text('6 to Nashville · 6 seats free'), findsNothing);
  });

  testWidgets('waiting jobs group by city; too-big and never-fit jobs show', (
    tester,
  ) async {
    final c = await start(tester);
    await bigPlane(tester, c);
    // The city most of the load goes to comes first and fills the seats.
    expect(find.byKey(const Key('load.group.nashville')), findsOneWidget);
    expect(find.byKey(const Key('load.fill.nashville')), findsOneWidget);
    expect(find.text('6 to Nashville · 6 seats free'), findsOneWidget);
    // A group of 8 doesn't fit in 6 free seats: it says so and still
    // offers the seats when tapped.
    expect(find.textContaining('too big'), findsOneWidget);
    expect(find.textContaining('52/seat'), findsOneWidget);
    // The fragile crate needs a loadmaster: listed apart at the bottom.
    await tester.scrollUntilVisible(
      find.byKey(const Key('load.job.fragile')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('load.list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining("CAN'T GO ON THIS PLANE"), findsOneWidget);
  });

  testWidgets('Fits hides jobs too big for the room left', (tester) async {
    final c = await start(tester);
    await bigPlane(tester, c);
    expect(find.byKey(const Key('load.job.g8')), findsOneWidget);
    await tester.tap(find.byKey(const Key('load.filter.fits')));
    await frames(tester);
    expect(find.byKey(const Key('load.job.g8')), findsNothing);
    expect(find.byKey(const Key('load.job.g4')), findsOneWidget);
  });

  testWidgets('the city picker filters, and the filter survives a refresh', (
    tester,
  ) async {
    final c = await start(tester);
    final id = await bigPlane(tester, c);
    await tester.tap(find.byKey(const Key('load.cityPicker')));
    await frames(tester, 30);
    expect(find.text('GOING TO'), findsOneWidget);
    await tester.tap(find.byKey(const Key('load.pickSort.name')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('load.pick.denver')));
    await frames(tester, 30);
    expect(find.byKey(const Key('load.group.denver')), findsOneWidget);
    expect(find.byKey(const Key('load.group.nashville')), findsNothing);
    expect(find.byKey(const Key('load.fillTo')), findsOneWidget);

    // A paid refresh brings new jobs; the filter stays on Denver.
    await tester.tap(find.byKey(const Key('load.refresh')));
    await frames(tester, 30);
    expect(
      find.descendant(
        of: find.byKey(const Key('load.cityPicker')),
        matching: find.textContaining('Denver'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('load.group.nashville')), findsNothing);

    // Leaving the sheet clears it.
    c.read(uiProvider.notifier).open(const NoPanel());
    await frames(tester, 30);
    c.read(uiProvider.notifier).open(LoadingPanel(id));
    await frames(tester, 30);
    expect(
      find.descendant(
        of: find.byKey(const Key('load.cityPicker')),
        matching: find.textContaining('All cities'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the busy loading sheet fits a small iPhone', (tester) async {
    final c = await start(tester, size: const Size(320, 568));
    await bigPlane(tester, c);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('load.cityPicker')));
    await frames(tester, 30);
    expect(tester.takeException(), isNull);
  });
}
