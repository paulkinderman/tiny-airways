import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/state/game_state.dart';
import 'package:tiny_airways/logic/rules.dart';
import 'package:tiny_airways/ui/format.dart';

void main() {
  test('formatCoins groups thousands', () {
    expect(formatCoins(0), '0');
    expect(formatCoins(999), '999');
    expect(formatCoins(1000), '1,000');
    expect(formatCoins(1234567), '1,234,567');
    expect(formatCoins(-2500), '-2,500');
  });

  test('countdowns read like the mockups', () {
    expect(formatCountdown(const Duration(seconds: 45)), '45s');
    expect(formatCountdown(const Duration(minutes: 4, seconds: 12)), '4m 12s');
    expect(formatCountdown(const Duration(hours: 1, minutes: 40)), '1h 40m');
    expect(formatCountdown(const Duration(seconds: -3)), '0s');
    expect(formatMinSec(const Duration(minutes: 3, seconds: 2)), '3:02');
    expect(formatAway(const Duration(hours: 2, minutes: 14)), '2h 14m');
    expect(formatAway(const Duration(days: 1, hours: 3)), '1 day 3h');
  });

  test('distances round to whole km', () {
    expect(formatKm(1150.4), '1,150 km');
  });

  test('flight numbers come from plane ids', () {
    const plane = Plane(id: 'p3', modelId: 'sparrow_s1', cityId: 'chicago');
    expect(flightNumber(plane), 'TA 103');
  });

  test('every rule error has a message', () {
    for (final e in RuleError.values) {
      expect(ruleErrorText(e), isNotEmpty);
    }
  });
}
