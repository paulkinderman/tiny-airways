import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/state/game_state.dart';
import '../game/map/map_scene.dart';
import '../game/tiny_airways_game.dart';
import '../game/world_map_view.dart';
import '../logic/rivals.dart';
import 'airport_panel.dart';
import 'fleet_board.dart';
import 'info_cards.dart';
import 'loading_sheet.dart';
import 'map_scene_builder.dart';
import 'rivals_screens.dart';
import 'route_picker.dart';
import 'start_screen.dart';
import 'theme.dart';
import 'top_bar.dart';
import 'ui_state.dart';

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

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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

    final state = ref.watch(gameSessionProvider);
    if (!state.hasStarted) return const StartScreen();
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
                    : TopBar(onWaitingTap: _jumpToWaiting),
              ),
            ),
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
        ],
      ),
    );
  }

  /// The rival screens cover the map, like the loading sheet.
  Widget? _fullSheet(Panel panel) => switch (panel) {
    RivalryPanel(:final cityId) => RivalryScreen(
      key: ValueKey('rivalry.$cityId'),
      cityId: cityId,
    ),
    TerminalPanel(:final cityId) => TerminalScreen(
      key: ValueKey('terminal.$cityId'),
      cityId: cityId,
    ),
    LeaderboardPanel() => LeaderboardScreen(panel: panel),
    _ => null,
  };

  Widget _tabBody(HomeTab tab) => switch (tab) {
    HomeTab.fleet => FleetScreen(
      onLoad: (id) => _ui.open(LoadingPanel(id)),
      onShowPlane: _showPlane,
    ),
    _ => _ComingSoon(tab: tab),
  };

  Widget _bottom(Panel panel, HomeTab tab, double height, EdgeInsets safe) {
    final nav = _NavBar(
      tab: tab,
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
      RivalryPanel() ||
      TerminalPanel() ||
      LeaderboardPanel() => const SizedBox.shrink(),
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
  });

  final HomeTab tab;
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
                    Icon(
                      icon,
                      color: t == tab ? Board.amber : Board.muted,
                      size: 22,
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

/// Tabs whose screens arrive with later packages (hangar and airport shop
/// with growth, crew with crew).
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.tab});

  final HomeTab tab;

  @override
  Widget build(BuildContext context) {
    final (title, text) = switch (tab) {
      HomeTab.crew => ('Crew', 'Hire pilots and staff here.'),
      HomeTab.hangar => ('Hangar', 'Buy new planes here.'),
      _ => ('Airports', 'Buy airports in new cities here.'),
    };
    return ColoredBox(
      color: Board.ground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title.toUpperCase(), style: Board.flapStyle(size: 20)),
              const SizedBox(height: 8),
              Text(
                '$text Opening soon.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Board.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
