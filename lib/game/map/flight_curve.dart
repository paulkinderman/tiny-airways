import 'dart:math' as math;
import 'dart:ui';

import 'projection.dart';

/// The cartoon arc a plane flies between two map points.
///
/// A quadratic curve that bows away from the straight line by [bow] of its
/// length, always towards the top of the map, so routes read as arcs rather
/// than ruler lines. Positions are spaced by distance along the arc, so a
/// plane moves at an even speed. The destination is the copy of [to] closest
/// to [from], so legs across the Pacific take the short way over the date
/// line.
class FlightCurve {
  FlightCurve(Offset from, Offset to, {double bow = 0.18})
    : start = from,
      end = MapProjection.nearest(to, from) {
    final chord = end - start;
    var normal = Offset(chord.dy, -chord.dx);
    if (normal.dy > 0 || (normal.dy == 0 && normal.dx < 0)) normal = -normal;
    control = (start + end) / 2 + normal * bow;
    _buildTable();
  }

  final Offset start;
  final Offset end;
  late final Offset control;

  static const _samples = 32;
  final _lengths = List<double>.filled(_samples + 1, 0);

  double get length => _lengths.last;

  void _buildTable() {
    var previous = start;
    for (var i = 1; i <= _samples; i++) {
      final p = _bezier(i / _samples);
      _lengths[i] = _lengths[i - 1] + (p - previous).distance;
      previous = p;
    }
  }

  Offset _bezier(double t) {
    final u = 1 - t;
    return start * (u * u) + control * (2 * u * t) + end * (t * t);
  }

  Offset _tangent(double t) =>
      (control - start) * (2 * (1 - t)) + (end - control) * (2 * t);

  /// Curve parameter for a share of the distance travelled.
  double _parameter(double progress) {
    final target = progress.clamp(0.0, 1.0) * length;
    if (length == 0) return progress.clamp(0.0, 1.0);
    var lo = 0;
    var hi = _samples;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_lengths[mid] < target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _lengths[hi] - _lengths[lo];
    final f = span == 0 ? 0.0 : (target - _lengths[lo]) / span;
    return (lo + f) / _samples;
  }

  /// Where a plane is when it has flown [progress] (0 to 1) of the leg.
  Offset pointAt(double progress) => _bezier(_parameter(progress));

  /// The plane's heading at [progress], in radians clockwise from east.
  double headingAt(double progress) {
    final t = _tangent(_parameter(progress));
    if (t == Offset.zero) {
      final chord = end - start;
      return math.atan2(chord.dy, chord.dx);
    }
    return math.atan2(t.dy, t.dx);
  }

  /// Points along the arc from [fromProgress] to the end, for drawing the
  /// trail still to fly.
  List<Offset> pointsFrom(double fromProgress, {int steps = 24}) {
    final from = fromProgress.clamp(0.0, 1.0);
    return [
      for (var i = 0; i <= steps; i++) pointAt(from + (1 - from) * i / steps),
    ];
  }
}

/// How far through a leg a plane is at [now], from 0 (departing) to 1
/// (landed).
double flightProgress(DateTime departAt, DateTime arriveAt, DateTime now) {
  final total = arriveAt.difference(departAt).inMilliseconds;
  if (total <= 0) return 1;
  return (now.difference(departAt).inMilliseconds / total).clamp(0.0, 1.0);
}

/// The countdown shown over a plane: "1h 40m", "11m", "4m 12s", "42s".
String formatCountdown(Duration left) {
  if (left <= Duration.zero) return 'Landing';
  final seconds = (left.inMilliseconds / 1000).ceil();
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m >= 10) return '${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
