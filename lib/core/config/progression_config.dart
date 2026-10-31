import 'dart:math' as math;

import 'config_reader.dart';

/// An airline level and the value that applies from it onward.
class LevelStep<T> {
  const LevelStep(this.airlineLevel, this.value);

  final int airlineLevel;
  final T value;
}

/// A region license: the nth one after the starting continent.
class RegionLicense {
  const RegionLicense({required this.airlineLevel, required this.cost});

  final int airlineLevel;
  final int cost;
}

/// `progression.json`: airline XP curve, unlocks and titles.
class ProgressionConfig {
  const ProgressionConfig({
    required this.xpBase,
    required this.xpExponent,
    required this.maxLevel,
    required this.planeClassUnlockLevel,
    required this.airportMaxLevel,
    required this.regionLicenses,
    required this.hangarBonusSlots,
    required this.featureUnlockLevel,
    required this.titles,
  });

  factory ProgressionConfig.fromConfig(ConfigReader c) {
    final classes = c.child('planeClassUnlockLevel');
    final features = c.child('featureUnlockLevel');
    final config = ProgressionConfig(
      xpBase: c.number('xpBase'),
      xpExponent: c.number('xpExponent'),
      maxLevel: c.integer('maxLevel'),
      planeClassUnlockLevel: {
        for (final k in classes.json.keys) k: classes.integer(k),
      },
      airportMaxLevel: [
        for (final r in c.children('airportMaxLevel'))
          LevelStep(r.integer('airlineLevel'), r.integer('maxAirportLevel')),
      ],
      regionLicenses: [
        for (final r in c.children('regionLicenses'))
          RegionLicense(
            airlineLevel: r.integer('airlineLevel'),
            cost: r.integer('cost'),
          ),
      ],
      hangarBonusSlots: [
        for (final r in c.children('hangarBonusSlots'))
          LevelStep(r.integer('airlineLevel'), r.integer('slots')),
      ],
      featureUnlockLevel: {
        for (final k in features.json.keys) k: features.integer(k),
      },
      titles: [
        for (final r in c.children('titles'))
          LevelStep(r.integer('fromLevel'), r.string('title')),
      ],
    );
    for (final feature in featureKeys) {
      c.check(
        config.featureUnlockLevel.containsKey(feature),
        'featureUnlockLevel.$feature',
        'is missing',
      );
    }
    c.check(
      _ascending(config.airportMaxLevel.map((s) => s.airlineLevel)),
      'airportMaxLevel',
      'should be sorted by airlineLevel',
    );
    c.check(
      _ascending(config.regionLicenses.map((s) => s.airlineLevel)),
      'regionLicenses',
      'should be sorted by airlineLevel',
    );
    c.check(
      _ascending(config.titles.map((s) => s.airlineLevel)),
      'titles',
      'should be sorted by fromLevel',
    );
    c.check(
      config.titles.isNotEmpty && config.titles.first.airlineLevel == 1,
      'titles',
      'should start at level 1',
    );
    c.check(
      config.airportMaxLevel.isNotEmpty &&
          config.airportMaxLevel.first.airlineLevel == 1,
      'airportMaxLevel',
      'should start at level 1',
    );
    return config;
  }

  /// Feature keys the rules look up.
  static const featureKeys = [
    'challenges',
    'cityShare',
    'specialJobs',
    'contracts',
    'partCrates',
    'terminals',
    'leaderboard',
    'specialLiveries',
  ];

  final double xpBase;
  final double xpExponent;
  final int maxLevel;
  final Map<String, int> planeClassUnlockLevel;
  final List<LevelStep<int>> airportMaxLevel;
  final List<RegionLicense> regionLicenses;
  final List<LevelStep<int>> hangarBonusSlots;
  final Map<String, int> featureUnlockLevel;
  final List<LevelStep<String>> titles;

  /// Airline XP needed to go from [level] to the next.
  int xpToNext(int level) => (xpBase * math.pow(level, xpExponent)).round();

  bool isUnlocked(String feature, int airlineLevel) =>
      airlineLevel >=
      (featureUnlockLevel[feature] ??
          (throw ArgumentError.value(feature, 'feature', 'unknown feature')));

  String titleFor(int airlineLevel) => _at(titles, airlineLevel);

  int maxAirportLevelAt(int airlineLevel) => _at(airportMaxLevel, airlineLevel);

  /// Hangar slots earned from levels (on top of the starting slots).
  int hangarBonusAt(int airlineLevel) => [
    for (final s in hangarBonusSlots)
      if (airlineLevel >= s.airlineLevel) s.value,
  ].fold(0, (a, b) => a + b);

  static T _at<T>(List<LevelStep<T>> steps, int level) =>
      steps.lastWhere((s) => level >= s.airlineLevel).value;

  static bool _ascending(Iterable<int> values) {
    int? last;
    for (final v in values) {
      if (last != null && v <= last) return false;
      last = v;
    }
    return true;
  }
}
