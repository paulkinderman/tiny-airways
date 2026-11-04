import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/config/config_loader.dart';
import 'package:tiny_airways/core/config/config_source.dart';
import 'package:tiny_airways/core/config/game_config.dart';
import 'package:tiny_airways/logic/growth.dart';
import 'package:tiny_airways/logic/rules.dart';
import 'package:tiny_airways/ui/guide_content.dart';

import '../core/config/config_test_helpers.dart';

void main() {
  late GameConfig shipped;

  setUpAll(
    () async =>
        shipped = await ConfigLoader(DirectoryConfigSource('assets')).load(),
  );

  GuideSection section(List<GuideSection> guide, String id) =>
      guide.firstWhere((s) => s.id == id);

  GuideEntry entry(List<GuideSection> guide, String id, String title) =>
      section(guide, id).entries.firstWhere((e) => e.title == title);

  test('every section has an intro and entries, with no blanks', () {
    final guide = buildGuide(Rules(shipped));
    expect(guide.map((s) => s.id), [
      'planes',
      'levels',
      'pilots',
      'upgrades',
      'jobs',
      'weather',
      'glossary',
    ]);
    for (final s in guide) {
      expect(s.intro, isNotEmpty, reason: s.id);
      expect(s.entries, isNotEmpty, reason: s.id);
      for (final e in s.entries) {
        expect(e.text.trim(), isNotEmpty, reason: e.title);
        for (final bad in ['null', 'NaN', 'Infinity', '  ', ' .']) {
          expect(e.text, isNot(contains(bad)), reason: '${e.title}: ${e.text}');
        }
      }
    }
  });

  test('plane classes say when they unlock and which airports take them', () {
    final guide = buildGuide(Rules(shipped));
    final medium = entry(guide, 'planes', 'Medium planes');
    expect(medium.tag, 'Lv 5');
    expect(medium.text, contains('Unlock at airline level 5.'));
    expect(medium.text, contains('Need airport level 3 or higher to land.'));
    expect(medium.text, contains('Pelican P4 (Lv 5)'));
    final large = entry(guide, 'planes', 'Large planes');
    expect(large.text, contains('Unlock at airline level 20.'));
    expect(large.text, contains('Need airport level 4 or higher'));
    expect(large.text, contains('2 pilots to fly'));
    expect(
      entry(guide, 'planes', 'Small planes').text,
      contains('Land at any airport.'),
    );
    expect(
      entry(guide, 'planes', 'Airport level 3').text,
      startsWith('Takes Small and Medium planes.'),
    );
    expect(
      entry(guide, 'planes', 'Airport level 4').text,
      contains('Needs airline level 10.'),
    );
  });

  test('the guide follows the config when the numbers change', () async {
    final edited = await loadEdited('config/progression', (json) {
      final pilots = json['pilotBonusSlots'] as List;
      (pilots.first as Map)['slots'] = 3;
    });
    final airports = await loadEdited('config/airports', (json) {
      ((json['levels'] as List)[2] as Map)['maxPlaneClass'] = 'small';
    });
    final planes = await loadEdited('config/planes', (json) {
      ((json['models'] as List).firstWhere(
        (m) => (m as Map)['id'] == 'pelican_p4',
      ) as Map)['unlockLevel'] = 6;
    });
    final guide = buildGuide(
      Rules(
        GameConfig(
          economy: edited.economy,
          world: edited.world,
          planes: planes.planes,
          airports: airports.airports,
          jobs: edited.jobs,
          flights: edited.flights,
          progression: edited.progression,
          crew: edited.crew,
          weather: edited.weather,
          rivals: edited.rivals,
          extras: edited.extras,
        ),
      ),
    );
    final medium = entry(guide, 'planes', 'Medium planes');
    expect(medium.text, contains('Need airport level 4 or higher'));
    expect(medium.text, contains('Pelican P4 (Lv 6)'));
    expect(
      entry(guide, 'pilots', 'Pilot slots by level').text,
      startsWith('Lv 1: 4 · Lv 3: 7 · Lv 5: 8'),
    );
  });

  test('unlocks list every level that unlocks something', () {
    final rules = Rules(shipped);
    final growth = Growth(rules);
    final levels = section(buildGuide(rules), 'levels').entries;
    final expected = [
      1,
      for (var l = 2; l <= shipped.progression.maxLevel; l++)
        if (growth.unlocksAt(l).isNotEmpty) l,
    ];
    expect(levels.map((e) => e.level), expected);
    expect(levels.first.text, contains('Sparrow S1'));
    expect(levels.first.text, contains('Airports up to level 3'));
    final five = levels.firstWhere((e) => e.level == 5);
    expect(five.text, contains('Medium planes'));
    expect(five.text, contains('Second region license'));
  });

  test('pilots: the cap by level, licenses and continents', () {
    final guide = buildGuide(Rules(shipped));
    final hiring = shipped.crew.hiring;
    final total =
        hiring.startingPilotSlots +
        shipped.progression.pilotBonusSlots.fold(0, (a, s) => a + s.value);
    final steps = entry(guide, 'pilots', 'Pilot slots by level').text;
    expect(steps, startsWith('Lv 1: ${hiring.startingPilotSlots}'));
    expect(steps, endsWith(': $total'));
    expect(
      entry(guide, 'pilots', 'Pilot licenses').text,
      contains('The first costs 10,000, the next 20,000'),
    );
    final continents = section(
      guide,
      'pilots',
    ).entries.where((e) => e.title.endsWith('continent'));
    expect(continents, hasLength(shipped.progression.regionLicenses.length));
    expect(
      continents.first.text,
      'Unlocks at airline level 5 and costs 20,000.',
    );
  });

  test('upgrades, jobs and weather read their numbers from config', () {
    final guide = buildGuide(Rules(shipped));
    expect(
      section(guide, 'upgrades').intro,
      contains('20%, 40% and 80% of the plane\'s price'),
    );
    expect(
      entry(guide, 'upgrades', 'Cargo hold').text,
      contains('Only planes with both seats and a hold'),
    );
    expect(
      entry(guide, 'jobs', 'Board rotation').text,
      contains('every 5 minutes'),
    );
    expect(
      entry(guide, 'jobs', 'Paid refresh').text,
      contains('costs 10 x the city\'s size'),
    );
    expect(
      entry(guide, 'jobs', 'Rival first look').text,
      contains('first 60 seconds'),
    );
    expect(entry(guide, 'jobs', 'VIP').text, contains('2-hour deadline'));

    final weather = section(guide, 'weather').entries;
    expect(weather, hasLength(shipped.weather.events.length));
    final storm = weather.firstWhere((e) => e.title.startsWith('Thunderstorm'));
    expect(storm.title, 'Thunderstorm (airport closure)');
    expect(storm.text, contains('for 15 to 25 minutes'));
    expect(storm.text, contains('About 1 in 9 events'));
  });

  test('the glossary is in A to Z order', () {
    final terms = section(buildGuide(Rules(shipped)), 'glossary').entries;
    final titles = terms.map((e) => e.title).toList();
    expect(titles, [...titles]..sort());
    expect(titles, containsAll(['Gate', 'Hub', 'Layover', 'Range']));
  });
}
