import 'package:flutter/material.dart';

/// Soft, flat palette. Package 8 (art and feel) refines this against the
/// mockups.
abstract final class TinyColors {
  static const sky = Color(0xFFBFE3F5);
  static const sea = Color(0xFF8CC9E8);
  static const land = Color(0xFFF3E9C9);
  static const ink = Color(0xFF23324A);
  static const accent = Color(0xFFF2994A);
  static const panel = Color(0xFFFFFFFF);
}

ThemeData buildTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: TinyColors.accent,
    surface: TinyColors.panel,
  ),
  scaffoldBackgroundColor: TinyColors.sky,
  useMaterial3: true,
);
