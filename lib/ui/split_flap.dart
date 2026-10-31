import 'package:flutter/material.dart';

/// Text that flips like a split-flap departures board when it changes: each
/// character that differs clatters through the drum to its new letter, the
/// columns a beat apart from left to right.
///
/// The first build shows the text at rest. While flipping, the real text
/// stays in the tree (invisible) so layout and finders see the final value.
/// With animations turned off (Reduce Motion) it changes at once.
class SplitFlapText extends StatefulWidget {
  const SplitFlapText(
    this.text, {
    required this.style,
    this.maxFlips = 6,
    this.flipTime = const Duration(milliseconds: 55),
    this.stagger = const Duration(milliseconds: 22),
    this.textAlign,
    super.key,
  });

  final String text;
  final TextStyle style;

  /// The most drum steps one character takes; longer trips skip ahead.
  final int maxFlips;

  /// How long one flap takes to fall.
  final Duration flipTime;

  /// The delay between one column starting and the next.
  final Duration stagger;

  final TextAlign? textAlign;

  /// The drum, in order. Characters not on it flip once, straight across.
  static const drum = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.,-/+\$%';

  /// The characters column [i] shows on its way from [from] to [to], ending
  /// with [to]; empty when they match.
  static List<String> steps(String from, String to, {int maxFlips = 6}) {
    if (from == to) return const [];
    final a = drum.indexOf(from);
    final b = drum.indexOf(to);
    if (a < 0 || b < 0) return [to];
    final path = <String>[];
    for (var k = a; k != b;) {
      k = (k + 1) % drum.length;
      path.add(drum[k]);
    }
    return path.length <= maxFlips
        ? path
        : path.sublist(path.length - maxFlips);
  }

  @override
  State<SplitFlapText> createState() => _SplitFlapTextState();
}

class _SplitFlapTextState extends State<SplitFlapText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);

  /// Per column: the character it starts from, then each step.
  List<List<String>> _columns = const [];

  @override
  void didUpdateWidget(SplitFlapText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    final animate =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        TickerMode.valuesOf(context).enabled;
    if (!animate) {
      _stop();
      return;
    }
    final from = _controller.isAnimating ? _frame() : old.text;
    final to = widget.text;
    final width = from.length > to.length ? from.length : to.length;
    _columns = [
      for (var i = 0; i < width; i++)
        [
          i < from.length ? from[i] : ' ',
          ...SplitFlapText.steps(
            i < from.length ? from[i] : ' ',
            i < to.length ? to[i] : ' ',
            maxFlips: widget.maxFlips,
          ),
        ],
    ];
    var longest = Duration.zero;
    for (var i = 0; i < _columns.length; i++) {
      final flips = _columns[i].length - 1;
      if (flips == 0) continue;
      final end = widget.stagger * i + widget.flipTime * flips;
      if (end > longest) longest = end;
    }
    if (longest == Duration.zero) {
      _stop();
      return;
    }
    _controller
      ..duration = longest
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _stop();
  }

  void _stop() {
    _controller.stop();
    if (_columns.isNotEmpty && mounted) setState(() => _columns = const []);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration get _elapsed => _controller.duration! * _controller.value;

  /// Where column [i] is: the character showing and how far its flap has
  /// fallen (0 to 1; at 0.5 the old character is edge-on and the new one
  /// takes over).
  (String, double) _column(int i) {
    final column = _columns[i];
    final flips = column.length - 1;
    if (flips == 0) return (column.first, 1);
    final t =
        (_elapsed - widget.stagger * i).inMicroseconds /
        widget.flipTime.inMicroseconds;
    if (t <= 0) return (column.first, 1);
    if (t >= flips) return (column.last, 1);
    final step = t.floor();
    final fall = t - step;
    return fall < 0.5
        ? (column[step], 1 - fall * 2)
        : (column[step + 1], fall * 2 - 1);
  }

  String _frame() =>
      [for (var i = 0; i < _columns.length; i++) _column(i).$1]
          .join()
          .trimRight();

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      textAlign: widget.textAlign,
      style: widget.style,
    );
    if (_columns.isEmpty) return text;
    return Stack(
      children: [
        Opacity(opacity: 0, child: text),
        Positioned.fill(
          child: ClipRect(
            child: ExcludeSemantics(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _columns.length; i++)
                        _flap(_column(i)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _flap((String, double) column) {
    final (char, open) = column;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(1, open.clamp(0.05, 1), 1),
      child: Text(
        char,
        style: widget.style.copyWith(
          color: Color.lerp(
            widget.style.color?.withValues(alpha: 0.35),
            widget.style.color,
            open,
          ),
        ),
      ),
    );
  }
}
