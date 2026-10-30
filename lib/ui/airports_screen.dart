import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'format.dart';
import 'growth_sheets.dart';
import 'theme.dart';
import 'widgets.dart';

enum _ShopView { cities, regions, yours }

/// The Airports tab: cities to buy (nearest the network first), region
/// licenses, and the airports already owned.
class AirportsScreen extends ConsumerStatefulWidget {
  const AirportsScreen({required this.onShowAirport, super.key});

  /// Opens an owned airport's panel on the map.
  final void Function(String cityId) onShowAirport;

  @override
  ConsumerState<AirportsScreen> createState() => _AirportsScreenState();
}

class _AirportsScreenState extends ConsumerState<AirportsScreen> {
  _ShopView _view = _ShopView.cities;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameSessionProvider);
    final sim = ref.read(simulationProvider);
    final world = sim.rules.world;
    final home = state.homeCityId == null
        ? null
        : world.region(world.city(state.homeCityId!).regionId).name;

    return ColoredBox(
      color: Board.ground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: 'Airports',
            subtitle:
                '${state.airports.length} owned'
                '${home == null ? '' : ' · $home'}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (v, label) in [
                  (_ShopView.cities, 'Cities'),
                  (_ShopView.regions, 'Regions'),
                  (_ShopView.yours, 'Yours'),
                ])
                  BoardChip(
                    key: Key('shop.view.${v.name}'),
                    label: label,
                    selected: _view == v,
                    onTap: () => setState(() => _view = v),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('shop.list'),
              padding: const EdgeInsets.all(16),
              children: switch (_view) {
                _ShopView.cities => _cities(state, sim),
                _ShopView.regions => _regions(state, sim),
                _ShopView.yours => _owned(state, sim),
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _cities(GameState state, Simulation sim) {
    final growth = sim.growth;
    final world = sim.rules.world;
    final licensed = growth.licensedRegions(state);
    final options = [
      for (final c in world.cities)
        if (!state.ownsAirport(c.id) && licensed.contains(c.regionId))
          (city: c, near: growth.nearestOwned(state, c.id)),
    ]..sort((a, b) => (a.near?.km ?? 0).compareTo(b.near?.km ?? 0));
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Sorted by distance from your network',
          style: TextStyle(color: Board.muted, fontSize: 13),
        ),
      ),
      BoardSection(
        title: 'Cities',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Every city in your regions is yours. Buy a license for '
                  'a new region.',
                  style: TextStyle(color: Board.muted),
                ),
              ),
            for (final o in options)
              _CityRow(
                cityId: o.city.id,
                subtitle:
                    'Size ${o.city.size}'
                    '${o.near == null ? '' : ' · ${formatKm(o.near!.km)} from '
                              '${world.city(o.near!.cityId).name}'}',
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _regions(GameState state, Simulation sim) {
    final growth = sim.growth;
    final world = sim.rules.world;
    final next = growth.nextLicense(state);
    final licensed = growth.licensedRegions(state);
    final bonus = sim.rules.config.world.crossRegionPayPct.round();
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          next == null
              ? 'Every license is bought.'
              : state.player.level < next.airlineLevel
              ? 'Your next license unlocks at airline Lv ${next.airlineLevel}.'
              : 'Your next license costs ${formatCoins(next.cost)}.',
          style: const TextStyle(color: Board.muted, fontSize: 13),
        ),
      ),
      BoardSection(
        title: 'Regions',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in world.regions)
              Builder(
                builder: (context) {
                  final owned = licensed.contains(r.id);
                  final problem = growth.licenseProblem(state, r.id);
                  return GrowthRow(
                    key: Key('shop.region.${r.id}'),
                    leading: Icon(
                      owned ? Icons.public : Icons.lock_outline,
                      color: owned ? Board.amber : Board.muted,
                      size: 22,
                    ),
                    title: r.name,
                    subtitle:
                        '${world.citiesIn(r.id).length} cities · '
                        '${owned ? 'licensed' : 'flights across regions pay +$bonus%'}',
                    button: owned
                        ? null
                        : AmberButton(
                            key: Key('shop.license.${r.id}'),
                            mono: true,
                            height: 34,
                            label: next == null
                                ? 'Sold out'
                                : problem == RuleError.levelTooLow
                                ? 'Lv ${next.airlineLevel}'
                                : priceLabel(problem, next.cost),
                            onPressed: problem == null
                                ? () {
                                    if (actOrExplain(
                                      context,
                                      ref,
                                      (sim, s, now) =>
                                          sim.buyLicense(s, r.id, now),
                                    )) {
                                      showToast(
                                        context,
                                        '${r.name} is open. Buy an airport '
                                        'there to fly in.',
                                      );
                                    }
                                  }
                                : null,
                          ),
                  );
                },
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _owned(GameState state, Simulation sim) {
    final world = sim.rules.world;
    final growth = sim.growth;
    final config = sim.rules.config;
    final airports = [...state.airports]
      ..sort((a, b) {
        final byLevel = b.level.compareTo(a.level);
        return byLevel != 0
            ? byLevel
            : world.city(a.cityId).name.compareTo(world.city(b.cityId).name);
      });
    return [
      BoardSection(
        title: 'Your airports',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in airports)
              GrowthRow(
                key: Key('shop.owned.${a.cityId}'),
                leading: Icon(
                  Icons.local_airport,
                  size: 22,
                  color: growth.topPath(a) == null
                      ? Board.amber
                      : pathColor(growth.topPath(a)!),
                ),
                title: world.city(a.cityId).name,
                subtitle: [
                  'Lv ${a.level}',
                  if (state.homeCityId == a.cityId) 'Home',
                  for (final p in config.airports.paths)
                    if (a.tier(p.id) > 0) '${p.name} ${a.tier(p.id)}',
                  if (growth.freePoints(a) > 0)
                    '${growth.freePoints(a)} free '
                        '${growth.freePoints(a) == 1 ? 'point' : 'points'}',
                ].join(' · '),
                onTap: () => widget.onShowAirport(a.cityId),
                button: const Icon(Icons.chevron_right, color: Board.muted),
              ),
          ],
        ),
      ),
    ];
  }
}

/// A city for sale, with its price button.
class _CityRow extends ConsumerWidget {
  const _CityRow({required this.cityId, required this.subtitle});

  final String cityId;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final growth = ref.read(simulationProvider).growth;
    final city = ref.read(gameConfigProvider).world.city(cityId);
    final price = growth.airportPrice(state, cityId);
    final problem = growth.buyAirportProblem(state, cityId);
    return GrowthRow(
      key: Key('shop.city.$cityId'),
      title: city.name,
      subtitle: subtitle,
      button: AmberButton(
        key: Key('shop.buy.$cityId'),
        mono: true,
        height: 34,
        label: problem == null
            ? formatCoins(price)
            : priceLabel(problem, price),
        onPressed: problem == null
            ? () {
                if (buyAirport(context, ref, cityId)) {
                  showToast(context, '${city.name} is now one of yours.');
                }
              }
            : null,
      ),
    );
  }
}

/// Buys [cityId]'s airport, explaining a refusal.
bool buyAirport(BuildContext context, WidgetRef ref, String cityId) =>
    actOrExplain(context, ref, (sim, s, now) => sim.buyAirport(s, cityId, now));
