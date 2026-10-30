import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The game rules live in a pure Dart layer so they can be unit tested and
/// shared with Android unchanged. Nothing under these folders may import
/// Flutter, Flame or any UI package.
const pureDirectories = ['lib/core', 'lib/logic'];

final _forbidden = RegExp(
  r'''^import\s+['"](package:(flutter|flame|flutter_riverpod)[/_]|dart:ui)''',
  multiLine: true,
);

void main() {
  test('the logic layer has no UI imports', () {
    final offenders = <String>[];
    for (final path in pureDirectories) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final match in _forbidden.allMatches(file.readAsStringSync())) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('game code reads time from the Clock, not DateTime.now()', () {
    final offenders = <String>[];
    for (final path in pureDirectories) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('clock.dart')) continue;
        if (file.readAsStringSync().contains('DateTime.now()')) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
