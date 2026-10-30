import 'airports_config.dart';
import 'config_reader.dart';
import 'crew_config.dart';
import 'extras_config.dart';
import 'flights_config.dart';
import 'jobs_config.dart';
import 'planes_config.dart';
import 'progression_config.dart';
import 'rivals_config.dart';
import 'weather_config.dart';
import 'world.dart';

export 'airports_config.dart';
export 'crew_config.dart';
export 'effect.dart';
export 'extras_config.dart';
export 'flights_config.dart';
export 'jobs_config.dart';
export 'planes_config.dart';
export 'progression_config.dart';
export 'rivals_config.dart';
export 'weather_config.dart';
export 'world.dart';

/// Every tunable number and all static game data, loaded from
/// `assets/config/*.json` and `assets/data/*.json`.
///
/// To add a config file: drop `<name>.json` into `assets/config/`, add its
/// name to [files], and give it a typed class built in [GameConfig.fromFiles].
/// Game code reads typed fields, never raw JSON.
///
/// Loading also checks the files against each other (every id referenced
/// exists, every region has cities, and so on), so bad data fails at startup
/// and in CI rather than mid-game.
class GameConfig {
  const GameConfig({
    required this.economy,
    required this.world,
    required this.planes,
    required this.airports,
    required this.jobs,
    required this.flights,
    required this.progression,
    required this.crew,
    required this.weather,
    required this.rivals,
    required this.extras,
  });

  /// Config files to load from `assets/config/`, by name (without `.json`).
  static const files = [
    'economy',
    'regions',
    'planes',
    'airports',
    'jobs',
    'flights',
    'progression',
    'crew',
    'weather',
    'rivals',
    'extras',
  ];

  /// Static data files to load from `assets/data/`.
  static const dataFiles = ['cities', 'rivals', 'crew'];

  final EconomyConfig economy;
  final WorldData world;
  final PlanesConfig planes;
  final AirportsConfig airports;
  final JobsConfig jobs;
  final FlightsConfig flights;
  final ProgressionConfig progression;
  final CrewConfig crew;
  final WeatherConfig weather;
  final RivalsConfig rivals;
  final ExtrasConfig extras;

  /// Builds the config from parsed files. [files] and [data] are keyed by
  /// the names in [GameConfig.files] and [GameConfig.dataFiles].
  factory GameConfig.fromFiles(
    Map<String, ConfigReader> files,
    Map<String, ConfigReader> data,
  ) {
    final regions = files['regions']!;
    final config = GameConfig(
      economy: EconomyConfig.fromConfig(files['economy']!),
      world: WorldData(
        regions: [
          for (final r in regions.children('regions')) Region.fromConfig(r),
        ],
        cities: [
          for (final c in data['cities']!.children('cities'))
            City.fromConfig(c),
        ],
        crossRegionPayPct: regions.number('crossRegionPayPct'),
      ),
      planes: PlanesConfig.fromConfig(files['planes']!),
      airports: AirportsConfig.fromConfig(files['airports']!),
      jobs: JobsConfig.fromConfig(files['jobs']!),
      flights: FlightsConfig.fromConfig(files['flights']!),
      progression: ProgressionConfig.fromConfig(files['progression']!),
      crew: CrewConfig.fromConfig(files['crew']!, data['crew']),
      weather: WeatherConfig.fromConfig(files['weather']!),
      rivals: RivalsConfig.fromConfig(files['rivals']!, data['rivals']!),
      extras: ExtrasConfig.fromConfig(files['extras']!),
    );
    config._crossCheck();
    return config;
  }

  void _crossCheck() {
    void check(bool ok, String message) {
      if (!ok) throw ConfigException(message);
    }

    void unique(String what, Iterable<String> ids) {
      final seen = <String>{};
      for (final id in ids) {
        check(seen.add(id), '$what has the id "$id" more than once');
      }
    }

    unique('regions', world.regions.map((r) => r.id));
    unique('cities', world.cities.map((c) => c.id));
    unique('planes', [
      ...planes.models.map((m) => m.id),
      ...planes.specialModels.map((m) => m.id),
    ]);
    unique('rivals', rivals.roster.map((r) => r.id));
    unique('crew signatures', crew.signatures.map((s) => s.id));
    unique('crew roles', crew.roles.map((r) => r.id));
    unique('airport paths', airports.paths.map((p) => p.id));

    for (final city in world.cities) {
      check(
        world.hasRegion(city.regionId),
        'cities.${city.id}.regionId "${city.regionId}" is not a region',
      );
    }
    for (final region in world.regions) {
      check(
        world.citiesIn(region.id).isNotEmpty,
        'region "${region.id}" has no cities',
      );
    }
    check(
      world.regions.length - 1 <= progression.regionLicenses.length,
      'progression.regionLicenses needs one entry per region after the first '
      '(${world.regions.length - 1})',
    );

    check(
      planes.hasModel(economy.startingPlaneModelId),
      'economy.startingPlaneModelId "${economy.startingPlaneModelId}" '
      'is not a plane',
    );
    for (final id in PlaneClass.ids) {
      check(
        planes.classes.any((c) => c.id == id),
        'planes.classes is missing "$id"',
      );
      check(
        progression.planeClassUnlockLevel.containsKey(id),
        'progression.planeClassUnlockLevel is missing "$id"',
      );
    }
    for (final model in planes.models) {
      check(
        model.unlockLevel! >= progression.planeClassUnlockLevel[model.classId]!,
        'planes.${model.id} unlocks before its class (${model.classId})',
      );
    }
    for (final id in extras.partBuiltPlanes) {
      check(
        planes.specialModels.any((m) => m.id == id),
        'extras.parts.specialPlanes "$id" is not a special plane',
      );
    }
    for (final d in [...extras.challenges.daily, ...extras.challenges.weekly]) {
      check(
        ExtrasConfig.isMetric(d.metric) &&
            !ExtrasConfig.stateMetrics.contains(d.metric),
        'extras.challenges.${d.id}.metric "${d.metric}" can\'t be counted',
      );
      final feature = d.requiresFeature;
      check(
        feature == null || progression.featureUnlockLevel.containsKey(feature),
        'extras.challenges.${d.id}.requiresFeature "$feature" is not a feature',
      );
      check(
        d.requiresPlane == null || planes.hasModel(d.requiresPlane!),
        'extras.challenges.${d.id}.requiresPlane "${d.requiresPlane}" '
        'is not a plane',
      );
    }
    for (final w in extras.challenges.badWeather) {
      check(
        weather.events.any((e) => e.id == w),
        'extras.challenges.badWeather "$w" is not a weather event',
      );
    }
    for (final m in extras.milestones) {
      check(
        ExtrasConfig.isMetric(m.metric),
        'extras.milestones.${m.id}.metric "${m.metric}" is not a metric',
      );
    }
    final sightseeing = jobs.special['sightseeing']!.requiresModel;
    check(
      sightseeing == null || planes.hasModel(sightseeing),
      'jobs.special.sightseeing.requiresModel "$sightseeing" is not a plane',
    );
    final fragile = jobs.special['fragile']!.requiresRole;
    check(
      fragile == null || crew.roles.any((r) => r.id == fragile),
      'jobs.special.fragile.requiresRole "$fragile" is not a crew role',
    );
    check(
      airports.levels.last.level >= progression.airportMaxLevel.last.value,
      'progression.airportMaxLevel goes past the last airport level',
    );
    check(
      economy.homeAirportStartLevel <= airports.maxLevel,
      'economy.homeAirportStartLevel is above the last airport level',
    );

    unique('crew skill nodes', [
      for (final branch in [
        ...crew.skillTrees.values.expand((b) => b),
        ...crew.signatures,
      ])
        for (final node in branch.nodes) node.id,
    ]);
    unique('named crew', crew.named.map((n) => n.id));
    for (final region in world.regions) {
      check(
        crew.rookieNames.containsKey(region.id),
        'data/crew.rookieNames is missing "${region.id}"',
      );
    }
    for (final n in crew.named) {
      final where = 'data/crew.named.${n.id}';
      check(
        crew.roles.any((r) => r.id == n.roleId),
        '$where.roleId "${n.roleId}" is not a crew role',
      );
      check(world.hasCity(n.homeCityId), '$where.homeCityId is not a city');
      final flight = crew.role(n.roleId).isFlightCrew;
      check(
        flight == (n.signatureId != null),
        flight
            ? '$where needs a signatureId'
            : '$where is airport staff and has no signature',
      );
      check(
        n.signatureId == null ||
            crew.signatures.any((s) => s.id == n.signatureId),
        '$where.signatureId "${n.signatureId}" is not a signature',
      );
      check(
        flight
            ? crew.skillTrees[n.roleId]!.any((b) => b.id == n.favoriteId)
            : crew.staffPaths[n.roleId]!.any((p) => p.id == n.favoriteId),
        '$where.favorite "${n.favoriteId}" is not one of its branches',
      );
    }

    for (final rival in rivals.roster) {
      check(
        world.hasRegion(rival.regionId),
        'rivals.${rival.id}.regionId "${rival.regionId}" is not a region',
      );
      check(
        world.hasCity(rival.hubCityId),
        'rivals.${rival.id}.hubCityId "${rival.hubCityId}" is not a city',
      );
      check(
        world.city(rival.hubCityId).regionId == rival.regionId,
        'rivals.${rival.id} has its hub outside its region',
      );
    }
  }
}

/// Starting values and pay rates (design doc, Economy section).
class EconomyConfig {
  const EconomyConfig({
    required this.startingMoney,
    required this.startingPlaneModelId,
    required this.homeAirportStartLevel,
    required this.freeNearbyAirports,
    required this.passengerRatePerKm,
    required this.cargoRatePerKm,
  });

  final int startingMoney;
  final String startingPlaneModelId;
  final int homeAirportStartLevel;
  final int freeNearbyAirports;
  final double passengerRatePerKm;
  final double cargoRatePerKm;

  factory EconomyConfig.fromConfig(ConfigReader c) {
    final rates = c.child('rates');
    return EconomyConfig(
      startingMoney: c.integer('startingMoney'),
      startingPlaneModelId: c.string('startingPlaneModelId'),
      homeAirportStartLevel: c.integer('homeAirportStartLevel'),
      freeNearbyAirports: c.integer('freeNearbyAirports'),
      passengerRatePerKm: rates.number('passengerPerKm'),
      cargoRatePerKm: rates.number('cargoPerKm'),
    );
  }
}
