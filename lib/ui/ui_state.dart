import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tabs along the bottom of the home screen.
enum HomeTab { map, fleet, crew, hangar, airports }

/// The sheet or panel open over the map. Only one is open at a time, and
/// none of this is saved.
sealed class Panel {
  const Panel();
}

class NoPanel extends Panel {
  const NoPanel();
}

/// An airport the player owns: gates, board and the planes parked there.
class AirportPanel extends Panel {
  const AirportPanel(this.cityId, {this.planeId});
  final String cityId;

  /// The parked plane the board's Load button loads.
  final String? planeId;
}

/// A city the player hasn't bought an airport in.
class CityPanel extends Panel {
  const CityPanel(this.cityId);
  final String cityId;
}

class LoadingPanel extends Panel {
  const LoadingPanel(this.planeId);
  final String planeId;
}

class RoutePanel extends Panel {
  const RoutePanel(this.planeId, {this.stops = const []});
  final String planeId;
  final List<String> stops;
}

/// A plane in the air (or holding).
class PlanePanel extends Panel {
  const PlanePanel(this.planeId);
  final String planeId;
}

class WeatherPanel extends Panel {
  const WeatherPanel(this.weatherId);
  final String weatherId;
}

/// The challenge board, milestones and plane parts (full screen).
class ChallengesPanel extends Panel {
  const ChallengesPanel();
}

class UiState {
  const UiState({this.tab = HomeTab.map, this.panel = const NoPanel()});

  final HomeTab tab;
  final Panel panel;
}

final uiProvider = NotifierProvider<UiController, UiState>(UiController.new);

class UiController extends Notifier<UiState> {
  @override
  UiState build() => const UiState();

  void open(Panel panel) => state = UiState(tab: HomeTab.map, panel: panel);
  void close() => open(const NoPanel());
  void showTab(HomeTab tab) => state = UiState(tab: tab);
}
