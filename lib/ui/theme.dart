import 'package:flutter/material.dart';

/// The departure-board palette from the screen mockups: a dark ground, amber
/// flap text and soft panels. Body text is Rubik and the board's capitals are
/// JetBrains Mono, both bundled in `assets/fonts/`.
abstract final class Board {
  static const ground = Color(0xFF0E141C);
  static const panel = Color(0xFF18212D);
  static const raised = Color(0xFF1F2A38);
  static const line = Color(0xFF2A3646);
  static const flap = Color(0xFF0B1017);
  static const ink = Color(0xFFF4F1E8);
  static const muted = Color(0xFF9FB0C2);
  static const amber = Color(0xFFFFC53D);
  static const amberInk = Color(0xFF1B1405);
  static const cargo = Color(0xFFFF9F43);
  static const cargoInk = Color(0xFFFFB27A);
  static const cargoChip = Color(0xFF3A2616);
  static const pax = Color(0xFF8CC8FF);
  static const good = Color(0xFF5FD39A);
  static const bad = Color(0xFFFF7A70);

  /// The board's capitals: uppercase, monospace, spaced out.
  static const mono = 'JetBrains Mono';
  static const monoFallback = ['Menlo', 'Courier', 'monospace'];

  /// Everything else: rounded, friendly sans.
  static const sans = 'Rubik';

  static TextStyle flapStyle({
    double size = 14,
    Color color = amber,
    FontWeight weight = FontWeight.w700,
  }) => TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: size * 0.08,
    color: color,
  );
}

ThemeData buildTheme() => ThemeData(
  brightness: Brightness.dark,
  fontFamily: Board.sans,
  colorScheme: const ColorScheme.dark(
    primary: Board.amber,
    onPrimary: Board.amberInk,
    secondary: Board.cargo,
    surface: Board.panel,
    onSurface: Board.ink,
    error: Board.bad,
  ),
  scaffoldBackgroundColor: Board.ground,
  dividerColor: Board.line,
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Board.raised,
    contentTextStyle: TextStyle(color: Board.ink, fontSize: 14),
    behavior: SnackBarBehavior.floating,
  ),
  useMaterial3: true,
);
