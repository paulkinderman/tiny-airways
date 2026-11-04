import 'dart:async';

import 'package:flutter/material.dart' hide Simulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../game/map/map_scene.dart';
import '../game/tiny_airways_game.dart';
import '../game/world_map_view.dart';
import '../logic/simulation.dart';
import 'airport_panel.dart';
import 'airports_screen.dart';
import 'challenges_screen.dart';
import 'crew_screen.dart';
import 'fleet_board.dart';
import 'growth_sheets.dart';
import 'guide_screen.dart';
import 'hangar_screen.dart';
import 'info_cards.dart';
import 'loading_sheet.dart';
import 'map_scene_builder.dart';
import 'rivals_screens.dart';
import 'route_picker.dart';
import 'start_screen.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'ui_state.dart';
import 'walkthrough.dart';

/// The map is home; every other screen is a sheet or panel over it. Before
/// the airline starts, this shows the starting continent picker.
///
/// It also drives the game clock: once a second it runs the simulation up
/// to now, so planes land and boards rotate while the player watches, and
/// after time away it shows the welcome-back summary.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _navHeight = 64.0;

  TinyAirwaysGame? _game;
  String _sceneKey = '';
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;

  /// The last plane the "waiting" button jumped to, so it cycles.
  String? _lastJumpId;

  GameSession get _session => ref.read(gameSessionProvider.notifier);
  UiController get _ui => ref.read(uiProvider.notifier);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _lifecycle = AppLifecycleListener(onResume: _tick);
    // Catch up on launch (this posts the welcome-back summary).
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _tick() {
    if (mounted) _session.tick();
  }

  TinyAirwaysGame _gameFor(GameState state) => _game ??= TinyAirwaysGame(
    worldData: ref.read(gameConfigProvider).world,
    geometry: ref.read(worldGeometryProvider),
    clock: ref.read(clockProvider),
    scene: _scene(state, ref.read(uiProvider)),
  )..onTap = _onMapTap;

  MapScene _scene(GameState state, UiState ui) => buildMapScene(
    sim: ref.read(simulationProvider),
    state: state,
    ui: ui,
    now: ref.read(clockProvider).now(),
  );

  void _onMapTap(MapHit? hit) {
    final panel = ref.read(uiProvider).panel;
    if (panel is RoutePanel) {
      if (hit is CityHit) {
        final error = toggleRouteStop(ref, panel, hit.cityId);
        if (error != null) _toast(error);
      }
      return;
    }
    final state = ref.read(gameSessionProvider);
    switch (hit) {
      case PlaneHit(:final planeId):
        _ui.open(PlanePanel(planeId));
      case RivalPlaneHit(:final planeId):
        final rivalId = RivalFlight.rivalIdOf(planeId);
        if (rivalId != null) _ui.open(RivalCardPanel(rivalId));
      case CityHit(:final cityId):
        _ui.open(
          state.ownsAirport(cityId) ? AirportPanel(cityId) : CityPanel(cityId),
        );
      case WeatherHit(:final weatherId):
        _ui.open(WeatherPanel(weatherId));
      case null:
        _ui.close();
    }
  }

  /// Marks the walkthrough seen (it is saved, so it shows only once) and
  /// returns to the map.
  void _finishTour() {
    _session.update((s) => s.copyWith(tourSeen: true));
    _ui.close();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  /// After a landing: says who levelled up and gained skill points, with a
  /// button straight to their skill tree.
  void _crewLevelled(GameState? before, GameState after) {
    if (before == null || !after.hasStarted) return;
    final desk = ref.read(simulationProvider).crew;
    final grown = [
      for (final m in after.crew.members)
        if (before.crew.member(m.id) case final was?)
          if (m.level > was.level && desk.unspentPoints(m) > 0) m,
    ];
    if (grown.isEmpty) return;
    final first = grown.first;
    final points = desk.unspentPoints(first);
    final text = grown.length == 1
        ? '${first.name} reached Lv ${first.level}: '
              '${points == 1 ? '1 skill point' : '$points skill points'} '
              'to spend.'
        : '${grown.length} crew levelled up and have skill points to spend.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('crew.levelToast'),
          content: Row(
            children: [
              const Icon(Icons.arrow_circle_up_rounded, color: Board.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontFamily: Board.sans,
                    fontSize: 14,
                    color: Board.ink,
                  ),
                ),
              ),
            ],
          ),
          // Floats above the tab bar, so the Crew tab's badge stays visible.
          margin: const EdgeInsets.fromLTRB(12, 0, 12, _navHeight + 8),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: grown.length == 1 ? 'UPGRADE' : 'SEE CREW',
            textColor: Board.amber,
            onPressed: () {
              if (grown.length == 1) {
                ref.read(crewFocusProvider.notifier).focus(first.id);
              }
              _ui.showTab(HomeTab.crew);
            },
          ),
        ),
      );
  }

  /// Opens the airport of the next plane waiting at a gate.
  void _jumpToWaiting() {
    final ready = readyPlanes(ref.read(gameSessionProvider));
    if (ready.isEmpty) return;
    final i = ready.indexWhere((p) => p.id == _lastJumpId);
    final next = ready[(i + 1) % ready.length];
    _lastJumpId = next.id;
    _ui.open(AirportPanel(next.cityId, planeId: next.id));
  }

  void _showPlane(String planeId) {
    final plane = ref.read(gameSessionProvider).plane(planeId);
    if (plane == null) return;
    _ui.open(
      plane.status == PlaneStatus.parked
          ? AirportPanel(plane.cityId, planeId: planeId)
          : PlanePanel(planeId),
    );
  }

  /// Moves the camera to whatever a newly opened panel is about, once the
  /// map has its new insets.
  void _follow(UiState? before, UiState after) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveCamera(before, after);
      });

  void _moveCamera(UiState? before, UiState after) {
    final game = _game;
    if (game == null || after.tab != HomeTab.map) return;
    final state = ref.read(gameSessionProvider);
    switch (after.panel) {
      case AirportPanel(:final cityId) || CityPanel(:final cityId):
        final was = before?.panel;
        final same =
            (was is AirportPanel && was.cityId == cityId) ||
            (was is CityPanel && was.cityId == cityId);
        if (!same) game.showCity(cityId);
      case RoutePanel(:final planeId) when before?.panel is! RoutePanel:
        final plane = state.plane(planeId);
        if (plane != null) game.showCity(plane.cityId, zoom: 1.5);
      case PlanePanel(:final planeId):
        game.showPlane(planeId);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(uiProvider, _follow);
    ref.listen(welcomeBackProvider, (_, summary) {
      if (summary == null) return;
      showDialog<void>(
        context: context,
        builder: (_) => WelcomeBackDialog(summary: summary),
      ).whenComplete(ref.read(welcomeBackProvider.notifier).dismiss);
    });
    ref.listen(gameSessionProvider, _crewLevelled);
    ref.listen(gameSessionProvider.select((s) => s.player.level), (from, to) {
      if (from == null || to <= from) return;
      showDialog<void>(
        context: context,
        builder: (_) => LevelUpDialog(from: from, to: to),
      );
    });

    final state = ref.watch(gameSessionProvider);
    if (!state.hasStarted) return const StartScreen();
    final touring = !state.tourSeen && ref.watch(walkthroughEnabledProvider);
    final ui = ref.watch(uiProvider);
    final game = _gameFor(state);
    final scene = _scene(state, ui);
    final key = sceneKey(scene);
    if (key != _sceneKey) {
      _sceneKey = key;
      game.scene = scene;
    }

    final media = MediaQuery.of(context);
    final safe = media.padding;
    final height = media.size.height;
    final panel = ui.tab == HomeTab.map ? ui.panel : const NoPanel();
    final routing = panel is RoutePanel;
    final bottomInset = switch (panel) {
      NoPanel() => GatePanel.maxHeight + _navHeight + safe.bottom,
      AirportPanel() => height * 0.58,
      RoutePanel() => 300.0 + safe.bottom,
      _ => 190.0 + _navHeight + safe.bottom,
    };
    final topInset = safe.top + TopBar.height + (routing ? 8 : 0);

    return Scaffold(
      backgroundColor: Board.ground,
      body: Stack(
        children: [
          Positioned.fill(
            child: WorldMapView(
              game: game,
              insets: EdgeInsets.only(top: topInset, bottom: bottomInset),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ColoredBox(
              color: Board.ground,
              child: SafeArea(
                bottom: false,
                child: routing
                    ? RouteHeader(panel: panel)
                    : TopBar(
                        onWaitingTap: _jumpToWaiting,
                        onLevelTap: () => showBoardSheet(
                          context,
                          AirlineSheet(
                            onGuide: () {
                              Navigator.of(context).pop();
                              _ui.open(const GuidePanel(section: 'levels'));
                            },
                          ),
                        ),
                        onChallengesTap: () =>
                            _ui.open(const ChallengesPanel()),
                      ),
              ),
            ),
          ),
          // The guide's "?" sits under the map's zoom buttons while nothing
          // else is open over the map.
          if (ui.tab == HomeTab.map && panel is NoPanel)
            Positioned(
              top: topInset + GuideButton.mapTop,
              right: 12,
              child: GuideButton(onTap: () => _ui.open(const GuidePanel())),
            ),
          if (ui.tab != HomeTab.map)
            Positioned.fill(
              top: safe.top + TopBar.height,
              bottom: _navHeight + safe.bottom,
              child: _tabBody(ui.tab),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottom(panel, ui.tab, height, safe),
          ),
          if (panel is LoadingPanel)
            Positioned.fill(
              child: ColoredBox(
                color: Board.ground,
                child: SafeArea(
                  child: LoadingSheet(
                    key: ValueKey(panel.planeId),
                    planeId: panel.planeId,
                  ),
                ),
              ),
            ),
          if (_fullSheet(panel) case final sheet?)
            Positioned.fill(
              child: ColoredBox(
                color: Board.ground,
                child: SafeArea(child: sheet),
              ),
            ),
          if (touring)
            // Keyed so it keeps its place in the tour when a tab's body is
            // added or removed above it.
            Positioned.fill(
              key: const ValueKey('walkthrough'),
              child: Walkthrough(
                onStep: (t) => t == HomeTab.map ? _ui.close() : _ui.showTab(t),
                onDone: _finishTour,
                navHeight: _navHeight,
                gatePanelHeight: GatePanel.maxHeight,
                topBarHeight: TopBar.height,
                navTabs: [for (final (t, _, _) in _NavBar._items) t],
              ),
            ),
        ],
      ),
    );
  }

  /// The rival screens cover the map, like the loading sheet.
  Widget? _fullSheet(Panel panel) => switch (panel) {
    ChallengesPanel() => ChallengesScreen(onClose: _ui.close),
    RivalryPanel(:final cityId) => RivalryScreen(
      key: ValueKey('rivalry.$cityId'),
      cityId: cityId,
    ),
    TerminalPanel(:final cityId) => TerminalScreen(
      key: ValueKey('terminal.$cityId'),
      cityId: cityId,
    ),
    LeaderboardPanel() => LeaderboardScreen(panel: panel),
    GuidePanel(:final section) => GuideScreen(
      key: ValueKey('guide.$section'),
      section: section,
      onClose: _ui.close,
    ),
    _ => null,
  };

  Widget _tabBody(HomeTab tab) => switch (tab) {
    HomeTab.fleet => FleetScreen(
      onLoad: (id) => _ui.open(LoadingPanel(id)),
      onShowPlane: _showPlane,
    ),
    HomeTab.hangar => const HangarScreen(),
    HomeTab.airports => AirportsScreen(
      onShowAirport: (id) => _ui.open(AirportPanel(id)),
    ),
    HomeTab.crew => const CrewScreen(),
    // The map has no body: it is the game underneath.
    HomeTab.map => const SizedBox.shrink(),
  };

  Widget _bottom(Panel panel, HomeTab tab, double height, EdgeInsets safe) {
    final nav = _NavBar(
      tab: tab,
      crewBadge: crewWithPoints(
        ref.read(simulationProvider),
        ref.watch(gameSessionProvider),
      ),
      onTab: (t) => t == HomeTab.map ? _ui.close() : _ui.showTab(t),
      bottomPadding: safe.bottom,
    );
    if (tab != HomeTab.map) return nav;
    return switch (panel) {
      AirportPanel() => Container(
        height: height * 0.58,
        decoration: const BoxDecoration(
          color: Board.ground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.only(bottom: safe.bottom),
          child: AirportPanelView(key: ValueKey(panel.cityId), panel: panel),
        ),
      ),
      RoutePanel() => ColoredBox(
        color: Board.panel,
        child: Padding(
          padding: EdgeInsets.only(bottom: safe.bottom),
          child: RoutePanelView(
            panel: panel,
            onDeparted: (id) {
              _ui.close();
              _game?.showPlane(id);
            },
          ),
        ),
      ),
      LoadingPanel() ||
      ChallengesPanel() ||
      RivalryPanel() ||
      TerminalPanel() ||
      LeaderboardPanel() ||
      GuidePanel() => const SizedBox.shrink(),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switch (panel) {
            PlanePanel(:final planeId) => PlaneCard(planeId: planeId),
            WeatherPanel(:final weatherId) => WeatherCard(weatherId: weatherId),
            CityPanel(:final cityId) => CityCard(cityId: cityId),
            RivalCardPanel(:final rivalId) => RivalCard(rivalId: rivalId),
            _ => GatePanel(
              onLoad: (id) => _ui.open(LoadingPanel(id)),
              onShowPlane: _showPlane,
            ),
          },
          nav,
        ],
      ),
    };
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.tab,
    required this.onTab,
    required this.bottomPadding,
    this.crewBadge = 0,
  });

  final HomeTab tab;

  /// Crew with skill points to spend, shown as a bubble on the Crew tab.
  final int crewBadge;
  final void Function(HomeTab tab) onTab;
  final double bottomPadding;

  static const _items = [
    (HomeTab.map, Icons.map_outlined, 'Map'),
    (HomeTab.fleet, Icons.send_rounded, 'Fleet'),
    (HomeTab.crew, Icons.groups_outlined, 'Crew'),
    (HomeTab.hangar, Icons.warehouse_outlined, 'Hangar'),
    (HomeTab.airports, Icons.place_outlined, 'Airports'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(bottom: bottomPadding),
    decoration: const BoxDecoration(
      color: Board.panel,
      border: Border(top: BorderSide(color: Board.line)),
    ),
    child: SizedBox(
      height: _HomeScreenState._navHeight,
      child: Row(
        children: [
          for (final (t, icon, label) in _items)
            Expanded(
              child: InkWell(
                key: Key('nav.${t.name}'),
                onTap: () => onTab(t),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          icon,
                          color: t == tab ? Board.amber : Board.muted,
                          size: 22,
                        ),
                        if (t == HomeTab.crew && crewBadge > 0)
                          Positioned(
                            top: -6,
                            right: -10,
                            child: _Badge(count: crewBadge),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: t == tab
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: t == tab ? Board.amber : Board.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// The red count bubble on a nav tab.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('nav.crew.badge'),
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE5484D),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: Board.panel, width: 2),
    ),
    child: Text(
      count > 9 ? '9+' : '$count',
      style: const TextStyle(
        fontSize: 10,
        height: 1,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );
}
