import 'package:flutter/material.dart';

/// The colour system behind every in-app notification.
///
/// One accent carries the brand; four semantic colours carry meaning. Each one
/// is defined twice — a light-mode and a dark-mode value — because a green that
/// reads as "success" on white is a green that glows radioactive on black.
///
/// To rebrand, change [brand] and the four semantic pairs. Nothing else in the
/// notification widgets names a colour.
enum NotifyTone { brand, success, error, warning, info }

/// How a notification is painted.
enum NotifySkin {
  /// One flat colour. The calmest, and the cheapest to draw.
  solid,

  /// A two-stop gradient of the tone. Loudest; best for rewards and wins.
  gradient,

  /// Frosted, translucent, sitting over whatever is behind it.
  glass,
}

/// One tone resolved for the current brightness.
class NotifyPalette {
  const NotifyPalette({
    required this.base,
    required this.deep,
    required this.onColor,
    required this.surface,
    required this.title,
    required this.body,
    required this.shadow,
  });

  /// The tone itself — icon tint, accent bar, gradient start.
  final Color base;

  /// The darker end of the gradient.
  final Color deep;

  /// Text and icons drawn *on* [base] or the gradient.
  final Color onColor;

  /// The card behind the content on solid/glass skins.
  final Color surface;

  final Color title;
  final Color body;
  final Color shadow;

  /// The gradient used by [NotifySkin.gradient].
  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [base, deep],
  );
}

/// Resolves a [NotifyTone] to real colours for a brightness.
class NotifyStyle {
  const NotifyStyle._();

  // ── Brand ────────────────────────────────────────────────────────────────
  // Swap these two for another product's palette; everything else follows.
  static const brandLight = Color(0xFFFF3D8B);
  static const brandDark = Color(0xFFFF6FB0);

  static const _light = <NotifyTone, (Color, Color)>{
    NotifyTone.brand: (brandLight, Color(0xFF9B4DFF)),
    NotifyTone.success: (Color(0xFF10B981), Color(0xFF059669)),
    NotifyTone.error: (Color(0xFFEF4444), Color(0xFFDC2626)),
    NotifyTone.warning: (Color(0xFFF59E0B), Color(0xFFD97706)),
    NotifyTone.info: (Color(0xFF6366F1), Color(0xFF8B5CF6)),
  };

  // Dark mode gets lighter, less saturated tones — the same hue, but readable
  // against ink instead of paper.
  static const _dark = <NotifyTone, (Color, Color)>{
    NotifyTone.brand: (brandDark, Color(0xFFB07CFF)),
    NotifyTone.success: (Color(0xFF34D399), Color(0xFF10B981)),
    NotifyTone.error: (Color(0xFFF87171), Color(0xFFEF4444)),
    NotifyTone.warning: (Color(0xFFFBBF24), Color(0xFFF59E0B)),
    NotifyTone.info: (Color(0xFF818CF8), Color(0xFFA78BFA)),
  };

  static NotifyPalette of(NotifyTone tone, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final (base, deep) = (dark ? _dark : _light)[tone]!;
    return NotifyPalette(
      base: base,
      deep: deep,
      onColor: Colors.white,
      surface: dark ? const Color(0xFF1B1620) : Colors.white,
      title: dark ? const Color(0xFFF6F2F8) : const Color(0xFF16121A),
      body: dark ? const Color(0xFFA9A0B4) : const Color(0xFF6B6472),
      shadow: dark
          ? Colors.black.withValues(alpha: 0.55)
          : base.withValues(alpha: 0.22),
    );
  }

  /// The default icon for a tone, when the caller does not supply one.
  static IconData iconFor(NotifyTone tone) => switch (tone) {
    NotifyTone.brand => Icons.auto_awesome_rounded,
    NotifyTone.success => Icons.check_circle_rounded,
    NotifyTone.error => Icons.error_rounded,
    NotifyTone.warning => Icons.warning_rounded,
    NotifyTone.info => Icons.info_rounded,
  };

  // ── Shape ────────────────────────────────────────────────────────────────
  static const radius = 18.0;
  static const radiusSmall = 14.0;
  static const radiusPill = 999.0;

  static const padCompact = EdgeInsets.symmetric(horizontal: 14, vertical: 12);
  static const padExpanded = EdgeInsets.fromLTRB(16, 16, 16, 14);

  // ── Type ─────────────────────────────────────────────────────────────────
  static TextStyle title(NotifyPalette p, {bool onColor = false}) => TextStyle(
    color: onColor ? p.onColor : p.title,
    fontSize: 14.5,
    fontWeight: FontWeight.w800,
    height: 1.25,
    letterSpacing: -0.1,
  );

  static TextStyle body(NotifyPalette p, {bool onColor = false}) => TextStyle(
    color: onColor ? p.onColor.withValues(alpha: 0.88) : p.body,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static TextStyle meta(NotifyPalette p, {bool onColor = false}) => TextStyle(
    color: onColor ? p.onColor.withValues(alpha: 0.7) : p.body,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  static TextStyle action(Color color) => TextStyle(
    color: color,
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );

  // ── Motion ───────────────────────────────────────────────────────────────
  // The specs an animator needs, in one place. Every component uses these, so
  // changing the feel of the whole system is a two-line edit.

  /// Toast and pill: rise from below with a soft overshoot.
  static const enterDuration = Duration(milliseconds: 420);
  static const enterCurve = Curves.easeOutBack;

  /// Banners drop in without the bounce — an alert that boings reads as a toy.
  static const bannerCurve = Curves.easeOutCubic;

  /// Leaving is always faster than arriving, and never bounces.
  static const exitDuration = Duration(milliseconds: 220);
  static const exitCurve = Curves.easeInCubic;

  /// How far a toast travels on the way in, in logical pixels.
  static const slideDistance = 28.0;

  /// How long a transient notification stays before it dismisses itself.
  static const dwellShort = Duration(milliseconds: 1600); // pill
  static const dwellNormal = Duration(milliseconds: 3200); // toast
  static const dwellLong = Duration(milliseconds: 5000); // banner with action
}
