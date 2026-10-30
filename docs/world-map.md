# World map

The map is the game's home screen: a cartoon world you pan and pinch, with the player's airports, planes flying curved routes with countdowns, the route picker and weather. It lives in `lib/game/` and only draws. Screens give it a `MapScene` built from the game state and hear about taps through a callback; it never changes game state itself.

## Using it from a screen

```dart
final game = TinyAirwaysGame(
  worldData: config.world,
  geometry: ref.read(worldGeometryProvider),
  clock: ref.read(clockProvider),
);
game.onTap = (hit) => switch (hit) {
  PlaneHit(:final planeId) => openPlane(planeId),
  CityHit(:final cityId) => openAirport(cityId),
  WeatherHit(:final weatherId) => showForecast(weatherId),
  null => closePanels(),
};

// Whenever the state changes:
game.scene = MapScene(
  airports: [MapAirport(cityId: 'chicago', level: 3, waitingPlanes: 2)],
  flights: [MapFlight(planeId: 'p1', fromCityId: 'chicago', toCityId: 'toronto', departAt: ..., arriveAt: ...)],
  weather: [...],
  lockedRegionIds: {'africa', 'oceania'},
  routePicker: MapRoutePicker(originCityId: 'chicago', rangeKm: 1200, stops: ['toronto'], reachableCityIds: {...}),
  selectedCityId: 'chicago',
);

// In the widget tree, with the parts of the map covered by panels:
WorldMapView(game: game, insets: EdgeInsets.only(top: 120, bottom: 260))
```

Flights and weather carry timestamps, and the map reads the `Clock` every frame, so planes move and countdowns tick without a new scene. A new scene is only needed when something changes (a plane departs, a stop is picked).

Camera moves for screens: `showCity`, `showPlane` (for "jump to the next idle plane"), `showRegion`, `showNetwork`, `zoomIn`, `zoomOut`. They glide and centre the target in the part of the map not under `insets`.

`demoScene()` in `lib/game/demo_scene.dart` is a busy example (8 airports, 20 planes, 6 rivals, one of each weather event) used by the tests and for screenshots.

## What it draws

From the bottom up (`lib/game/map/layers/`):

| Layer | Draws |
| --- | --- |
| `LandLayer` | Shallows, land per region (muted while the region is locked), lakes, coastlines, region borders |
| `DecorLayer` | Wave squiggles and drifting clouds (decoration only) |
| `WeatherLayer(icons: false)` | Snowstorm and heat wave circles, fog, the jet stream band |
| `RouteLayer` | Dotted trails ahead of the player's planes; the route picker's range ring and chosen legs |
| `CityLayer` | City dots, airport pins (size and number by level, waiting-plane count, upgrade badge), route stops, labels |
| `PlaneLayer` | Planes along their arcs, countdown pills; rival planes smaller, in livery, without pills |
| `WeatherLayer(icons: true)` | Weather icons with "in 8m" forecasts or time left |

A forecast shows faded, with a dotted outline and an "in 8m" pill. An active event is solid with the time left.

## Design calls

- **Projection: Miller cylindrical.** It looks like the familiar Mercator map at city latitudes but is finite at the poles, so the South Pole station (latitude -90) has a real position. Cities are drawn no further south than -85 so its pin is not on the map's bottom edge. The map runs from 84°N to the pole.
- **The map wraps east to west.** Panning never hits a wall, and legs across the Pacific (Los Angeles to Tokyo, Honolulu to Sydney) take the short way over the date line. Everything is drawn once per copy of the world on screen.
- **Routes are arcs, not great circles.** Each leg is a gentle curve bowing towards the top of the map, as in the mockups. Planes move at an even speed along it, from `departAt` to `arriveAt`.
- **Zoom** goes from the map's full height on screen (about half the world on a phone in portrait) to about 600 km across. Pins, labels, planes and lines keep their screen size as you zoom.
- **Labels never overlap.** Selected, route and owned cities get theirs first, then bigger cities. Zoomed out, only bigger cities are labelled, and countdown pills hide below zoom 0.6 except on the selected plane.
- **Regions.** Natural Earth countries are merged into the game's 7 regions. Russia is split at the Urals (60°E) and Turkey is in Europe, matching `cities.json`; overseas islands go by where they are (French Guiana is South America), except Hawaii, which stays with North America.
- **Weather positions.** A thunderstorm or fog sits over one city, a snowstorm or heat wave is a circle of `radiusKm` (`weather.clusterRadiusKm`), and the jet stream is a band of latitude right round the world.
- **Colours** follow the Main and Route mockups (sea #8ED3F5, land #B9E59E, coast #3F8F55, owned airports #1D63C4). Text uses the system font until package 8 adds Rubik.

## Coastlines

`assets/map/world.json` (about 740 KB) is built by `tool/build_map.py` from Natural Earth 1:50m countries and lakes, which are public domain. It holds two levels of detail: `detail` (about 28,000 points) for zoomed-in views and `coarse` (about 5,400) for zoomed-out ones. Small islands are dropped unless a city is on them, and shared region edges are simplified together so neighbouring regions still meet. To rebuild, see the instructions at the top of the script. `test/game/world_geometry_test.dart` checks every city still sits on its own region's land.

## Performance

The target is a smooth map with 20 planes in the air on an older iPhone.

- Zoomed out, the coarse land is drawn as a handful of merged paths. Zoomed in, the detailed land is drawn shape by shape, skipping anything off screen.
- Text is laid out once and reused; countdown pills are laid out again only when their text changes, about once a second.
- Arcs and range rings are computed once per leg and cached.
- `world_map_test.dart` measures a frame with the demo scene's 20 planes, 6 rivals and 5 weather events: about 1 ms of Dart time for update plus drawing on the CI machine, against a budget of 4 ms. GPU time has not been measured on a device yet; the TestFlight build (package 11) is the check for that.

## Left for later packages

- Building `MapScene` from the game state, the airport panel, loading sheet and route picker sheet (package 5). The home screen shows the map with an empty scene until then.
- Plane sprites per model and livery, Rubik on the map, sound (package 8).
- Rival flights in the scene (package 11).
