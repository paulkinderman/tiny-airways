import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'map/map_style.dart';
import 'tiny_airways_game.dart';

/// The world map as a widget: the Flame game plus drag to pan, pinch (or
/// scroll) to zoom, flings, taps, and the + and - buttons.
///
/// [insets] are the parts of the map covered by panels (the top bar, a
/// sheet), so jumps centre things in the part still visible and the zoom
/// buttons stay clear.
class WorldMapView extends StatefulWidget {
  const WorldMapView({
    required this.game,
    this.insets = EdgeInsets.zero,
    this.showZoomButtons = true,
    super.key,
  });

  final TinyAirwaysGame game;
  final EdgeInsets insets;
  final bool showZoomButtons;

  @override
  State<WorldMapView> createState() => _WorldMapViewState();
}

class _WorldMapViewState extends State<WorldMapView> {
  double _lastScale = 1;
  bool _pinched = false;

  @override
  void initState() {
    super.initState();
    widget.game.mapCamera.insets = widget.insets;
  }

  @override
  void didUpdateWidget(WorldMapView old) {
    super.didUpdateWidget(old);
    widget.game.mapCamera.insets = widget.insets;
  }

  @override
  Widget build(BuildContext context) {
    final camera = widget.game.mapCamera;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final factor = event.scrollDelta.dy > 0 ? 1 / 1.15 : 1.15;
                camera.zoomBy(factor, event.localPosition);
              }
            },
            child: GestureDetector(
              key: const Key('worldMap.gestures'),
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _lastScale = 1;
                _pinched = details.pointerCount > 1;
                camera.stop();
              },
              onScaleUpdate: (details) {
                if (details.pointerCount > 1) _pinched = true;
                camera.panBy(details.focalPointDelta);
                if (details.scale != _lastScale) {
                  camera.zoomBy(
                    details.scale / _lastScale,
                    details.localFocalPoint,
                  );
                  _lastScale = details.scale;
                }
              },
              onScaleEnd: (details) {
                if (!_pinched) camera.fling(details.velocity.pixelsPerSecond);
              },
              onTapUp: (details) => widget.game.tapAt(details.localPosition),
              child: GameWidget(game: widget.game),
            ),
          ),
        ),
        if (widget.showZoomButtons)
          Positioned(
            right: widget.insets.right + 12,
            top: widget.insets.top + 12,
            child: Column(
              children: [
                _ZoomButton(
                  key: const Key('worldMap.zoomIn'),
                  label: '+',
                  semantics: 'Zoom in',
                  onPressed: widget.game.zoomIn,
                ),
                const SizedBox(height: 10),
                _ZoomButton(
                  key: const Key('worldMap.zoomOut'),
                  label: '−',
                  semantics: 'Zoom out',
                  onPressed: widget.game.zoomOut,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.label,
    required this.semantics,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String semantics;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    excludeSemantics: true,
    child: Material(
      color: MapStyle.amber,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MapStyle.ink, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: MapStyle.font,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: MapStyle.ink,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
