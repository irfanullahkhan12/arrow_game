import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A per-level set of arrow colours. Defaults to the neon set lifted straight
/// off the app icon; the designer generates fresh neon palettes per level, and
/// the online AI can supply its own.
class Palette {
  const Palette(this.colors);

  final List<Color> colors;

  /// The icon palette: saturated candy neons that glow on the dark board.
  static const candy = Palette([
    Color(0xFFFF3D8B), // neon pink
    Color(0xFF3ED7F0), // electric cyan
    Color(0xFFFFC61A), // sun yellow
    Color(0xFF9B4DFF), // ultraviolet
    Color(0xFF3C8CFF), // cobalt
    Color(0xFF56E03A), // laser lime
    Color(0xFFFF7A1A), // hot orange
    Color(0xFFD86BFF), // orchid
    Color(0xFF19E0A0), // mint
    Color(0xFF00C2FF), // aqua
    Color(0xFFFF5C5C), // coral red
    Color(0xFFA6F03A), // acid green
  ]);

  /// Seeded neon palette: hues spread by the golden angle so neighbouring
  /// indices are always far apart on the wheel, saturation/lightness kept in
  /// the glow zone so it matches the icon.
  factory Palette.generate(int seed) {
    final rng = math.Random(seed);
    final baseHue = rng.nextDouble() * 360;
    return Palette([
      for (var i = 0; i < 12; i++)
        HSLColor.fromAHSL(
          1,
          (baseHue + i * 137.508) % 360,
          0.86 + rng.nextDouble() * 0.14,
          0.55 + rng.nextDouble() * 0.08,
        ).toColor(),
    ]);
  }

  int get length => colors.length;

  Color color(int i) => colors[i % colors.length];

  /// Darker edge of the "gummy" arrow — keeps neighbours separated.
  Color deep(int i) => Color.lerp(color(i), const Color(0xFF2C0722), 0.52)!;

  /// Highlight running along the top of each arrow.
  Color gloss(int i) => Color.lerp(color(i), Colors.white, 0.72)!;

  /// The halo colour bleeding out around the arrow.
  Color glow(int i) => Color.lerp(color(i), Colors.white, 0.18)!;

  List<String> toHexList() => [
    for (final c in colors)
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
  ];

  static Palette? fromHexList(List<dynamic> hex) {
    final colors = <Color>[];
    for (final h in hex) {
      final s = h.toString().replaceAll('#', '');
      final v = int.tryParse(s, radix: 16);
      if (v == null || s.length != 6) return null;
      colors.add(Color(0xFF000000 | v));
    }
    return colors.length >= 4 ? Palette(colors) : null;
  }
}
