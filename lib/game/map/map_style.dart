import 'dart:ui';

/// Colours and sizes for the cartoon map, taken from the screen mockups.
/// Sizes are screen pixels; layers divide by the zoom to draw in map units.
abstract final class MapStyle {
  static const sea = Color(0xFF8ED3F5);
  static const shallows = Color(0xFF5BB6E0);
  static const wave = Color(0xB3FFFFFF);
  static const land = Color(0xFFB9E59E);
  static const coast = Color(0xFF3F8F55);
  static const lockedLand = Color(0xFFD9E2CF);
  static const lockedCoast = Color(0xFF8FA597);
  static const border = Color(0xCCFFFFFF);

  static const ink = Color(0xFF13233A);
  static const label = Color(0xFF3B4B5E);
  static const halo = Color(0xFFFFFFFF);
  static const cityDot = Color(0xFFFFFFFF);
  static const cityRing = Color(0xFF6B7F92);
  static const owned = Color(0xFF1D63C4);
  static const amber = Color(0xFFFFC53D);
  static const planeBody = Color(0xFFFFFFFF);
  static const planeWing = Color(0xFFFF9F43);
  static const shadow = Color(0x2E13233A);

  static const rangeFill = Color(0x2EFFFFFF);
  static const storm = Color(0xFF5E6E82);
  static const fog = Color(0xFFE4E9EE);
  static const snow = Color(0x66FFFFFF);
  static const heat = Color(0x40FF8A3D);
  static const jet = Color(0x14FFFFFF);

  /// Map labels use the app's bundled Rubik.
  static const font = 'Rubik';

  static const coastWidth = 2.5;
  static const shallowsOffset = 5.0;
  static const borderWidth = 2.0;
  static const labelSize = 11.0;
  static const planeSize = 30.0;
  static const rivalPlaneSize = 22.0;
}
