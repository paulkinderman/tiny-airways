import '../core/config/game_config.dart';
import '../logic/growth.dart';
import '../logic/rules.dart';
import 'format.dart';
import 'info_cards.dart';

/// One entry in the game guide: a term or topic, a short tag beside it
/// (such as the level it unlocks at) and a paragraph or two.
class GuideEntry {
  const GuideEntry(this.title, this.text, {this.tag, this.level});

  final String title;
  final String text;
  final String? tag;

  /// The airline level this entry is about, if any, so the screen can mark
  /// the levels the player has reached.
  final int? level;
}

/// A page of the guide.
class GuideSection {
  const GuideSection({
    required this.id,
    required this.title,
    required this.intro,
    required this.entries,
  });

  final String id;
  final String title;
  final String intro;
  final List<GuideEntry> entries;
}

/// The in-game guide, written from the live game data so it never drifts
/// from the rules: every number below comes from `assets/config/`.
List<GuideSection> buildGuide(Rules rules) {
  final g = _Guide(rules);
  return [
    g.planesAndAirports(),
    g.unlocks(),
    g.pilots(),
    g.upgrades(),
    g.jobs(),
    g.weather(),
    g.glossary(),
  ];
}

class _Guide {
  _Guide(this.rules);

  final Rules rules;

  GameConfig get config => rules.config;
  Growth get growth => Growth(rules);

  // -------------------------------------------------------------------
  // Helpers

  String pct(double v) {
    final a = v.abs();
    return a == a.roundToDouble() ? '${a.round()}%' : '$a%';
  }

  String times(double v) => v == v.roundToDouble() ? '${v.round()}x' : '${v}x';

  String hours(int minutes) => minutes % 60 == 0
      ? '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}'
      : '$minutes minutes';

  /// "2-hour" or "90-minute", for a deadline.
  String deadline(int minutes) =>
      minutes % 60 == 0 ? '${minutes ~/ 60}-hour' : '$minutes-minute';

  String list(List<String> items, [String and = 'and']) =>
      switch (items.length) {
        0 => '',
        1 => items.first,
        _ =>
          '${items.sublist(0, items.length - 1).join(', ')} $and ${items.last}',
      };

  String plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  String ordinal(int n) => switch (n % 100) {
    11 || 12 || 13 => '${n}th',
    _ => switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    },
  };

  /// The lowest airport level that takes [planeClass].
  int minAirportLevel(PlaneClass planeClass) => config.airports.levels
      .firstWhere(
        (l) =>
            config.planes.planeClass(l.maxPlaneClass).rank >= planeClass.rank,
      )
      .level;

  /// The airline level needed before an airport can reach [airportLevel].
  int? airlineLevelForAirport(int airportLevel) => config
      .progression
      .airportMaxLevel
      .where((s) => s.value >= airportLevel)
      .firstOrNull
      ?.airlineLevel;

  int classUnlock(PlaneClass c) =>
      config.progression.planeClassUnlockLevel[c.id] ?? 1;

  /// Plane classes an airport of [level] takes, by name.
  List<String> classesAt(int level) {
    final rank = config.planes
        .planeClass(config.airports.level(level).maxPlaneClass)
        .rank;
    return [
      for (final c in config.planes.classes)
        if (c.rank <= rank) c.name,
    ];
  }

  String classOf(PlaneModel m) => config.planes.planeClass(m.classId).name;

  // -------------------------------------------------------------------
  // Sections

  GuideSection planesAndAirports() {
    final airports = config.airports;
    final classes = [...config.planes.classes]
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final mid = (airports.citySizeCostMultiplier.length / 2).floor();
    final costNote =
        'Costs are for a size ${mid + 1} city: from '
        '${times(airports.citySizeCostMultiplier.first)} in the smallest '
        'cities to ${times(airports.citySizeCostMultiplier.last)} in the '
        'biggest.';
    final bigCityGates = airports.extraGatesBySize.last;
    return GuideSection(
      id: 'planes',
      title: 'Planes & airports',
      intro:
          'Every plane is ${list([for (final c in classes) c.name], 'or')}. '
          'A plane can only fly to an airport whose level is high enough for '
          'its class, and new planes are delivered to one that is.',
      entries: [
        for (final c in classes)
          GuideEntry(
            '${c.name} planes',
            _classText(c),
            tag: 'Lv ${classUnlock(c)}',
            level: classUnlock(c),
          ),
        for (final l in airports.levels)
          GuideEntry(
            'Airport level ${l.level}',
            'Takes ${list(classesAt(l.level))} planes. '
                '${plural(l.gates, 'gate')}, '
                '${plural(l.jobBoardSize, 'job')} on the board, '
                '${plural(l.layoverSlots, 'layover slot')} and '
                '${plural(l.staffSlots, 'staff slot')}.'
                '${l.upgradeCost > 0 ? ' Upgrade: ${formatCoins(l.upgradeCost)}.' : ''}'
                '${switch (airlineLevelForAirport(l.level)) {
                  final a? when a > 1 => ' Needs airline level $a.',
                  _ => '',
                }}',
            tag: 'Airport ${l.level}',
            level: airlineLevelForAirport(l.level),
          ),
        GuideEntry(
          'City size',
          'Cities are size 1 to ${airports.purchasePriceBySize.length}. '
              'Bigger cities cost more to buy and upgrade, have bigger job '
              'boards and add up to ${plural(bigCityGates, 'extra gate')}. '
              '$costNote',
        ),
        const GuideEntry(
          'Hangar',
          'Each parked plane takes a gate. To free one without selling, '
              'park a plane in the hangar from its Load screen or its card: '
              'it stops using a gate and can\'t fly, and its crew can move '
              'to other planes. Bring it back to a gate from the Fleet board '
              'whenever one is free.',
        ),
        GuideEntry(
          'Selling an airport',
          'Sell an airport from the bottom of its Airport level section. It '
              'pays back ${(airports.airportSellRefund * 100).round()}% of '
              'what the airport, its levels and its upgrade paths cost. Fly '
              'every plane out first; your home airport can\'t be sold. Jobs '
              'bound there are cancelled and its staff go back to the crew '
              'room.',
        ),
        GuideEntry(
          'Special planes',
          '${list([for (final m in config.planes.specialModels) '${m.name} (${classOf(m)})'])} '
              'are built from plane parts in Challenges, Parts. They follow '
              'the same airport rules as their class and have no upgrades.',
        ),
      ],
    );
  }

  String _classText(PlaneClass c) {
    final models = [
      for (final m in config.planes.models)
        if (m.classId == c.id) m,
    ]..sort((a, b) => growth.unlockLevel(a).compareTo(growth.unlockLevel(b)));
    final airport = minAirportLevel(c);
    final airportText = airport == 1
        ? 'Land at any airport.'
        : 'Need airport level $airport or higher to land.';
    return 'Unlock at airline level ${classUnlock(c)}. $airportText '
        '${plural(c.pilotsRequired, 'pilot')} to fly'
        '${c.openCrewSeats > 0 ? ', ${plural(c.openCrewSeats, 'crew seat')}' : ', no crew seats'}. '
        '${list([for (final m in models) '${m.name} (Lv ${growth.unlockLevel(m)})'])}.';
  }

  GuideSection unlocks() {
    final p = config.progression;
    final start = [
      for (final c in config.planes.classes)
        if (classUnlock(c) <= 1) '${c.name} planes',
      for (final m in config.planes.models)
        if (growth.unlockLevel(m) <= 1) m.name,
      'Airports up to level ${p.maxAirportLevelAt(1)}',
      '${config.crew.hiring.startingPilotSlots} pilots',
    ];
    return GuideSection(
      id: 'levels',
      title: 'Unlocks by level',
      intro:
          'Deliveries earn airline XP (${formatCoins((config.jobs.airlineXpPerCoin * 100).round())} '
          'XP for every 100 coins paid). Each level unlocks something new, '
          'up to level ${p.maxLevel}.',
      entries: [
        GuideEntry('Level 1', list(start), tag: p.titleFor(1), level: 1),
        for (var l = 2; l <= p.maxLevel; l++)
          if (growth.unlocksAt(l) case final u when u.isNotEmpty)
            GuideEntry(
              'Level $l',
              u.join(' · '),
              // The title, on the levels where it changes.
              tag: p.titleFor(l) == p.titleFor(l - 1) ? null : p.titleFor(l),
              level: l,
            ),
      ],
    );
  }

  GuideSection pilots() {
    final p = config.progression;
    final hiring = config.crew.hiring;
    var slots = hiring.startingPilotSlots;
    final steps = <String>['Lv 1: $slots'];
    for (final s in p.pilotBonusSlots) {
      slots += s.value;
      steps.add('Lv ${s.airlineLevel}: $slots');
    }
    final licenses = p.regionLicenses;
    final regions = config.world.regions;
    return GuideSection(
      id: 'pilots',
      title: 'Pilots & licenses',
      intro:
          'Planes need pilots to fly. You can buy as many planes as you '
          'like, but the number of pilots you employ is capped.',
      entries: [
        GuideEntry(
          'Pilot cap',
          'You start with ${plural(hiring.startingPilotSlots, 'pilot slot')}. '
              'Airline levels add more, and each pilot license adds one.',
        ),
        GuideEntry('Pilot slots by level', steps.join(' · ')),
        GuideEntry(
          'Pilots per plane',
          '${list([for (final c in config.planes.classes) '${c.name} planes need ${plural(c.pilotsRequired, 'pilot')}'])}. '
              'A plane without enough pilots aboard stays parked.'
              '${hiring.freePilotWithPlane ? ' Each plane you buy comes with a free pilot while you have a slot.' : ''}',
        ),
        GuideEntry(
          'Pilot licenses',
          'Buy one in the Crew tab for +1 pilot slot. The first costs '
              '${formatCoins(hiring.pilotLicensePrice(0))}, the next '
              '${formatCoins(hiring.pilotLicensePrice(1))}, then '
              '${formatCoins(hiring.pilotLicensePrice(2))}: each costs '
              '${times(hiring.pilotLicensePriceGrowth)} the last.',
        ),
        GuideEntry(
          'Region licenses',
          'Your starting continent is free. Each license opens one more of '
              'the ${regions.length} continents, any one you like, in the '
              'Airports tab.',
        ),
        for (var i = 0; i < licenses.length; i++)
          GuideEntry(
            '${ordinal(i + 2)} continent',
            'Unlocks at airline level ${licenses[i].airlineLevel} and costs '
                '${formatCoins(licenses[i].cost)}.',
            tag: 'Lv ${licenses[i].airlineLevel}',
            level: licenses[i].airlineLevel,
          ),
      ],
    );
  }

  GuideSection upgrades() {
    final up = config.planes.upgrades;
    final costs = [for (final f in up.costFractionOfPrice) pct(f * 100)];
    final per = up.capacityPerLevel;
    return GuideSection(
      id: 'upgrades',
      title: 'Plane upgrades',
      intro:
          'Tap a plane in the Hangar to upgrade it. Each track has '
          '${plural(up.maxLevel, 'level')}, costing ${list(costs)} of the '
          'plane\'s price, and works even mid-flight.',
      entries: [
        GuideEntry(
          'Seats',
          '+${plural(per, 'seat')} a level. On cargo-only planes this track '
              'adds ${plural(per, 'cargo slot')} instead.',
        ),
        GuideEntry(
          'Cargo hold',
          '+${plural(per, 'cargo slot')} a level. Only planes with both seats '
              'and a hold have this track.',
        ),
        GuideEntry('Speed', '+${pct(up.speedPctPerLevel)} speed a level.'),
        GuideEntry('Range', '+${pct(up.rangePctPerLevel)} range a level.'),
      ],
    );
  }

  GuideSection jobs() {
    final j = config.jobs;
    final p = config.progression;
    final r = config.rivals;
    final s = j.special;
    final shareLevel = p.featureUnlockLevel['cityShare'];
    final specialLevel = p.featureUnlockLevel['specialJobs'];
    final antarctic = config.world.regions
        .where((x) => x.outboundPayMultiplier != 1)
        .toList();
    String role(String? id) => id == null
        ? ''
        : config.crew.roles
              .firstWhere((x) => x.id == id, orElse: () => config.crew.roles[0])
              .name
              .toLowerCase();
    String model(String? id) => id == null || !config.planes.hasModel(id)
        ? ''
        : config.planes.model(id).name;
    return GuideSection(
      id: 'jobs',
      title: 'Jobs & rivals',
      intro:
          'Each airport you own has a job board. Passenger jobs take a seat; '
          'cargo jobs take a cargo slot.',
      entries: [
        GuideEntry(
          'Board rotation',
          'Boards get a batch of new jobs every '
              '${plural(j.boardRotationMinutes, 'minute')}, even while you are '
              'away: more at bigger, higher-level airports. A job waits '
              '${plural(j.boardRotationMinutes * j.jobLifetimeRotations, 'minute')}, '
              'then leaves, so jobs to the same city pile up while you plan.',
        ),
        GuideEntry(
          'Paid refresh',
          'Tap New jobs in the loading sheet to swap the whole board at once. It '
              'costs ${formatCoins(j.refreshCostPerCitySize)} x the city\'s '
              'size (a terminal\'s Gates branch makes it cheaper).',
        ),
        GuideEntry(
          'Rival first look',
          'When a rival airline leads a city\'s share, the jobs each rotation '
              'brings are theirs for the first '
              '${plural(r.leader['firstLookSeconds']!.round(), 'second')}, '
              'then they reach your board. Lead the city yourself and its jobs '
              'pay +${pct(r.leader['payPct']!)}.',
          tag: shareLevel == null ? null : 'Lv $shareLevel',
          level: shareLevel,
        ),
        GuideEntry(
          'Charter',
          'Fill every seat with passengers going to one city: they all pay '
              '+${pct(j.charterBonusPct)}.',
        ),
        GuideEntry(
          'Hot destinations',
          'Each board favours a few of your airports, nearer, bigger and '
              'higher-level ones more often, and sends most of its jobs there. They change every '
              '${j.hotRotations * j.boardRotationMinutes} minutes. Boards grow as '
              'your airline does, and now and then a rotation brings enough '
              'jobs to one hot destination to fill a plane there.',
        ),
        GuideEntry(
          'Group bookings',
          'Some passenger jobs are a group of 2 to ${j.groupMaxSize} that '
              'fly together and pay per seat. Bigger planes make them more '
              'common.',
        ),
        GuideEntry(
          'Full hold',
          'Fill every cargo slot with cargo going to one city: it all pays '
              '+${pct(j.fullHoldBonusPct)}.',
        ),
        GuideEntry(
          'Layovers',
          'Press and hold a job to drop it at another of your airports and '
              'carry it on later. It waits up to '
              '${hours(j.connectionExpiryMinutes)} in a layover slot.',
        ),
        GuideEntry(
          'Long trips',
          'Legs between continents pay +${pct(config.world.crossRegionPayPct)}.'
              '${antarctic.isEmpty ? '' : ' Legs leaving ${list([for (final a in antarctic) a.name])} pay ${times(antarctic.first.outboundPayMultiplier)}.'}',
        ),
        GuideEntry(
          'Rush',
          'Pays ${times(s['rush']!.payMultiplier)}, but it goes on the next '
              'plane out: when any plane leaves that airport, rush jobs still '
              'on the board are gone.',
          tag: specialLevel == null ? null : 'Lv $specialLevel',
          level: specialLevel,
        ),
        GuideEntry(
          'VIP',
          'Pays ${times(s['vip']!.payMultiplier)} with a '
              '${deadline(s['vip']!.deadlineMinutes ?? 0)} deadline. Much more '
              'common at airports with a VIP lounge (Passenger path).',
          tag: specialLevel == null ? null : 'Lv $specialLevel',
          level: specialLevel,
        ),
        GuideEntry(
          'Fragile',
          'Pays ${times(s['fragile']!.payMultiplier)} and needs a '
              '${role(s['fragile']!.requiresRole)} aboard.',
          tag: specialLevel == null ? null : 'Lv $specialLevel',
          level: specialLevel,
        ),
        GuideEntry(
          'Bulk crate',
          'Pays ${times(s['bulk']!.payMultiplier)} and takes '
              '${plural(s['bulk']!.slots, 'cargo slot')}. Appears at '
              'airports with a freight yard (Cargo path).',
        ),
        GuideEntry(
          'Sightseeing',
          'Pays ${times(s['sightseeing']!.payMultiplier)}; only the '
              '${model(s['sightseeing']!.requiresModel)} can fly it.',
        ),
      ],
    );
  }

  GuideSection weather() {
    final w = config.weather;
    final total = w.events.fold<double>(0, (a, e) => a + e.weight);
    String area(String a) => switch (a) {
      'airport' => 'one airport',
      'cluster' => 'cities within ${formatCoins(w.clusterRadiusKm)} km',
      _ => 'a band across the map',
    };
    String length(int min, int max) =>
        min == max ? hours(min) : '$min to $max minutes';
    return GuideSection(
      id: 'weather',
      title: 'Weather',
      intro:
          'Each continent you fly in gets a weather event every '
          '${w.minIntervalMinutes} to ${w.maxIntervalMinutes} minutes, shown '
          'on the map ${plural(w.forecastMinutes, 'minute')} before it starts. '
          'Tap a weather icon to see what it does.',
      entries: [
        for (final e in w.events)
          GuideEntry(
            e.closesAirport ? '${e.name} (airport closure)' : e.name,
            '${weatherEffectText(config, e.id)} Covers ${area(e.area)} for '
            '${length(e.minMinutes, e.maxMinutes)}. About 1 in '
            '${(total / e.weight).round()} events.',
          ),
      ],
    );
  }

  GuideSection glossary() {
    final p = config.progression;
    final r = config.rivals;
    final terms = <GuideEntry>[
      const GuideEntry(
        'Airline level',
        'Your airline\'s rank, shown in the top bar. Tap it to see your XP '
            'and what the next levels unlock.',
      ),
      const GuideEntry(
        'Airport level',
        'How big an airport is: its gates, job board and the largest plane '
            'class that can land. Upgrade it in the Airports tab.',
      ),
      const GuideEntry(
        'Cargo slot',
        'Room for one cargo job in a plane\'s hold.',
      ),
      GuideEntry(
        'City share',
        'How much of a city\'s traffic you carry against rival airlines. '
            'Deliveries there raise it; it fades slowly over time.',
        tag: 'Lv ${p.featureUnlockLevel['cityShare']}',
        level: p.featureUnlockLevel['cityShare'],
      ),
      const GuideEntry(
        'Connecting job',
        'A job waiting on a layover, part of the way to where it is going.',
      ),
      GuideEntry(
        'Crew seat',
        'A spot on a plane for crew other than pilots, such as a navigator '
            'or loadmaster. ${list([for (final c in config.planes.classes)
              if (c.openCrewSeats > 0) c.name])} '
            'planes have them.',
      ),
      const GuideEntry(
        'Gate',
        'A parking spot. Each plane parked or loading at an airport uses one.',
      ),
      GuideEntry(
        'Hub',
        'A city where you hold ${pct(r.hub['minSharePct']!)} share for '
            '${plural(r.hub['daysHeld']!.round(), 'day')} in a row. It adds '
            'a job to the board and lets you build a terminal.',
      ),
      GuideEntry(
        'Layover',
        'A job dropped at another of your airports on its way, to be picked '
            'up by another plane. It waits up to '
            '${hours(config.jobs.connectionExpiryMinutes)}.',
      ),
      const GuideEntry(
        'Leader',
        'The airline with the biggest share of a city.',
      ),
      const GuideEntry(
        'Pilot license',
        'Bought in the Crew tab: room for one more pilot on staff.',
      ),
      const GuideEntry(
        'Region license',
        'Opens another continent, so you can buy airports there.',
      ),
      const GuideEntry(
        'Range',
        'How far a plane flies in one leg. Jobs further away go on a '
            'layover or need a stop on the way.',
      ),
      const GuideEntry('Seat', 'Room for one passenger job.'),
      GuideEntry(
        'Terminal',
        'Built at a hub from airline level '
            '${r.terminal['firstAirlineLevel']!.round()}, with its own tree '
            'of bonuses.',
        tag: 'Lv ${r.terminal['firstAirlineLevel']!.round()}',
        level: r.terminal['firstAirlineLevel']!.round(),
      ),
      const GuideEntry(
        'Title',
        'The name under your level in the top bar. It changes as you level '
            'up.',
      ),
      GuideEntry(
        'Upgrade path',
        '${list([for (final x in config.airports.paths) x.name], 'or')}: '
            '${plural(config.airports.pathTierCosts.length, 'tier')} of '
            'bonuses you buy for one airport.',
      ),
      const GuideEntry(
        'XP',
        'Experience. Your airline earns it from every delivery; crew earn '
            'their own and spend it in their skill trees.',
      ),
    ];
    terms.sort((a, b) => a.title.compareTo(b.title));
    return GuideSection(
      id: 'glossary',
      title: 'Glossary',
      intro: 'The words the game uses, A to Z.',
      entries: terms,
    );
  }
}
