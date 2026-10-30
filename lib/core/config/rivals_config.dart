import 'config_reader.dart';
import 'effect.dart';

/// A named CPU airline (`assets/data/rivals.json`).
class RivalAirline {
  const RivalAirline({
    required this.id,
    required this.name,
    required this.regionId,
    required this.personality,
    required this.tier,
    required this.hubCityId,
    required this.color,
  });

  factory RivalAirline.fromConfig(ConfigReader c) {
    final rival = RivalAirline(
      id: c.string('id'),
      name: c.string('name'),
      regionId: c.string('regionId'),
      personality: c.string('personality'),
      tier: c.string('tier'),
      hubCityId: c.string('hubCityId'),
      color: c.string('color'),
    );
    c.check(
      RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(rival.color),
      'color',
      'should be a #RRGGBB colour',
    );
    return rival;
  }

  final String id;
  final String name;
  final String regionId;
  final String personality;
  final String tier;
  final String hubCityId;

  /// Livery colour as `#RRGGBB`.
  final String color;
}

class RivalTier {
  const RivalTier({
    required this.id,
    required this.name,
    required this.strengthVsPlayer,
    required this.fortifiedHubs,
  });

  factory RivalTier.fromConfig(ConfigReader c) => RivalTier(
    id: c.string('id'),
    name: c.string('name'),
    strengthVsPlayer: c.number('strengthVsPlayer'),
    fortifiedHubs: c.integer('fortifiedHubs'),
  );

  final String id;
  final String name;

  /// Multiplier on the player's growth curve (0.7 = about 30% behind).
  final double strengthVsPlayer;
  final int fortifiedHubs;
}

class RivalDifficulty {
  const RivalDifficulty({
    required this.id,
    required this.name,
    required this.tierStrength,
    required this.cityWinTimeMultiplier,
    required this.reactionSpeedMultiplier,
  });

  factory RivalDifficulty.fromConfig(ConfigReader c) => RivalDifficulty(
    id: c.string('id'),
    name: c.string('name'),
    tierStrength: c.numberMap('tierStrength'),
    cityWinTimeMultiplier: c.number('cityWinTimeMultiplier'),
    reactionSpeedMultiplier: c.number('reactionSpeedMultiplier'),
  );

  final String id;
  final String name;

  /// Strength against the player's curve for each tier id.
  final Map<String, double> tierStrength;
  final double cityWinTimeMultiplier;
  final double reactionSpeedMultiplier;
}

/// `rivals.json` rules plus the roster from `data/rivals.json`.
class RivalsConfig {
  const RivalsConfig({
    required this.personalities,
    required this.tiers,
    required this.difficulties,
    required this.defaultDifficulty,
    required this.hardModeTierShift,
    required this.offlinePace,
    required this.share,
    required this.leader,
    required this.hub,
    required this.terminal,
    required this.terminalBranches,
    required this.contracts,
    required this.rivalsRacing,
    required this.seasonLengthDays,
    required this.roster,
  });

  factory RivalsConfig.fromConfig(ConfigReader c, ConfigReader roster) {
    final terminal = c.child('terminal');
    final config = RivalsConfig(
      personalities: [
        for (final p in c.children('personalities')) p.string('id'),
      ],
      tiers: [for (final t in c.children('tiers')) RivalTier.fromConfig(t)],
      difficulties: [
        for (final d in c.children('difficulties'))
          RivalDifficulty.fromConfig(d),
      ],
      defaultDifficulty: c.string('defaultDifficulty'),
      hardModeTierShift: c.integer('hardModeTierShift'),
      offlinePace: c.number('offlinePace'),
      share: c.numberMap('share'),
      leader: c.numberMap('leader'),
      hub: c.numberMap('hub'),
      terminal: {
        for (final k in terminal.json.keys)
          if (k != 'branches') k: terminal.number(k),
      },
      terminalBranches: [
        for (final b in terminal.children('branches'))
          (
            id: b.string('id'),
            name: b.string('name'),
            nodes: [for (final n in b.children('nodes')) Effect.fromConfig(n)],
          ),
      ],
      contracts: {
        for (final k in c.child('contracts').json.keys)
          if (k != 'rivalsRacing') k: c.child('contracts').number(k),
      },
      rivalsRacing: c.child('contracts').integers('rivalsRacing'),
      seasonLengthDays: c.child('season').integer('lengthDays'),
      roster: [
        for (final r in roster.children('rivals')) RivalAirline.fromConfig(r),
      ],
    );
    for (final (name, map, keys) in [
      ('share', config.share, shareKeys),
      ('leader', config.leader, leaderKeys),
      ('hub', config.hub, hubKeys),
      ('terminal', config.terminal, terminalKeys),
      ('contracts', config.contracts, contractKeys),
    ]) {
      for (final key in keys) {
        c.check(map.containsKey(key), '$name.$key', 'is missing');
      }
    }
    final tierIds = config.tiers.map((t) => t.id).toSet();
    c.check(
      config.difficulties.any((d) => d.id == config.defaultDifficulty),
      'defaultDifficulty',
      'should name one of the difficulties',
    );
    for (final d in config.difficulties) {
      c.check(
        d.tierStrength.keys.toSet().containsAll(tierIds),
        'difficulties.${d.id}.tierStrength',
        'should cover every tier',
      );
    }
    for (var i = 0; i < config.roster.length; i++) {
      final rival = config.roster[i];
      roster.check(
        config.personalities.contains(rival.personality),
        'rivals[$i].personality',
        'is not one of ${config.personalities.join(', ')}',
      );
      roster.check(
        tierIds.contains(rival.tier),
        'rivals[$i].tier',
        'is not one of ${tierIds.join(', ')}',
      );
    }
    return config;
  }

  static const shareKeys = [
    'perCoinDelivered',
    'decayPctPerHour',
    'pathTierBonusPct',
    'terminalShareMultiplier',
    'terminalDecayMultiplier',
  ];
  static const leaderKeys = ['payPct', 'firstLookSeconds'];
  static const hubKeys = ['minSharePct', 'daysHeld', 'boardSlots'];
  static const terminalKeys = [
    'buildCostPerCitySize',
    'firstAirlineLevel',
    'extraEveryLevels',
    'jobsPerPoint',
    'maxPoints',
    'takeoverDaysLeading',
    'leaseCostFraction',
  ];
  static const contractKeys = [
    'intervalHours',
    'minIntervalHours',
    'jobsToWin',
    'prizePerCitySize',
    'shareBurstPct',
  ];

  final List<String> personalities;
  final List<RivalTier> tiers;
  final List<RivalDifficulty> difficulties;
  final String defaultDifficulty;

  /// Starting in a hard-mode region moves every rival up this many tiers.
  final int hardModeTierShift;

  /// Rivals act at this fraction of their pace while the game is closed.
  final double offlinePace;

  /// City share rules: perCoinDelivered, decayPctPerHour, pathTierBonusPct,
  /// terminalShareMultiplier, terminalDecayMultiplier.
  final Map<String, double> share;

  /// Leader perks: payPct, firstLookSeconds.
  final Map<String, double> leader;

  /// Hub status: minSharePct, daysHeld, boardSlots.
  final Map<String, double> hub;

  /// Terminal rules: buildCostPerCitySize, firstAirlineLevel,
  /// extraEveryLevels, jobsPerPoint, maxPoints, takeoverDaysLeading,
  /// leaseCostFraction.
  final Map<String, double> terminal;
  final List<({String id, String name, List<Effect> nodes})> terminalBranches;

  /// Contract rules: intervalHours, minIntervalHours, jobsToWin,
  /// prizePerCitySize, shareBurstPct.
  final Map<String, double> contracts;

  /// How many rivals race the player for each contract (min, max).
  final List<int> rivalsRacing;
  final int seasonLengthDays;
  final List<RivalAirline> roster;
}
