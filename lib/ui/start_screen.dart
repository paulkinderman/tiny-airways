import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/game_config.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Choose your home": the starting continent and home city, shown until
/// the airline starts.
class StartScreen extends ConsumerStatefulWidget {
  const StartScreen({this.onStarted, super.key});

  /// Called with the home city once the airline has started.
  final void Function(String homeCityId)? onStarted;

  @override
  ConsumerState<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends ConsumerState<StartScreen> {
  String _regionId = 'north_america';
  String? _cityId;

  /// The biggest cities first: the obvious homes.
  List<City> _homes(WorldData world, String regionId) =>
      world.citiesIn(regionId)..sort((a, b) {
        final bySize = b.size.compareTo(a.size);
        return bySize != 0 ? bySize : b.population.compareTo(a.population);
      });

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(gameConfigProvider);
    final world = config.world;
    if (!world.hasRegion(_regionId)) _regionId = world.regions.first.id;
    final homes = _homes(world, _regionId);
    final cityId = _cityId ?? homes.first.id;
    final chips = homes.take(3).toList();
    if (!chips.any((c) => c.id == cityId)) chips[2] = world.city(cityId);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'NEW AIRLINE',
                style: Board.flapStyle(
                  size: 12,
                  color: Board.muted,
                  weight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text('CHOOSE YOUR HOME', style: Board.flapStyle(size: 24)),
              const SizedBox(height: 6),
              const Text(
                'Pick a starting continent. The rest unlock as you grow.',
                style: TextStyle(fontSize: 15, color: Board.muted),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _continentTable(config),
                      const SizedBox(height: 18),
                      Text(
                        'HOME CITY',
                        style: Board.flapStyle(
                          size: 12,
                          color: Board.muted,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in chips)
                            BoardChip(
                              key: Key('start.city.${c.id}'),
                              label: c.name,
                              selected: c.id == cityId,
                              onTap: () => setState(() => _cityId = c.id),
                            ),
                          if (homes.length > 3)
                            BoardChip(
                              key: const Key('start.moreCities'),
                              label: 'More…',
                              selected: false,
                              onTap: () => _pickCity(homes, cityId),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AmberButton(
                key: const Key('start.startAirline'),
                label: 'START AIRLINE IN ${world.city(cityId).name}',
                mono: true,
                height: 56,
                onPressed: () => _start(cityId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _continentTable(GameConfig config) {
    final world = config.world;
    Color labelColor(String label) => switch (label.toLowerCase()) {
      'easy' => Board.pax,
      'hard' => Board.bad,
      'standard' => Board.good,
      _ => Board.amber,
    };
    return Container(
      decoration: BoxDecoration(
        color: Board.flap,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Board.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Expanded(flex: 5, child: _heading('CONTINENT')),
                Expanded(flex: 3, child: _heading('SIZE')),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _heading('START'),
                  ),
                ),
              ],
            ),
          ),
          for (final r in world.regions)
            InkWell(
              key: Key('start.region.${r.id}'),
              onTap: () => setState(() {
                _regionId = r.id;
                _cityId = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: r.id == _regionId ? Board.raised : null,
                  border: Border(
                    top: const BorderSide(color: Board.line),
                    left: BorderSide(
                      color: r.id == _regionId
                          ? Board.amber
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FlapText(r.name, size: 13),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        r.hardMode
                            ? '${world.citiesIn(r.id).length} stations'
                            : '${world.citiesIn(r.id).length} cities',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Board.muted,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        r.startLabel.toUpperCase(),
                        textAlign: TextAlign.right,
                        style: Board.flapStyle(
                          size: 11,
                          color: labelColor(r.startLabel),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _heading(String text) => Text(
    text,
    style: Board.flapStyle(
      size: 10,
      color: Board.muted,
      weight: FontWeight.w500,
    ),
  );

  Future<void> _pickCity(List<City> homes, String current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Board.panel,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in homes)
                ListTile(
                  key: Key('start.pick.${c.id}'),
                  title: Text(c.name),
                  subtitle: Text(
                    '${citySizeLabel(c.size)} · ${c.country}',
                    style: const TextStyle(color: Board.muted),
                  ),
                  trailing: c.id == current
                      ? const Icon(Icons.check, color: Board.amber)
                      : null,
                  onTap: () => Navigator.of(context).pop(c.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _cityId = picked);
  }

  void _start(String cityId) {
    final error = ref
        .read(gameSessionProvider.notifier)
        .act((sim, state, now) => sim.startAirline(state, cityId, now));
    if (error != null) {
      showToast(context, ruleErrorText(error));
      return;
    }
    widget.onStarted?.call(cityId);
  }
}
