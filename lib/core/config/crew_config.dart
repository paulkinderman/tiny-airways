import 'dart:math' as math;

import 'config_reader.dart';
import 'effect.dart';

/// A crew role and the bonus every member of it gives from day one.
class CrewRole {
  const CrewRole({
    required this.id,
    required this.name,
    required this.assignedTo,
    required this.base,
  });

  factory CrewRole.fromConfig(ConfigReader c) => CrewRole(
    id: c.string('id'),
    name: c.string('name'),
    assignedTo: c.oneOf('assignedTo', ['plane', 'airport']),
    base: Effect(
      effect: c.string('baseEffect'),
      value: c.number('baseValue'),
      text: c.string('text'),
    ),
  );

  final String id;
  final String name;

  /// `plane` for flight crew (who earn XP and skill points), `airport` for
  /// staff (who are upgraded with money).
  final String assignedTo;
  final Effect base;

  bool get isFlightCrew => assignedTo == 'plane';
}

/// One node in a skill tree. Nodes in a branch unlock in [step] order.
class SkillNode extends Effect {
  const SkillNode({
    required this.id,
    required this.step,
    required this.capstone,
    required super.effect,
    required super.value,
    required super.text,
    this.name,
  });

  factory SkillNode.fromConfig(ConfigReader c, String branchId) {
    final step = c.integer('step');
    final effect = Effect.fromConfig(c);
    return SkillNode(
      id: c.has('id') ? c.string('id') : '$branchId.$step',
      step: step,
      capstone: c.booleanOr('capstone', false),
      name: c.has('name') ? c.string('name') : null,
      effect: effect.effect,
      value: effect.value,
      text: effect.text,
    );
  }

  final String id;
  final int step;
  final bool capstone;

  /// Capstones have names ("Autopilot"); plain nodes don't.
  final String? name;
}

/// A branch of a skill tree, or a signature branch.
class SkillBranch {
  const SkillBranch({
    required this.id,
    required this.name,
    required this.nodes,
  });

  factory SkillBranch.fromConfig(ConfigReader c, {required int length}) {
    final id = c.string('id');
    final branch = SkillBranch(
      id: id,
      name: c.string('name'),
      nodes: [for (final n in c.children('nodes')) SkillNode.fromConfig(n, id)],
    );
    c.check(
      branch.nodes.length == length,
      'nodes',
      'should have $length nodes',
    );
    for (var i = 0; i < branch.nodes.length; i++) {
      c.check(
        branch.nodes[i].step == i + 1,
        'nodes[$i].step',
        'should be ${i + 1}',
      );
      c.check(
        branch.nodes[i].capstone == (i == length - 1),
        'nodes[$i].capstone',
        'should be true only for the last node',
      );
    }
    return branch;
  }

  final String id;
  final String name;
  final List<SkillNode> nodes;

  SkillNode get capstone => nodes.last;
}

/// One money-bought upgrade path for airport staff.
class StaffPath {
  const StaffPath({required this.id, required this.name, required this.tiers});

  factory StaffPath.fromConfig(ConfigReader c) => StaffPath(
    id: c.string('id'),
    name: c.string('name'),
    tiers: [for (final t in c.children('tiers')) Effect.fromConfig(t)],
  );

  final String id;
  final String name;

  /// Each tier's value is the total at that tier, not an increment.
  final List<Effect> tiers;
}

class CrewXpConfig {
  const CrewXpConfig({
    required this.kmPerXp,
    required this.minLoadFactor,
    required this.crossRegionBonusPct,
    required this.vipOrBulkBonusPct,
    required this.perEarlierStopBonusPct,
    required this.firstOfficerSkillFactor,
  });

  factory CrewXpConfig.fromConfig(ConfigReader c) => CrewXpConfig(
    kmPerXp: c.number('kmPerXp'),
    minLoadFactor: c.number('minLoadFactor'),
    crossRegionBonusPct: c.number('crossRegionBonusPct'),
    vipOrBulkBonusPct: c.number('vipOrBulkBonusPct'),
    perEarlierStopBonusPct: c.number('perEarlierStopBonusPct'),
    firstOfficerSkillFactor: c.number('firstOfficerSkillFactor'),
  );

  final double kmPerXp;
  final double minLoadFactor;
  final double crossRegionBonusPct;
  final double vipOrBulkBonusPct;
  final double perEarlierStopBonusPct;

  /// The first officer's skills apply at this fraction.
  final double firstOfficerSkillFactor;
}

class HiringConfig {
  const HiringConfig({
    required this.rookiesOnOffer,
    required this.rookieRefreshHours,
    required this.firstNonPilotPrice,
    required this.nonPilotPriceGrowth,
    required this.veteransOnOffer,
    required this.veteranRefreshHours,
    required this.veteranMinLevel,
    required this.veteranMaxLevel,
    required this.veteranPricePerLevel,
    required this.freePilotWithPlane,
    required this.respecCostFractionOfHirePrice,
  });

  factory HiringConfig.fromConfig(ConfigReader c) => HiringConfig(
    rookiesOnOffer: c.integer('rookiesOnOffer'),
    rookieRefreshHours: c.integer('rookieRefreshHours'),
    firstNonPilotPrice: c.integer('firstNonPilotPrice'),
    nonPilotPriceGrowth: c.number('nonPilotPriceGrowth'),
    veteransOnOffer: c.integer('veteransOnOffer'),
    veteranRefreshHours: c.integer('veteranRefreshHours'),
    veteranMinLevel: c.integer('veteranMinLevel'),
    veteranMaxLevel: c.integer('veteranMaxLevel'),
    veteranPricePerLevel: c.integer('veteranPricePerLevel'),
    freePilotWithPlane: c.boolean('freePilotWithPlane'),
    respecCostFractionOfHirePrice: c.number('respecCostFractionOfHirePrice'),
  );

  final int rookiesOnOffer;
  final int rookieRefreshHours;
  final int firstNonPilotPrice;

  /// Each non-pilot already on staff raises the next one's price this much.
  final double nonPilotPriceGrowth;
  final int veteransOnOffer;
  final int veteranRefreshHours;
  final int veteranMinLevel;
  final int veteranMaxLevel;
  final int veteranPricePerLevel;
  final bool freePilotWithPlane;
  final double respecCostFractionOfHirePrice;

  /// Price of a rookie non-pilot when [nonPilotsOnStaff] are already hired.
  int rookiePrice(int nonPilotsOnStaff) =>
      (firstNonPilotPrice * math.pow(1 + nonPilotPriceGrowth, nonPilotsOnStaff))
          .round();

  int veteranPrice(int level) => veteranPricePerLevel * level;
}

/// `crew.json`: roles, skill trees, signatures, staff upgrades, XP and hiring.
class CrewConfig {
  const CrewConfig({
    required this.roles,
    required this.skillTrees,
    required this.signatures,
    required this.staffPaths,
    required this.staffTierCosts,
    required this.maxLevel,
    required this.xpBase,
    required this.xpExponent,
    required this.skillPointsPerLevel,
    required this.xp,
    required this.hiring,
  });

  factory CrewConfig.fromConfig(ConfigReader c) {
    final roles = [for (final r in c.children('roles')) CrewRole.fromConfig(r)];
    final trees = c.child('skillTrees');
    final staff = c.child('staffPaths');
    final levels = c.child('levels');
    final config = CrewConfig(
      roles: roles,
      skillTrees: {
        for (final role in roles.where((r) => r.isFlightCrew))
          role.id: [
            for (final b in trees.children(role.id))
              SkillBranch.fromConfig(b, length: branchLength),
          ],
      },
      signatures: [
        for (final s in c.children('signatures'))
          SkillBranch.fromConfig(s, length: signatureLength),
      ],
      staffPaths: {
        for (final role in roles.where((r) => !r.isFlightCrew))
          role.id: [
            for (final p in staff.children(role.id)) StaffPath.fromConfig(p),
          ],
      },
      staffTierCosts: c.integers('staffTierCosts'),
      maxLevel: levels.integer('maxLevel'),
      xpBase: levels.number('xpBase'),
      xpExponent: levels.number('xpExponent'),
      skillPointsPerLevel: levels.integer('skillPointsPerLevel'),
      xp: CrewXpConfig.fromConfig(c.child('xp')),
      hiring: HiringConfig.fromConfig(c.child('hiring')),
    );
    for (final entry in config.skillTrees.entries) {
      c.check(
        entry.value.length == 3,
        'skillTrees.${entry.key}',
        'should have 3 branches',
      );
    }
    for (final entry in config.staffPaths.entries) {
      for (final path in entry.value) {
        c.check(
          path.tiers.length == config.staffTierCosts.length,
          'staffPaths.${entry.key}.${path.id}',
          'should have ${config.staffTierCosts.length} tiers',
        );
      }
    }
    return config;
  }

  /// Nodes in a standard branch (4 plus a capstone) and in a signature
  /// branch (3 plus a capstone).
  static const branchLength = 5;
  static const signatureLength = 4;

  final List<CrewRole> roles;

  /// Three branches per flight-crew role.
  final Map<String, List<SkillBranch>> skillTrees;
  final List<SkillBranch> signatures;

  /// Three money paths per airport-staff role.
  final Map<String, List<StaffPath>> staffPaths;

  /// Size-3 city costs; scaled with `AirportsConfig.scaledCost`.
  final List<int> staffTierCosts;
  final int maxLevel;
  final double xpBase;
  final double xpExponent;
  final int skillPointsPerLevel;
  final CrewXpConfig xp;
  final HiringConfig hiring;

  /// Crew XP needed to go from [level] to the next.
  int xpToNext(int level) => (xpBase * math.pow(level, xpExponent)).round();

  CrewRole role(String id) => roles.firstWhere(
    (r) => r.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown role'),
  );
}
