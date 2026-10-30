import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/game/map/labels.dart';

void main() {
  LabelCandidate city(String id, Offset at, double priority) => LabelCandidate(
    id: id,
    point: at,
    size: const Size(60, 14),
    priority: priority,
  );

  test('overlapping labels keep the most important one', () {
    final shown = placeLabels([
      city('small', const Offset(100, 100), 1),
      city('big', const Offset(102, 101), 5),
      city('far', const Offset(400, 100), 1),
    ], 1);
    expect(shown, {'big', 'far'});
  });

  test('zooming in makes room for more labels', () {
    final candidates = [
      city('a', const Offset(100, 100), 2),
      city('b', const Offset(110, 100), 1),
    ];
    expect(placeLabels(candidates, 1), {'a'});
    expect(placeLabels(candidates, 10), {'a', 'b'});
  });
}
