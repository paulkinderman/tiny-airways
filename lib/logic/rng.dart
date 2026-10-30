/// A small seeded random number generator (mulberry32) whose whole state is
/// one 32-bit int, so it can live in the save and replay identically.
class GameRng {
  GameRng(int seed) : _state = seed & _mask;

  static const _mask = 0xFFFFFFFF;

  int _state;

  /// The state to store back into `GameState.rngState`.
  int get state => _state;

  static int _imul(int a, int b) => (a * b) & _mask;

  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t = (t ^ ((t + _imul(t ^ (t >>> 7), t | 61)) & _mask)) & _mask;
    return (t ^ (t >>> 14)) & _mask;
  }

  /// A double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// An int in [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();

  /// An int in [min, max], both inclusive.
  int between(int min, int max) => min + nextInt(max - min + 1);

  /// True with [percent] chance.
  bool chance(double percent) => nextDouble() * 100 < percent;

  bool nextBool() => nextUint32() & 1 == 1;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// Picks one of [items] with probability proportional to [weight]. Returns
  /// null when nothing has a positive weight.
  T? weighted<T>(List<T> items, double Function(T item) weight) {
    var total = 0.0;
    for (final item in items) {
      total += weight(item);
    }
    if (total <= 0) return null;
    var roll = nextDouble() * total;
    for (final item in items) {
      roll -= weight(item);
      if (roll < 0) return item;
    }
    return items.lastWhere((i) => weight(i) > 0);
  }
}
