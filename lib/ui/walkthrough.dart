import 'package:flutter/material.dart';

import 'theme.dart';
import 'ui_state.dart';
import 'widgets.dart';

/// The part of the home screen a walkthrough step points at.
enum TourSpot { none, topBar, gatePanel, navTab }

/// One card of the first-launch walkthrough.
class TourStep {
  const TourStep({
    required this.tab,
    required this.title,
    required this.body,
    this.spot = TourSpot.none,
  });

  /// The tab the home screen shows while this card is up.
  final HomeTab tab;
  final String title;
  final String body;

  /// What gets the amber outline. [TourSpot.navTab] outlines [tab]'s button.
  final TourSpot spot;
}

/// The walkthrough: one stop per main screen, ending back on the map.
const tourSteps = [
  TourStep(
    tab: HomeTab.map,
    title: 'Welcome aboard',
    body:
        'This is your world. Your home airport is on the map; pinch to zoom, '
        'drag to look around, and tap any city or plane to see it up close.',
  ),
  TourStep(
    tab: HomeTab.map,
    spot: TourSpot.topBar,
    title: 'Your airline at a glance',
    body:
        'Cash, airline level and the planes waiting at a gate. Tap the '
        'waiting count to jump to an idle plane, and the level to see what '
        'unlocks next. The trophy opens your challenges.',
  ),
  TourStep(
    tab: HomeTab.map,
    spot: TourSpot.gatePanel,
    title: 'Ready at gate',
    body:
        'Parked planes wait here. Tap Load to fill one with passengers and '
        'cargo, then tap cities on the map to pick its route and send it off. '
        'You get paid when it lands.',
  ),
  TourStep(
    tab: HomeTab.fleet,
    spot: TourSpot.navTab,
    title: 'Fleet',
    body:
        'The departures board: planes ready at a gate first, then everything '
        'in the air with its arrival time. Tap a row to find that plane.',
  ),
  TourStep(
    tab: HomeTab.crew,
    spot: TourSpot.navTab,
    title: 'Crew',
    body:
        'Every plane needs pilots, and your airline may only employ so many: '
        'level up or buy pilot licenses for more. Hire rookies and veterans, '
        'assign them to planes and airports, and spend their skill points.',
  ),
  TourStep(
    tab: HomeTab.hangar,
    spot: TourSpot.navTab,
    title: 'Hangar',
    body:
        'Buy as many planes as you like, upgrade them and give them names. '
        'A plane only flies with a pilot aboard; spare planes wait parked.',
  ),
  TourStep(
    tab: HomeTab.airports,
    spot: TourSpot.navTab,
    title: 'Airports',
    body:
        'Buy airports in new cities to grow your network, then upgrade them '
        'for more gates and better jobs.',
  ),
  TourStep(
    tab: HomeTab.map,
    title: 'Cleared for takeoff',
    body:
        'That is everything you need. Load your first plane from the gate '
        'panel and have a good flight!',
  ),
];

/// A dimmed layer over the home screen with one card per [tourSteps] entry,
/// shown once when an airline starts. Skip or the last card's button calls
/// [onDone]; [onStep] switches the home screen to each card's tab.
class Walkthrough extends StatefulWidget {
  const Walkthrough({
    required this.onStep,
    required this.onDone,
    required this.navHeight,
    required this.gatePanelHeight,
    required this.topBarHeight,
    required this.navTabs,
    super.key,
  });

  final void Function(HomeTab tab) onStep;
  final VoidCallback onDone;

  /// Layout of the home screen, so the outline lands on the right spot.
  final double navHeight;
  final double gatePanelHeight;
  final double topBarHeight;

  /// The bottom bar's tabs, left to right.
  final List<HomeTab> navTabs;

  @override
  State<Walkthrough> createState() => _WalkthroughState();
}

class _WalkthroughState extends State<Walkthrough> {
  var _index = 0;

  TourStep get _step => tourSteps[_index];
  bool get _last => _index == tourSteps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  void _show() {
    if (mounted) widget.onStep(_step.tab);
  }

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    setState(() => _index++);
    _show();
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
    _show();
  }

  Rect? _spotRect(Size size, EdgeInsets safe) {
    final navTop = size.height - safe.bottom - widget.navHeight;
    switch (_step.spot) {
      case TourSpot.none:
        return null;
      case TourSpot.topBar:
        return Rect.fromLTWH(0, safe.top, size.width, widget.topBarHeight);
      case TourSpot.gatePanel:
        return Rect.fromLTRB(
          0,
          navTop - widget.gatePanelHeight,
          size.width,
          navTop,
        );
      case TourSpot.navTab:
        final i = widget.navTabs.indexOf(_step.tab);
        if (i < 0) return null;
        final w = size.width / widget.navTabs.length;
        return Rect.fromLTWH(w * i, navTop, w, widget.navHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final spot = _spotRect(media.size, media.padding)?.deflate(3);
    // Cards about the bottom of the screen sit near the top, and the reverse,
    // so they never cover what they describe.
    final cardAtTop =
        _step.spot == TourSpot.gatePanel || _step.spot == TourSpot.navTab;
    final cardAtBottom = _step.spot == TourSpot.topBar;

    return Stack(
      key: const Key('tour'),
      children: [
        // Swallows taps so the game underneath waits for the tour.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(painter: _ScrimPainter(spot)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: cardAtTop
              ? media.padding.top + widget.topBarHeight + 24
              : cardAtBottom
              ? null
              : 0,
          bottom: cardAtBottom
              ? media.padding.bottom + widget.navHeight + 24
              : cardAtTop
              ? null
              : 0,
          child: Align(
            alignment: cardAtTop
                ? Alignment.topCenter
                : cardAtBottom
                ? Alignment.bottomCenter
                : Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _card(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card() => Material(
    color: Board.panel,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Board.line),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < tourSteps.length; i++)
                Container(
                  width: i == _index ? 14 : 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: i == _index ? Board.amber : Board.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const Spacer(),
              if (!_last)
                TextButton(
                  key: const Key('tour.skip'),
                  onPressed: widget.onDone,
                  style: TextButton.styleFrom(
                    foregroundColor: Board.muted,
                    minimumSize: const Size(44, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Skip tour'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _step.title.toUpperCase(),
            key: const Key('tour.title'),
            style: Board.flapStyle(size: 17),
          ),
          const SizedBox(height: 8),
          Text(
            _step.body,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: Board.ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Spacer(),
              if (_index > 0)
                TextButton(
                  key: const Key('tour.back'),
                  onPressed: _back,
                  style: TextButton.styleFrom(foregroundColor: Board.muted),
                  child: const Text('Back'),
                ),
              const SizedBox(width: 4),
              AmberButton(
                key: const Key('tour.next'),
                label: _last ? "Let's fly" : 'Next',
                onPressed: _next,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Dims everything but [spot], which gets an amber outline.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.spot);

  final Rect? spot;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Board.flap.withValues(alpha: 0.62);
    final spot = this.spot;
    if (spot == null) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }
    final hole = RRect.fromRectAndRadius(spot, const Radius.circular(14));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(hole),
      scrim,
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..color = Board.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.spot != spot;
}
