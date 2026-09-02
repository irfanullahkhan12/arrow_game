/// Implicit-shape helpers, all working in normalized board coordinates where
/// x and y both run −1 … 1 and +y points *down* (the board's own axis).
///
/// Every one of these answers the same question: is this point inside the
/// outline? That is all a silhouette ever needs, which is why both the fixed
/// presets and the AI's generated designs can be built out of them.
library;

import 'dart:math' as math;

const _twoPi = math.pi * 2;

double radiusOf(double x, double y) => math.sqrt(x * x + y * y);

/// Angle folded into one repeat of a shape with [count] identical lobes.
double _fold(double x, double y, int count, double rotation) {
  final segment = _twoPi / count;
  var angle = (math.atan2(y, x) - rotation) % segment;
  if (angle < 0) angle += segment;
  return angle;
}

/// Regular polygon with [sides] sides and circumradius 1.
bool polygonContains(double x, double y, int sides, [double rotation = 0]) {
  final s = sides.clamp(3, 16);
  final r = radiusOf(x, y);
  if (r < 1e-9) return true;
  final segment = _twoPi / s;
  final angle = _fold(x, y, s, rotation) - segment / 2;
  return r <= math.cos(math.pi / s) / math.cos(angle);
}

/// Pointed star: [points] tips at radius 1, valleys at radius [inner].
bool starContains(
  double x,
  double y,
  int points,
  double inner, [
  double rotation = 0,
]) {
  final p = points.clamp(3, 16);
  final k = inner.clamp(0.2, 0.9);
  final r = radiusOf(x, y);
  if (r < 1e-9) return true;
  final segment = _twoPi / p;
  final angle = _fold(x, y, p, rotation);
  // Linear between a tip at angle 0 and a valley at half a segment.
  final t = angle <= segment / 2
      ? angle / (segment / 2)
      : (segment - angle) / (segment / 2);
  return r <= 1 + (k - 1) * t;
}

/// Rounded petals: [petals] bulges of depth [depth].
bool flowerContains(
  double x,
  double y,
  int petals,
  double depth, [
  double rotation = 0,
]) {
  final p = petals.clamp(3, 12);
  final d = depth.clamp(0.1, 0.6);
  final r = radiusOf(x, y);
  if (r < 1e-9) return true;
  final angle = math.atan2(y, x) - rotation;
  return r <= 1 - d + d * (math.cos(p * angle / 2)).abs();
}

/// Square-toothed gear: [teeth] teeth standing [depth] proud of the body.
bool gearContains(
  double x,
  double y,
  int teeth,
  double depth, [
  double rotation = 0,
]) {
  final t = teeth.clamp(4, 16);
  final d = depth.clamp(0.1, 0.5);
  final r = radiusOf(x, y);
  if (r < 1e-9) return true;
  final angle = math.atan2(y, x) - rotation;
  return r <= (math.cos(t * angle) > 0 ? 1.0 : 1 - d);
}

/// |x|^n + |y|^n ≤ 1. n = 1 is a diamond, 2 a circle, large n a square.
bool superellipseContains(double x, double y, double exponent) {
  final n = exponent.clamp(0.5, 8.0);
  return math.pow(x.abs(), n) + math.pow(y.abs(), n) <= 1.0;
}

/// A smooth wobbling outline built from cosine harmonics. Always star-shaped
/// about the centre, so it can never come apart into pieces.
bool blobContains(double x, double y, List<double> harmonics) {
  final r = radiusOf(x, y);
  if (r < 1e-9) return true;
  final angle = math.atan2(y, x);
  var edge = 1.0;
  for (var i = 0; i < harmonics.length && i < 6; i++) {
    edge += harmonics[i].clamp(-0.35, 0.35) * math.cos((i + 2) * angle);
  }
  return r <= edge.clamp(0.3, 1.0);
}

/// Plus sign ([diagonal] false) or X ([diagonal] true) with arms [arm] wide.
bool crossContains(double x, double y, double arm, bool diagonal) {
  final w = arm.clamp(0.15, 0.5);
  if (!diagonal) return x.abs() <= w || y.abs() <= w;
  final d = w * math.sqrt2;
  return (x - y).abs() <= d || (x + y).abs() <= d;
}

// ── The hand-drawn silhouettes ───────────────────────────────────────────

/// Classic implicit heart curve, y flipped so the point faces down.
bool heartContains(double x, double y) {
  final hx = x * 1.3;
  final hy = -y * 1.3 + 0.2;
  final a = hx * hx + hy * hy - 1;
  return a * a * a - hx * hx * hy * hy * hy <= 0;
}

/// A disc with a bite taken out of the right side.
bool moonContains(double x, double y) {
  final inDisc = x * x + y * y <= 1;
  final bite = (x - 0.5) * (x - 0.5) + y * y <= 0.85 * 0.85;
  return inDisc && !bite;
}

/// Two wing ellipses joined by a body, so it is always one piece.
bool butterflyContains(double x, double y) {
  final body = x.abs() <= 0.13 && y.abs() <= 0.9;
  final wx = (x.abs() - 0.46) / 0.52;
  final wy = y / 0.78;
  return body || wx * wx + wy * wy <= 1;
}

/// Flat rounded top tapering to a point at the bottom.
bool shieldContains(double x, double y) {
  final w = y <= 0
      ? 1 - 0.3 * math.pow(-y, 3)
      : math.pow(1 - y, 0.55).toDouble();
  return x.abs() <= w;
}

/// An arrow pointing up — the game's own motif as a board.
bool arrowContains(double x, double y) {
  if (y <= -0.05) return x.abs() <= (y + 1) / 0.95;
  return x.abs() <= 0.34;
}

/// Cut gem: a flat crown, a wide girdle, then a point.
bool gemContains(double x, double y) {
  final w = y <= -0.2
      ? 0.55 + 0.45 * ((y + 1) / 0.8).clamp(0.0, 1.0)
      : 1.0 - (y + 0.2) / 1.2;
  return x.abs() <= w;
}

/// Four overlapping discs — a four-leaf clover.
bool cloverContains(double x, double y) {
  const centres = [
    [0.45, 0.0],
    [-0.45, 0.0],
    [0.0, 0.45],
    [0.0, -0.45],
  ];
  for (final c in centres) {
    final dx = x - c[0];
    final dy = y - c[1];
    if (dx * dx + dy * dy <= 0.55 * 0.55) return true;
  }
  return false;
}

/// Two triangles meeting at a waist wide enough to stay connected.
bool hourglassContains(double x, double y) => x.abs() <= 0.28 + 0.72 * y.abs();

bool bowtieContains(double x, double y) => y.abs() <= 0.28 + 0.72 * x.abs();

/// An annulus: [inner] is the hole radius.
bool ringContains(double x, double y, double inner) {
  final r = radiusOf(x, y);
  return r <= 1 && r >= inner.clamp(0.2, 0.75);
}
