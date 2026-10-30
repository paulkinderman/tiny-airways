import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_airways/core/clock/clock.dart';

void main() {
  test('SystemClock returns UTC', () {
    expect(const SystemClock().now().isUtc, isTrue);
  });

  test('FakeClock only moves when told to', () {
    final clock = FakeClock(DateTime.utc(2026, 10, 30, 12));
    expect(clock.now(), DateTime.utc(2026, 10, 30, 12));

    clock.advance(const Duration(minutes: 5));
    expect(clock.now(), DateTime.utc(2026, 10, 30, 12, 5));

    clock.advance(const Duration(hours: -1));
    expect(clock.now(), DateTime.utc(2026, 10, 30, 11, 5));

    clock.set(DateTime.utc(2027));
    expect(clock.now(), DateTime.utc(2027));
  });
}
