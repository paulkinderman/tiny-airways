import 'dart:ui';

/// A city that would like a name label.
class LabelCandidate {
  const LabelCandidate({
    required this.id,
    required this.point,
    required this.size,
    required this.priority,
    this.gap = 8,
  });

  final String id;

  /// The city's position in map units.
  final Offset point;

  /// The label's size in screen pixels.
  final Size size;

  /// Higher goes first: selected and owned cities, then bigger cities.
  final double priority;

  /// Pixels between the city's centre and the top of its label.
  final double gap;
}

/// Picks which labels to show at [zoom] so that none overlap each other or
/// another labelled city's dot. Labels sit centred under their city.
/// Returns the ids of the cities to label.
Set<String> placeLabels(Iterable<LabelCandidate> candidates, double zoom) {
  final sorted = candidates.toList()
    ..sort((a, b) => b.priority.compareTo(a.priority));
  final taken = <Rect>[];
  final placed = <String>{};
  for (final c in sorted) {
    final p = c.point * zoom;
    final label = Rect.fromLTWH(
      p.dx - c.size.width / 2,
      p.dy + c.gap,
      c.size.width,
      c.size.height,
    ).inflate(2);
    final dot = Rect.fromCircle(center: p, radius: c.gap - 1);
    if (taken.any((r) => r.overlaps(label) || r.overlaps(dot))) continue;
    taken
      ..add(label)
      ..add(dot);
    placed.add(c.id);
  }
  return placed;
}
