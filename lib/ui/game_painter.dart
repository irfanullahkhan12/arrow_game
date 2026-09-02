import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/flight_path.dart';
import '../models/arrow_piece.dart';
import '../models/palette.dart';
import '../theme/game_theme.dart';
import 'arrow_art.dart';

/// Draws the board and every arrow on it.
///
/// The arrows are modelled on the app icon: a fat rounded pipe with its own
/// neon halo, a dark rim so neighbours never merge, a bright gloss streak
/// along the top-left, a shaded underside, a wide chevron head and a white
/// bead sitting in it. Arrow thickness scales with arrow length, so a long
/// snake reads as a *bigger* piece than a short one.
class GamePainter extends CustomPainter {
  GamePainter({
    required this.columns,
    required this.rows,
    required this.pieces,
    required this.palette,
    required this.mask,
    required this.flights,
    this.overshootCells = 0,
    required this.bumpPieceId,
    required this.bumpBlockerId,
    required this.bumpStep,
    required this.bumpCells,
    required this.bump,
    this.hintPieceId,
    this.pulse,
    this.convertMode = false,
  }) : super(
         repaint: Listenable.merge([bump, ?pulse, ...flights.values]),
       );

  final int columns;
  final int rows;
  final List<ArrowPiece> pieces;
  final Palette palette;
  final Set<int> mask;

  /// Live flight animations per piece — the painter repaints straight from
  /// these (they are in `repaint`), so flying frames never rebuild widgets.
  final Map<int, Animation<double>> flights;

  /// Extra cells past the board edge a flying arrow keeps travelling, so it
  /// exits the whole screen before being removed.
  final int overshootCells;

  /// Blocked-tap feedback: [bumpPieceId] lunges [bumpCells] along [bumpStep],
  /// and [bumpBlockerId] gives a little in the same direction as it is struck.
  final int? bumpPieceId;
  final int? bumpBlockerId;
  final Offset bumpStep;
  final double bumpCells;

  /// Live bump animation — read at paint time (also in `repaint`).
  final Animation<double> bump;

  /// The arrow the hint powerup is pointing at, ringed and pulsing.
  final int? hintPieceId;

  /// Shared 0→1→0 pulse driving the hint ring and the convert-mode shimmer.
  final Animation<double>? pulse;

  /// While the player is spending a token, every ordinary arrow gets a faint
  /// golden shimmer to say "pick me".
  final bool convertMode;

  /// Blurred drop shadows are the most expensive thing here, and on a busy
  /// board they are also the least visible. Past this many arrows they go.
  static const _shadowLimit = 32;

  bool _shadows = true;

  /// A flight route only depends on the piece and the board, so it is built
  /// once per arrow rather than on every animation frame.
  final Map<int, FlightPath> _paths = {};

  FlightPath _pathFor(ArrowPiece piece) => _paths.putIfAbsent(
    piece.id,
    () => buildFlightPath(
      piece,
      columns: columns,
      rows: rows,
      overshootCells: overshootCells,
      mask: mask,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min(size.width / columns, size.height / rows);
    _shadows = pieces.length <= _shadowLimit;

    // Eased flight progress per moving piece, read fresh every repaint.
    final moving = <int, double>{
      for (final entry in flights.entries)
        entry.key: Curves.easeInOutQuart.transform(
          entry.value.value.clamp(0.0, 1.0),
        ),
    };

    _drawMaskTiles(canvas, cell);

    // Draw non-moving arrows first (back to front). The bumping arrow is held
    // back so it rides over its blocker during the collision.
    for (final piece in pieces) {
      if (piece.removed || moving.containsKey(piece.id)) continue;
      if (piece.id == bumpPieceId) continue;
      _drawArrow(canvas, piece, cell, false, 0);
    }
    for (final piece in pieces) {
      if (piece.removed || moving.containsKey(piece.id)) continue;
      if (piece.id != bumpPieceId) continue;
      _drawArrow(canvas, piece, cell, false, 0);
    }

    // Draw moving arrows on top, each at its own flight progress.
    for (final piece in pieces) {
      final progress = moving[piece.id];
      if (piece.removed || progress == null) continue;
      _drawArrow(canvas, piece, cell, true, progress);
    }
  }

  // ── Shape tiles ────────────────────────────────────────────────────────

  /// A soft tile behind every playable cell, so the board's silhouette
  /// (heart, diamond, …) is visible even before arrows move out.
  void _drawMaskTiles(Canvas canvas, double cell) {
    // Skip when the mask is the full rectangle — the card already shows it.
    if (mask.length == columns * rows) return;
    final paint = Paint()..color = GameTheme.cellTint;
    for (final index in mask) {
      final x = index % columns;
      final y = index ~/ columns;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x * cell + cell * 0.06,
            y * cell + cell * 0.06,
            cell * 0.88,
            cell * 0.88,
          ),
          Radius.circular(cell * 0.22),
        ),
        paint,
      );
    }
  }

  // ── Arrow drawing (neon glow pipes on a deep purple board) ─────────────

  void _drawArrow(
    Canvas canvas,
    ArrowPiece piece,
    double cell,
    bool isMoving,
    double progress,
  ) {
    final cellsToDraw = isMoving
        ? _movingSnakePoints(piece, progress)
        : piece.cells;

    final geometry = buildArrowGeometry(
      cells: cellsToDraw,
      cell: cell,
      sizeScale: arrowSizeScale(piece.cells.length),
    );
    if (geometry == null) return;

    // Blocked-tap nudge. The blocker gives only a fraction, so the collision
    // reads as "this one is in the way" rather than both arrows sliding.
    var nudge = Offset.zero;
    final bumpValue = bump.value;
    if (bumpValue > 0) {
      if (piece.id == bumpPieceId) {
        nudge = bumpStep * (bumpCells * bumpValue * cell);
      } else if (piece.id == bumpBlockerId) {
        nudge = bumpStep * (0.10 * bumpValue * cell);
      }
    }
    if (nudge != Offset.zero) {
      canvas.save();
      canvas.translate(nudge.dx, nudge.dy);
    }

    // Hint ring / convert-mode shimmer, under the arrow's own halo.
    final pulseValue = pulse?.value ?? 0;
    if (pulseValue > 0) {
      Color? ring;
      var width = geometry.rimW * 1.7;
      if (piece.id == hintPieceId) {
        ring = Colors.white.withValues(alpha: 0.30 + 0.45 * pulseValue);
        width = geometry.rimW * (1.7 + 0.5 * pulseValue);
      } else if (convertMode && !piece.special) {
        ring = GameTheme.gold.withValues(alpha: 0.16 + 0.20 * pulseValue);
      }
      if (ring != null) {
        canvas.drawPath(
          geometry.shaft,
          Paint()
            ..isAntiAlias = true
            ..color = ring
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              geometry.strokeW * 1.05,
            ),
        );
      }
    }

    paintArrow(
      canvas,
      geometry,
      ArrowSkin.of(
        piece.kind,
        palette: palette,
        colorIndex: piece.colorIndex,
      ),
      shadow: _shadows,
    );

    if (nudge != Offset.zero) canvas.restore();
  }

  // ── Snake animation helpers ───────────────────────────────────────────

  List<Offset> _movingSnakePoints(ArrowPiece piece, double progress) {
    final path = _pathFor(piece);
    final bodyLength = (piece.cells.length - 1).toDouble();
    final tailDistance = path.travel * progress.clamp(0.0, 1.0);
    return _slicePolyline(path.route, tailDistance, tailDistance + bodyLength);
  }

  List<Offset> _slicePolyline(
    List<Offset> route,
    double startDistance,
    double endDistance,
  ) {
    if (route.length < 2 || endDistance <= startDistance) return const [];

    final result = <Offset>[];
    var travelled = 0.0;

    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final segmentLength = (b - a).distance;
      final segmentStart = travelled;
      final segmentEnd = travelled + segmentLength;

      if (segmentEnd < startDistance) {
        travelled = segmentEnd;
        continue;
      }
      if (segmentStart > endDistance) break;

      final localStart = ((startDistance - segmentStart) / segmentLength).clamp(
        0.0,
        1.0,
      );
      final localEnd = ((endDistance - segmentStart) / segmentLength).clamp(
        0.0,
        1.0,
      );

      final startPoint = Offset.lerp(a, b, localStart)!;
      final endPoint = Offset.lerp(a, b, localEnd)!;

      if (result.isEmpty || (result.last - startPoint).distance > .001) {
        result.add(startPoint);
      }
      if ((result.last - endPoint).distance > .001) {
        result.add(endPoint);
      }

      travelled = segmentEnd;
      if (segmentEnd >= endDistance) break;
    }

    return result;
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
