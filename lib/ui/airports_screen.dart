import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../logic/simulation.dart';
import 'airport_panel.dart' show weatherIcon;
import 'format.dart';
import 'growth_sheets.dart';
import 'owned_airports.dart';
import 'rivals_screens.dart';
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
                                        kind: ToastKind.done,
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

  List<Widget> _owned(GameState state, Simulation sim) => [
    _OwnedAirports(onShowAirport: widget.onShowAirport),
  ];
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
                  showToast(
                    context,
                    '${city.name} is now one of yours.',
                    kind: ToastKind.done,
                  );
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

/// The "Yours" view: a summary of the network, a sort, and a card per
/// owned airport with its share race, gates, jobs and weather.
class _OwnedAirports extends ConsumerWidget {
  const _OwnedAirports({required this.onShowAirport});

  final void Function(String cityId) onShowAirport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameSessionProvider);
    final sort = ref.watch(airportSortProvider);
    final sim = ref.read(simulationProvider);
    final shareOn = sim.rivals.shareOn(state);
    return TickBuilder(
      builder: (context, now) {
        final airports = ownedAirports(state, sim, now, sort);
        int count(bool Function(OwnedAirportInfo) test) =>
            airports.where(test).length;
        final tiles = shareOn
            ? [
                ('Owned', '${airports.length}', Board.ink),
                (
                  'You lead',
                  '${count((a) => a.standing == ShareStanding.lead || a.standing == ShareStanding.leadClose)}',
                  Board.good,
                ),
                (
                  'Rival leads',
                  '${count((a) => a.standing == ShareStanding.rivalLeads)}',
                  Board.bad,
                ),
                ('Hubs', '${count((a) => a.isHub)}', Board.signature),
              ]
            : [
                ('Owned', '${airports.length}', Board.ink),
                (
                  'Planes in',
                  '${airports.fold(0, (n, a) => n + a.parked)}',
                  Board.ink,
                ),
                (
                  'Jobs',
                  '${airports.fold(0, (n, a) => n + a.jobs)}',
                  Board.ink,
                ),
              ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              key: const Key('shop.owned.summary'),
              children: [
                for (final (i, t) in tiles.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _SummaryTile(t.$1, t.$2, t.$3)),
                ],
              ],
            ),
            if (!shareOn) ...[
              const SizedBox(height: 8),
              Text(
                'City share unlocks at Lv '
                '${sim.rules.config.progression.featureUnlockLevel['cityShare']}',
                style: const TextStyle(color: Board.muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Sort',
                    style: TextStyle(color: Board.muted, fontSize: 13),
                  ),
                  for (final s in AirportSort.values)
                    if (s != AirportSort.share || shareOn) ...[
                      const SizedBox(width: 6),
                      BoardChip(
                        key: Key('shop.sort.${s.name}'),
                        label: s.label,
                        dense: true,
                        selected: sort == s,
                        onTap: () =>
                            ref.read(airportSortProvider.notifier).set(s),
                      ),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final a in airports) ...[
              _OwnedCard(
                info: a,
                now: now,
                onTap: () => onShowAirport(a.cityId),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    decoration: BoxDecoration(
      color: Board.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Board.line),
    ),
    child: Column(
      children: [
        Text(value, style: Board.flapStyle(size: 18).copyWith(color: color)),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 0.5,
            color: Board.muted,
          ),
        ),
      ],
    ),
  );
}

/// One owned airport: name and badges, the share race, and its gates, jobs
/// and weather.
class _OwnedCard extends ConsumerWidget {
  const _OwnedCard({
    required this.info,
    required this.now,
    required this.onTap,
  });

  final OwnedAirportInfo info;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.read(gameConfigProvider);
    final a = info;
    final paths = [
      for (final p in config.airports.paths)
        if (a.airport.tier(p.id) > 0) '${p.name} ${a.airport.tier(p.id)}',
    ];
    final (shareText, shareColor) = switch (a.standing) {
      ShareStanding.off => ('', Board.muted),
      ShareStanding.open => ('Nobody leads yet', Board.muted),
      ShareStanding.lead => ('You lead · ${_pct(a.myShare)}', Board.good),
      ShareStanding.leadClose => (
        'You lead · ${_pct(a.myShare)} · close',
        Board.amber,
      ),
      ShareStanding.rivalLeads => (
        '${airlineName(config, a.leaderId!)} leads · '
            '${_pct(a.share.fraction(a.leaderId!))}',
        airlineColor(config, a.leaderId!),
      ),
    };
    final String? shareRight = a.standing == ShareStanding.off
        ? null
        : a.terminalPoints > 0
        ? 'Terminal · ${a.terminalPoints} '
              '${a.terminalPoints == 1 ? 'pt' : 'pts'} to spend'
        : a.hubIn != null
        ? 'hub in ${formatCountdown(a.hubIn!)}'
        : a.standing == ShareStanding.rivalLeads
        ? 'you ${_pct(a.myShare)}'
        : null;
    final weather = a.weather;
    final weatherName = weather == null
        ? null
        : config.weather.events.firstWhere((t) => t.id == weather.typeId).name;
    const meta = TextStyle(fontSize: 12, color: Board.muted);
    const bold = TextStyle(
      fontSize: 12,
      color: Board.ink,
      fontWeight: FontWeight.w600,
    );
    return Material(
      color: Board.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: a.standing == ShareStanding.rivalLeads
              ? Board.bad.withValues(alpha: 0.45)
              : Board.line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('shop.owned.${a.cityId}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Board.ink,
                      ),
                    ),
                  ),
                  if (a.isHome)
                    const _Badge('HOME', Board.amber, Color(0xFF3A3216)),
                  if (a.isHub)
                    const _Badge('HUB', Board.signature, Board.signatureChip),
                  _Badge(
                    'Lv ${a.airport.level}',
                    Board.amber,
                    Colors.transparent,
                    outlined: true,
                  ),
                ],
              ),
              if (a.standing != ShareStanding.off) ...[
                const SizedBox(height: 8),
                _MiniShareBar(share: a.share),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shareText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: shareColor),
                      ),
                    ),
                    if (shareRight != null) Text(shareRight, style: meta),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Meta(
                    icon: Icons.flight,
                    children: [
                      TextSpan(text: '${a.parked}', style: bold),
                      TextSpan(text: ' parked / ${a.gates}', style: meta),
                    ],
                  ),
                  _Meta(
                    icon: Icons.luggage,
                    children: [
                      TextSpan(text: '${a.jobs}', style: bold),
                      TextSpan(
                        text: a.jobs == 1 ? ' job' : ' jobs',
                        style: meta,
                      ),
                    ],
                  ),
                  if (weather != null)
                    _Meta(
                      icon: weatherIcon(weather.typeId),
                      children: [
                        TextSpan(
                          text: weather.activeAt(now)
                              ? '$weatherName now'
                              : '$weatherName in '
                                    '${formatCountdown(weather.startsAt.difference(now))}',
                          style: meta,
                        ),
                      ],
                    ),
                  if (paths.isNotEmpty)
                    Text(
                      paths.join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Board.cargoInk,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.ink, this.fill, {this.outlined = false});

  final String text;
  final Color ink;
  final Color fill;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
      border: outlined
          ? Border.all(color: Board.amber.withValues(alpha: 0.4))
          : null,
    ),
    child: Text(
      text,
      style: outlined
          ? Board.flapStyle(size: 11).copyWith(color: ink)
          : TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: ink,
            ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.children});

  final IconData icon;
  final List<TextSpan> children;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: Board.muted),
      const SizedBox(width: 4),
      Text.rich(TextSpan(children: children)),
    ],
  );
}

/// A thin bar of the city's share: the player first, then rivals biggest
/// first.
class _MiniShareBar extends ConsumerWidget {
  const _MiniShareBar({required this.share});

  final CityShare share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.read(gameConfigProvider);
    final rivals = [
      for (final id in share.points.keys)
        if (id != playerAirlineId) id,
    ]..sort((a, b) => share.of(b).compareTo(share.of(a)));
    final ids = [playerAirlineId, ...rivals];
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: ColoredBox(
          color: Board.raised,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final id in ids)
                if (share.fraction(id) > 0)
                  Expanded(
                    flex: (share.fraction(id) * 1000).round(),
                    child: Container(
                      // A dark notch between airlines, so similar
                      // liveries still read as two.
                      margin: EdgeInsets.only(left: id == ids.first ? 0 : 2),
                      color: airlineColor(config, id),
                    ),
                  ),
              if (share.total <= 0) const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

String _pct(double fraction) => '${(fraction * 100).round()}%';
