import 'dart:math' as math;

import 'config_reader.dart';

/// Small, Medium or Large: decides which airports a plane can land at, how
/// many pilots it needs and how much XP its crew earn.
class PlaneClass {
  const PlaneClass({
    required this.id,
    required this.name,
    required this.rank,
    required this.pilotsRequired,
    required this.openCrewSeats,
    required this.crewXpFactor,
    required this.pilotHirePrice,
  });

  factory PlaneClass.fromConfig(ConfigReader c) => PlaneClass(
    id: c.oneOf('id', ids),
    name: c.string('name'),
    rank: c.integer('rank'),
    pilotsRequired: c.integer('pilotsRequired'),
    openCrewSeats: c.integer('openCrewSeats'),
    crewXpFactor: c.number('crewXpFactor'),
    pilotHirePrice: c.integer('pilotHirePrice'),
  );

  static const ids = ['small', 'medium', 'large'];

  final String id;
  final String name;

  /// 1 small, 2 medium, 3 large. An airport takes planes up to its rank.
  final int rank;
  final int pilotsRequired;
  final int openCrewSeats;
  final double crewXpFactor;
  final int pilotHirePrice;
}

/// A plane design from the hangar, or one of the special planes built from
/// parts (which have no price or unlock level).
class PlaneModel {
  const PlaneModel({
    required this.id,
    required this.name,
    required this.classId,
    required this.seats,
    required this.cargoSlots,
    required this.rangeKm,
    required this.speedKmh,
    required this.fuelPerKm,
    required this.price,
    required this.unlockLevel,
    required this.look,
    this.twist,
    this.ignoresJetStream = false,
  });

  factory PlaneModel.fromConfig(ConfigReader c, {required bool special}) {
    final model = PlaneModel(
      id: c.string('id'),
      name: c.string('name'),
      classId: c.oneOf('class', PlaneClass.ids),
      seats: c.integer('seats'),
      cargoSlots: c.integer('cargoSlots'),
      rangeKm: c.integer('rangeKm'),
      speedKmh: c.integer('speedKmh'),
      fuelPerKm: c.number('fuelPerKm'),
      price: special ? null : c.integer('price'),
      unlockLevel: special ? null : c.integer('unlockLevel'),
      look: c.string('look'),
      twist: special ? c.string('twist') : null,
      ignoresJetStream: special && c.boolean('ignoresJetStream'),
    );
    c.check(model.seats >= 0, 'seats', 'should not be negative');
    c.check(model.cargoSlots >= 0, 'cargoSlots', 'should not be negative');
    c.check(model.capacity > 0, 'seats', 'and cargoSlots are both 0');
    c.check(model.rangeKm > 0, 'rangeKm', 'should be above 0');
    c.check(model.speedKmh > 0, 'speedKmh', 'should be above 0');
    c.check(model.fuelPerKm >= 0, 'fuelPerKm', 'should not be negative');
    return model;
  }

  final String id;
  final String name;
  final String classId;
  final int seats;
  final int cargoSlots;
  final int rangeKm;
  final int speedKmh;
  final double fuelPerKm;

  /// Null for special planes, which are built from parts.
  final int? price;
  final int? unlockLevel;
  final String look;

  /// What makes a special plane special ("sightseeing", "supersonic",
  /// "airship"); null for hangar planes.
  final String? twist;
  final bool ignoresJetStream;

  bool get isSpecial => twist != null;
  int get capacity => seats + cargoSlots;
}

/// The three per-plane upgrade tracks: capacity, speed and range.
class PlaneUpgradeConfig {
  const PlaneUpgradeConfig({
    required this.maxLevel,
    required this.costFractionOfPrice,
    required this.capacityPerLevel,
    required this.speedPctPerLevel,
    required this.rangePctPerLevel,
  });

  factory PlaneUpgradeConfig.fromConfig(ConfigReader c) {
    final config = PlaneUpgradeConfig(
      maxLevel: c.integer('maxLevel'),
      costFractionOfPrice: c.numbers('costFractionOfPrice'),
      capacityPerLevel: c.integer('capacityPerLevel'),
      speedPctPerLevel: c.number('speedPctPerLevel'),
      rangePctPerLevel: c.number('rangePctPerLevel'),
    );
    c.check(
      config.costFractionOfPrice.length == config.maxLevel,
      'costFractionOfPrice',
      'should have one entry per level (${config.maxLevel})',
    );
    return config;
  }

  final int maxLevel;

  /// Cost of reaching level n+1 is `costFractionOfPrice[n] x plane price`.
  final List<double> costFractionOfPrice;
  final int capacityPerLevel;
  final double speedPctPerLevel;
  final double rangePctPerLevel;
}

class HangarConfig {
  const HangarConfig({
    required this.startingSlots,
    required this.expansionBasePrice,
    required this.expansionPriceGrowth,
  });

  factory HangarConfig.fromConfig(ConfigReader c) => HangarConfig(
    startingSlots: c.integer('startingSlots'),
    expansionBasePrice: c.integer('expansionBasePrice'),
    expansionPriceGrowth: c.number('expansionPriceGrowth'),
  );

  final int startingSlots;
  final int expansionBasePrice;

  /// Each bought expansion costs this much more than the last.
  final double expansionPriceGrowth;

  /// Price of the next expansion after [bought] earlier ones.
  int expansionPrice(int bought) =>
      (expansionBasePrice * math.pow(expansionPriceGrowth, bought)).round();
}

/// `planes.json`: plane classes, the hangar roster, special planes, upgrades
/// and hangar space.
class PlanesConfig {
  PlanesConfig({
    required this.classes,
    required this.models,
    required this.specialModels,
    required this.upgrades,
    required this.hangar,
  }) : _byId = {
         for (final m in [...models, ...specialModels]) m.id: m,
       },
       _classes = {for (final c in classes) c.id: c};

  factory PlanesConfig.fromConfig(ConfigReader c) => PlanesConfig(
    classes: [for (final r in c.children('classes')) PlaneClass.fromConfig(r)],
    models: [
      for (final r in c.children('models'))
        PlaneModel.fromConfig(r, special: false),
    ],
    specialModels: [
      for (final r in c.children('specialModels'))
        PlaneModel.fromConfig(r, special: true),
    ],
    upgrades: PlaneUpgradeConfig.fromConfig(c.child('upgrades')),
    hangar: HangarConfig.fromConfig(c.child('hangar')),
  );

  final List<PlaneClass> classes;

  /// Planes sold in the hangar, cheapest first.
  final List<PlaneModel> models;
  final List<PlaneModel> specialModels;
  final PlaneUpgradeConfig upgrades;
  final HangarConfig hangar;
  final Map<String, PlaneModel> _byId;
  final Map<String, PlaneClass> _classes;

  PlaneModel model(String id) =>
      _byId[id] ?? (throw ArgumentError.value(id, 'id', 'unknown plane'));

  bool hasModel(String id) => _byId.containsKey(id);

  PlaneClass planeClass(String id) =>
      _classes[id] ?? (throw ArgumentError.value(id, 'id', 'unknown class'));
}
