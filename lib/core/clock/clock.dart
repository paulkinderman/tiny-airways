/// The single source of time for the whole game.
///
/// Game rules never call `DateTime.now()` directly; they ask a [Clock]. The
/// app uses [SystemClock] and tests use [FakeClock], so flights, job board
/// rotations and offline catch-up can be tested without waiting.
///
/// Every time a clock returns is in UTC.
abstract interface class Clock {
  DateTime now();
}

/// The real wall clock.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A clock that only moves when a test tells it to.
class FakeClock implements Clock {
  FakeClock([DateTime? start])
    : _now = (start ?? DateTime.utc(2026, 1, 1)).toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Moves time forward (or backward, with a negative [duration], to test
  /// clock-jump handling).
  void advance(Duration duration) => _now = _now.add(duration);

  /// Jumps straight to [time].
  void set(DateTime time) => _now = time.toUtc();
}
