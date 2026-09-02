import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Single source of truth for every colour in the app, so the whole game reads
/// as one neon, candy-coloured set. Every colour has a light and a dark
/// variant, switched by [dark].
///
/// The whole app is built around hot pink — backdrop, board, chrome and
/// accents all sit on the same rose ramp. The *board* itself is deliberately
/// dark in both themes: the arrows are neon glow pipes (see `GamePainter`),
/// and neon only reads as neon against ink.
class GameTheme {
  /// Current theme; flipped by the in-game button and persisted in prefs.
  static bool dark = true;

  // Backdrop: blush → rose → petal (light) / deep wine → black cherry (dark).
  static Color get bgTop =>
      dark ? const Color(0xFF1C0713) : const Color(0xFFFFF2F8);
  static Color get bgMid =>
      dark ? const Color(0xFF2A0A1D) : const Color(0xFFFFE9F4);
  static Color get bgBottom =>
      dark ? const Color(0xFF150410) : const Color(0xFFFFF6FB);

  // ── The play area ────────────────────────────────────────────────────────
  // Always a deep rose-plum, so every neon arrow glows against it.
  static const boardFill = Color(0xFF4E1140);
  static const boardFillDeep = Color(0xFF2C0722);
  static const boardEdge = Color(0xFFFF5CC8);
  static const boardGlow = Color(0x66FF4DA6);

  /// Tint behind each playable cell, so the silhouette reads before play.
  static const cellTint = Color(0x1AFFFFFF);

  // Pills, buttons, dialogs sit on this card colour.
  static Color get card =>
      dark ? const Color(0xFF381029) : const Color(0xFFFFFFFF);

  // Text.
  static Color get ink =>
      dark ? const Color(0xFFFFEAF6) : const Color(0xFF7A3358);
  static Color get inkSoft =>
      dark ? const Color(0xFFD9A6C4) : const Color(0xFFB8879F);

  // Accents read well on both backdrops.
  static const accent = Color(0xFFFF4D9D); // neon bubblegum
  static const accentDeep = Color(0xFFFF2E86);
  /// The secondary accent — a lighter pink that still separates from [accent].
  static Color get lilac =>
      dark ? const Color(0xFFFF9AD5) : const Color(0xFFE86BB0);
  static const heart = Color(0xFFFF3D74);
  static const gold = Color(0xFFFFC83D);
  static const coin = Color(0xFFFFD54A);

  static Color get cardShadow =>
      dark ? const Color(0x88000000) : const Color(0x229C4C7A);

  /// Shadow cast by arrows onto the board — the board is dark, so this is a
  /// true black drop shadow in both themes.
  static const softShadow = Color(0x73000000);

  /// App text style: Google Font "Unbounded" through the google_fonts
  /// package. Going through [GoogleFonts.unbounded] per style makes the
  /// package fetch the real file for each weight — no faux bold.
  static TextStyle font({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
  }) => GoogleFonts.unbounded(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
  );
}
