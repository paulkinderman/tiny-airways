import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../tiny_airways_game.dart';
import '../flight_curve.dart';
import '../map_scene.dart';
import '../map_style.dart';
import '../projection.dart';
import '../sprites.dart';
import 'dots.dart';

/// Weather on the map. One instance draws the areas under the routes
/// (snowstorm and heat wave circles, fog, the jet stream band); another
/// draws the icons and countdowns on top. A forecast shows as a faded,
/// dotted outline with "in 8m"; an active event is solid with the time left.
class WeatherLayer extends Component with HasGameReference<TinyAirwaysGame> {
  WeatherLayer({required this.icons});

  final bool icons;

  final _fill = Paint();
  final _streak = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final _pills = <String, MapPill>{};

  @override
  void render(Canvas canvas) {
    final now = game.now;
    final weather = [
      for (final w in game.scene.weather)
        if (!w.isOverAt(now)) w,
    ];
    if (weather.isEmpty) return;
    final zoom = game.mapCamera.zoom;

    if (!icons) {
      for (final w in weather) {
        if (w.area case final WeatherBand band) {
          _paintBand(canvas, band, forecast: w.isForecastAt(now));
        }
      }
    }

    game.paintWorld(canvas, (visible) {
      for (final w in weather) {
        final forecast = w.isForecastAt(now);
        if (w.area is WeatherBand) {
          if (icons) _paintIcon(canvas, w, forecast, now);
          continue;
        }
        final anchor = game.weatherAnchor(w);
        if (!visible.inflate(400 / zoom + 200).contains(anchor)) continue;
        if (icons) {
          _paintIcon(canvas, w, forecast, now);
        } else {
          _paintArea(canvas, w, forecast, zoom);
        }
      }
    });
    if (icons) {
      _pills.removeWhere((id, _) => !weather.any((w) => w.id == id));
    }
  }

  void _paintArea(Canvas canvas, MapWeather w, bool forecast, double zoom) {
    switch (w.area) {
      case WeatherCluster(:final lat, :final lon, :final radiusKm):
        final ring = game.ring(lat, lon, radiusKm);
        final colour = w.eventId == 'heat_wave' ? MapStyle.heat : MapStyle.snow;
        if (!forecast) {
          _fill.color = colour;
          canvas.drawPath(Path()..addPolygon(ring, true), _fill);
        }
        drawDots(
          canvas,
          ring,
          spacing: 9 / zoom,
          radius: 1.6 / zoom,
          paint: Paint()
            ..color = forecast
                ? MapStyle.halo.withValues(alpha: 0.9)
                : colour.withValues(alpha: 0.9),
          closed: true,
        );
      case WeatherAtCity():
        if (forecast || w.eventId != 'fog') return;
        game.paintAt(canvas, game.weatherAnchor(w), () {
          _fill.color = MapStyle.fog.withValues(alpha: 0.55);
          for (final (o, r) in const [
            (Offset(-16, 4), 22.0),
            (Offset(14, 2), 24.0),
            (Offset(0, -8), 22.0),
          ]) {
            canvas.drawCircle(o, r, _fill);
          }
        });
      case WeatherBand():
        return;
    }
  }

  void _paintBand(Canvas canvas, WeatherBand band, {required bool forecast}) {
    final cam = game.mapCamera;
    final top = cam
        .worldToScreen(
          Offset(0, MapProjection.yOf(band.lat + band.halfWidthDeg)),
        )
        .dy;
    final bottom = cam
        .worldToScreen(
          Offset(0, MapProjection.yOf(band.lat - band.halfWidthDeg)),
        )
        .dy;
    final width = cam.viewport.width;
    if (bottom < 0 || top > cam.viewport.height) return;
    if (!forecast) {
      _fill.color = MapStyle.jet;
      canvas.drawRect(Rect.fromLTRB(0, top, width, bottom), _fill);
    }
    // Wind streaks drift the way the wind blows; fixed to the map so they
    // pan with it.
    final spacing = 90.0;
    final origin = cam.worldToScreen(Offset.zero).dx;
    final drift = (game.seconds * 40) % spacing * (band.eastward ? 1 : -1);
    _streak
      ..color = MapStyle.halo.withValues(alpha: forecast ? 0.35 : 0.7)
      ..strokeWidth = 2.5;
    final rows = 3;
    for (var r = 0; r < rows; r++) {
      final y = top + (bottom - top) * (r + 1) / (rows + 1);
      final stagger = r.isOdd ? spacing / 2 : 0;
      var x = (origin + drift + stagger) % spacing - spacing;
      for (; x < width + spacing; x += spacing) {
        canvas.drawLine(Offset(x, y), Offset(x + 34, y), _streak);
      }
    }
  }

  void _paintIcon(Canvas canvas, MapWeather w, bool forecast, DateTime now) {
    final anchor = game.weatherAnchor(w);
    final lift = w.area is WeatherAtCity ? -34.0 : 0.0;
    final text = forecast
        ? 'in ${formatCountdown(w.startsAt.difference(now))}'
        : formatCountdown(w.endsAt.difference(now));
    game.paintAt(canvas, anchor, () {
      canvas.translate(0, lift);
      if (forecast) {
        canvas.saveLayer(null, Paint()..color = const Color(0x99000000));
      }
      final bob = math.sin(game.seconds * 1.5 + w.id.hashCode) * 1.5;
      canvas.translate(0, bob);
      switch (w.eventId) {
        case 'thunderstorm':
          Sprites.cloud(canvas, width: 44, color: MapStyle.storm);
          canvas
            ..save()
            ..translate(2, 14);
          Sprites.bolt(canvas, 18);
          canvas.restore();
        case 'fog':
          Sprites.cloud(canvas, width: 40, color: MapStyle.fog);
          canvas
            ..save()
            ..translate(0, 14);
          Sprites.fogLines(canvas, 30, MapStyle.cityRing);
          canvas.restore();
        case 'snowstorm':
          Sprites.cloud(canvas, width: 44, color: const Color(0xFFF4F8FC));
          canvas
            ..save()
            ..translate(0, 14);
          Sprites.snowflake(canvas, 7, MapStyle.owned);
          canvas.restore();
        case 'heat_wave':
          Sprites.sun(canvas, 10);
        case _:
          // Jet stream and anything new: a wind cloud with an arrow.
          Sprites.cloud(canvas, width: 40, color: const Color(0xFFF4F8FC));
          _streak
            ..color = MapStyle.owned
            ..strokeWidth = 3;
          final area = w.area;
          final dir = area is WeatherBand && !area.eastward ? -1.0 : 1.0;
          canvas
            ..drawLine(Offset(-10 * dir, 4), Offset(10 * dir, 4), _streak)
            ..drawLine(Offset(10 * dir, 4), Offset(5 * dir, -1), _streak)
            ..drawLine(Offset(10 * dir, 4), Offset(5 * dir, 9), _streak);
      }
      if (forecast) canvas.restore();
      if (game.mapCamera.zoom >= 0.45) {
        _pill(w.id, text, forecast).paintCentred(canvas, Offset(0, -26 + bob));
      }
    });
  }

  MapPill _pill(String id, String text, bool forecast) {
    final pill = _pills[id];
    if (pill != null && pill.text == text) return pill;
    return _pills[id] = MapPill(
      text,
      background: forecast ? MapStyle.storm : MapStyle.ink,
    );
  }
}
