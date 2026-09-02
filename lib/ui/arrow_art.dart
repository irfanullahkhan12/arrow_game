import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/arrow_kind.dart';
import '../models/palette.dart';
import '../theme/game_theme.dart';

/// How one arrow is painted: body, rim, gloss and halo.
///
/// One place decides what each kind looks like, so the arrow in the specials
/// tray is the same arrow the player will see on the board.
class ArrowSkin {
  const ArrowSkin({
    required this.color,
    required this.deep,
    required this.gloss,
    required this.halo,
    required this.bead,
    this.haloAlpha = 0.50,
    this.rainbow = false,
  });

  final Color color;
  final Color deep;
  final Color gloss;
  final Color halo;
  final Color bead;
  final double haloAlpha;

  /// Paints the body with a spectrum sweep instead of a flat colour.
  final bool rainbow;

  /// The look of [kind]. Plain arrows take their colour from the board's
  /// [palette]; every special has its own fixed livery.
  factory ArrowSkin.of(ArrowKind kind, {Palette? palette, int colorIndex = 0}) {
    switch (kind) {
      case ArrowKind.normal:
        final p = palette ?? Palette.candy;
        return ArrowSkin(
          color: p.color(colorIndex),
          deep: p.deep(colorIndex),
          gloss: p.gloss(colorIndex),
          halo: p.glow(colorIndex),
          bead: Colors.white,
        );
      // Ink black under a golden halo.
      case ArrowKind.boost:
        return const ArrowSkin(
          color: Color(0xFF241E30),
          deep: Color(0xFF08050E),
          gloss: Color(0xFFA79BC0),
          halo: GameTheme.gold,
          bead: GameTheme.gold,
          haloAlpha: 0.75,
        );
      // The full spectrum swept along the body.
      case ArrowKind.rainbow:
        return const ArrowSkin(
          color: Color(0xFFFF3D8B),
          deep: Color(0xFF3A0B2C),
          gloss: Color(0xFFFFFFFF),
          halo: Color(0xFFFFFFFF),
          bead: Colors.white,
          haloAlpha: 0.62,
          rainbow: true,
        );
      // Pure white with an icy rim.
      case ArrowKind.ghost:
        return const ArrowSkin(
          color: Color(0xFFF7FBFF),
          deep: Color(0xFF6E86C4),
          gloss: Color(0xFFFFFFFF),
          halo: Color(0xFFCFE6FF),
          bead: Color(0xFF6E86C4),
          haloAlpha: 0.70,
        );
      // Hot orange over a burnt rim.
      case ArrowKind.bomb:
        return const ArrowSkin(
          color: Color(0xFFFF7A1A),
          deep: Color(0xFF641505),
          gloss: Color(0xFFFFD9A6),
          halo: Color(0xFFFFB03A),
          bead: Color(0xFFFFE9A8),
          haloAlpha: 0.72,
        );
    }
  }
}

const _spectrum = <Color>[
  Color(0xFFFF3D8B),
  Color(0xFFFF7A1A),
  Color(0xFFFFC61A),
  Color(0xFF56E03A),
  Color(0xFF00C2FF),
  Color(0xFF9B4DFF),
  Color(0xFFFF3D8B),
];

/// The paths and measurements of one arrow, worked out once so a caller can
/// add its own glow to [shaft] before the arrow itself is painted.
class ArrowGeometry {
  const ArrowGeometry({
    required this.shaft,
    required this.chevron,
    required this.strokeW,
    required this.rimW,
    required this.corner,
    required this.tip,
    required this.wingL,
    required this.backCenter,
    required this.direction,
    required this.headLen,
  });

  final Path shaft;
  final Path chevron;
  final double strokeW;
  final double rimW;
  final double corner;
  final Offset tip;
  final Offset wingL;
  final Offset backCenter;
  final Offset direction;
  final double headLen;

  /// The little pearl that sits in the arrowhead.
  Offset get bead => Offset.lerp(tip, backCenter, 0.52)!;
}

/// Arrow lengths run between these; used only to scale thickness.
const _minLen = 3;
const _maxLen = 11;

/// Thickness rides on length: a long snake is a visibly chunkier piece than a
/// short one, which is what gives the board its mix of arrow sizes.
double arrowSizeScale(int cellCount) {
  final t = ((cellCount - _minLen) / (_maxLen - _minLen)).clamp(0.0, 1.0);
  return 0.86 + 0.22 * t;
}

/// Lays out an arrow running through [cells] (cell coordinates, tail → head)
/// on a grid of [cell] pixels. Returns null if there is nothing to draw.
ArrowGeometry? buildArrowGeometry({
  required List<Offset> cells,
  required double cell,
  required double sizeScale,
}) {
  if (cells.length < 2) return null;

  Offset center(Offset p) => Offset((p.dx + .5) * cell, (p.dy + .5) * cell);

  final head = center(cells.last);
  final previous = center(cells[cells.length - 2]);
  final vector = head - previous;
  if (vector.distance <= .001) return null;

  final direction = vector / vector.distance;
  final perpendicular = Offset(-direction.dy, direction.dx);

  // Chunky, but narrow enough that two arrows in neighbouring cells never
  // touch — that gap is what keeps a packed board readable.
  final strokeW = math.max(3.0, cell * 0.30 * sizeScale);
  final rimW = strokeW * 1.34;

  // A wide, fat chevron like the app icon's: wider than the shaft, with a
  // notched back so it reads as an arrowhead and not a triangle.
  final headLen = cell * 0.46 * sizeScale;
  final headHalf = cell * 0.37 * sizeScale;
  final tip = head + direction * (cell * 0.30 * sizeScale);
  final backCenter = tip - direction * headLen;
  final notch = tip - direction * (headLen * 0.52);
  final wingL = backCenter + perpendicular * headHalf;
  final wingR = backCenter - perpendicular * headHalf;

  final chevron = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(wingL.dx, wingL.dy)
    ..lineTo(notch.dx, notch.dy)
    ..lineTo(wingR.dx, wingR.dy)
    ..close();

  // The shaft stops inside the chevron's notch so the two read as one piece.
  final shaftEnd = notch - direction * (strokeW * 0.20);
  final shaft = Path()..moveTo(center(cells.first).dx, center(cells.first).dy);
  for (var i = 1; i < cells.length - 1; i++) {
    final pt = center(cells[i]);
    shaft.lineTo(pt.dx, pt.dy);
  }
  shaft.lineTo(shaftEnd.dx, shaftEnd.dy);

  return ArrowGeometry(
    shaft: shaft,
    chevron: chevron,
    strokeW: strokeW,
    rimW: rimW,
    corner: strokeW * 0.22,
    tip: tip,
    wingL: wingL,
    backCenter: backCenter,
    direction: direction,
    headLen: headLen,
  );
}

/// Paints one arrow: neon halo, drop shadow, dark rim, body, shaded underside,
/// gloss streak, chevron sheen and the bead in the head.
void paintArrow(
  Canvas canvas,
  ArrowGeometry g,
  ArrowSkin skin, {
  bool shadow = true,
  bool halo = true,
}) {
  Shader? bodyShader;
  if (skin.rainbow) {
    final bounds = g.shaft
        .getBounds()
        .expandToInclude(g.chevron.getBounds())
        .inflate(g.strokeW);
    bodyShader = const LinearGradient(
      colors: _spectrum,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(bounds);
  }

  Paint strokePaint(
    Color c,
    double width, {
    double blur = 0,
    bool body = false,
  }) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (body && bodyShader != null) paint.shader = bodyShader;
    if (blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return paint;
  }

  /// Draws the chevron grown by [grow] on every side — fill plus a round
  /// stroke, which is what rounds off its corners.
  void chevronLayer(
    Color c,
    double grow, {
    double blur = 0,
    bool body = false,
  }) {
    final stroke = Paint()
      ..isAntiAlias = true
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = grow * 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..isAntiAlias = true
      ..color = c
      ..style = PaintingStyle.fill;
    if (body && bodyShader != null) {
      stroke.shader = bodyShader;
      fill.shader = bodyShader;
    }
    if (blur > 0) {
      stroke.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      fill.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    canvas.drawPath(g.chevron, stroke);
    canvas.drawPath(g.chevron, fill);
  }

  // 1. The neon halo — the whole reason the board is dark.
  if (halo) {
    final glow = skin.halo.withValues(alpha: skin.haloAlpha);
    canvas.drawPath(
      g.shaft,
      strokePaint(glow, g.rimW * 1.5, blur: g.strokeW * 0.85),
    );
    chevronLayer(
      glow,
      g.corner + g.strokeW * 0.42,
      blur: g.strokeW * 0.85,
    );
  }

  // 2. Drop shadow so the arrow lifts off the board.
  if (shadow) {
    canvas.save();
    canvas.translate(g.strokeW * .10, g.strokeW * .34);
    canvas.drawPath(
      g.shaft,
      strokePaint(GameTheme.softShadow, g.rimW, blur: g.strokeW * .45),
    );
    chevronLayer(GameTheme.softShadow, g.corner, blur: g.strokeW * .45);
    canvas.restore();
  }

  // 3. Darker rim — separates neighbouring arrows.
  canvas.drawPath(g.shaft, strokePaint(skin.deep, g.rimW));
  chevronLayer(skin.deep, g.corner + (g.rimW - g.strokeW) / 2);

  // 4. Body.
  canvas.drawPath(g.shaft, strokePaint(skin.color, g.strokeW, body: true));
  chevronLayer(skin.color, g.corner, body: true);

  // 5. Shaded underside, then the gloss streak along the top-left. Both are
  // offset by less than half the stroke, so neither spills past the pipe.
  canvas.save();
  canvas.translate(g.strokeW * .12, g.strokeW * .15);
  canvas.drawPath(
    g.shaft,
    strokePaint(skin.deep.withValues(alpha: 0.55), g.strokeW * .32),
  );
  canvas.restore();

  canvas.save();
  canvas.translate(-g.strokeW * .10, -g.strokeW * .14);
  canvas.drawPath(
    g.shaft,
    strokePaint(skin.gloss.withValues(alpha: 0.92), g.strokeW * .30),
  );
  canvas.restore();

  // A matching sheen on the chevron's upper wing.
  canvas.drawLine(
    Offset.lerp(g.tip, g.wingL, 0.30)! - g.direction * (g.headLen * 0.10),
    Offset.lerp(g.tip, g.wingL, 0.72)! - g.direction * (g.headLen * 0.10),
    strokePaint(skin.gloss.withValues(alpha: 0.60), g.strokeW * .24),
  );

  // 6. Head bead: a little pearl with a dark ring.
  canvas.drawCircle(g.bead, g.strokeW * .40, Paint()..color = skin.deep);
  canvas.drawCircle(g.bead, g.strokeW * .28, Paint()..color = skin.bead);
}

// ─── Preview ─────────────────────────────────────────────────────────────────

/// A single arrow of [kind], drawn exactly as it appears on the board. Used by
/// the specials tray so the player buys a picture of the real thing.
class ArrowPreview extends StatelessWidget {
  const ArrowPreview({
    super.key,
    required this.kind,
    this.height = 54,
    this.bend = true,
  });

  final ArrowKind kind;

  final double height;

  /// Draw the shaft with a corner in it, the way most board arrows run.
  final bool bend;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _ArrowPreviewPainter(kind, bend)),
    );
  }
}

class _ArrowPreviewPainter extends CustomPainter {
  _ArrowPreviewPainter(this.kind, this.bend);

  final ArrowKind kind;
  final bool bend;

  @override
  void paint(Canvas canvas, Size size) {
    // A short L-shaped arrow reading left to right, laid out on its own tiny
    // grid so it scales with the tile.
    final cells = bend
        ? const [Offset(0, 1), Offset(1, 1), Offset(2, 1), Offset(2, 0),
            Offset(3, 0)]
        : const [Offset(0, 0), Offset(1, 0), Offset(2, 0), Offset(3, 0)];

    var maxX = 0.0;
    var maxY = 0.0;
    for (final c in cells) {
      maxX = math.max(maxX, c.dx);
      maxY = math.max(maxY, c.dy);
    }
    // Leave room on the right for the chevron sticking past the last cell.
    final cell = math.min(
      size.width / (maxX + 1.7),
      size.height / (maxY + 1.15),
    );
    if (cell <= 0) return;

    final geometry = buildArrowGeometry(
      cells: cells,
      cell: cell,
      sizeScale: 1.0,
    );
    if (geometry == null) return;

    final bounds = geometry.shaft
        .getBounds()
        .expandToInclude(geometry.chevron.getBounds());
    canvas.save();
    canvas.translate(
      (size.width - bounds.width) / 2 - bounds.left,
      (size.height - bounds.height) / 2 - bounds.top,
    );
    paintArrow(canvas, geometry, ArrowSkin.of(kind), shadow: false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArrowPreviewPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.bend != bend;
}
