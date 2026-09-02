import 'dart:math' as math;
import 'dart:ui';

import '../models/arrow_kind.dart';
import '../models/arrow_piece.dart';

/// The route one fired arrow travels, and how far its tail moves along it.
///
/// One builder for both the painter and the game logic: the arrows a special
/// clears on its way out are picked by walking this same list, so what the
/// player sees being touched is exactly what fires.
class FlightPath {
  const FlightPath(this.route, this.travel);

  /// Cell coordinates, tail → head → out of the board. Consecutive points are
  /// always one cell apart, so a point's index is its distance along the route.
  final List<Offset> route;

  /// How far the tail travels over the whole flight.
  final double travel;
}

/// Builds the route for [piece]. [overshootCells] is how far past the board
/// edge the arrow keeps going, so it clears the screen and not just the card.
/// [mask] is the board's playable cells — the rainbow arrow laps *that*
/// outline, not the grid's rectangle.
FlightPath buildFlightPath(
  ArrowPiece piece, {
  required int columns,
  required int rows,
  required int overshootCells,
  Set<int> mask = const {},
}) {
  final route = List<Offset>.from(piece.cells);
  final head = piece.head;
  final dir = piece.direction.step;
  final body = (piece.cells.length - 1).toDouble();
  final exitRun = overshootCells + piece.cells.length + 2;

  bool inBoard(Offset c) =>
      c.dx >= 0 && c.dy >= 0 && c.dx < columns && c.dy < rows;

  // Cells between the head and the board edge, in the direction of travel.
  final toBorder = switch (piece.direction) {
    ArrowDirection.up => head.dy.toInt(),
    ArrowDirection.right => columns - 1 - head.dx.toInt(),
    ArrowDirection.down => rows - 1 - head.dy.toInt(),
    ArrowDirection.left => head.dx.toInt(),
  };

  switch (piece.kind) {
    // Straight out. The plain arrows, the black one and the bomb all fly this
    // way — the bomb's blast is about where it *was*, not where it goes.
    case ArrowKind.normal:
    case ArrowKind.boost:
    case ArrowKind.bomb:
      final stepsToOutside = toBorder + 1 + overshootCells;
      for (var i = 1; i <= stepsToOutside + piece.cells.length + 1; i++) {
        route.add(head + dir * i.toDouble());
      }
      return FlightPath(route, stepsToOutside + body);

    // Straight to the edge, one full lap of the boundary, then out.
    case ArrowKind.rainbow:
      var cursor = head;
      // Out to the last playable cell in front of it. On a shaped board that
      // is the edge of the *shape*, which is usually well inside the grid.
      for (var i = 0; i < toBorder; i++) {
        final next = cursor + dir;
        if (!inBoard(next)) break;
        cursor = next;
        route.add(cursor);
        if (mask.isNotEmpty &&
            !mask.contains(next.dy.toInt() * columns + next.dx.toInt())) {
          break;
        }
      }

      final ring = _silhouetteRing(mask, columns, rows);
      if (ring.length > 2) {
        // Join the outline at whichever of its cells is nearest, then run all
        // the way round it.
        var entry = 0;
        var best = double.infinity;
        for (var i = 0; i < ring.length; i++) {
          final d =
              (ring[i].dx - cursor.dx).abs() + (ring[i].dy - cursor.dy).abs();
          if (d < best) {
            best = d;
            entry = i;
          }
        }
        for (final step in _walk(cursor, ring[entry])) {
          route.add(step);
        }
        cursor = ring[entry];
        for (var k = 1; k <= ring.length; k++) {
          final next = ring[(entry + k) % ring.length];
          for (final step in _walk(cursor, next)) {
            route.add(step);
          }
          cursor = next;
        }
      }

      // Then straight out from wherever the lap ended.
      for (var i = 1; i <= exitRun + toBorder; i++) {
        route.add(cursor + dir * i.toDouble());
      }
      return FlightPath(route, (route.length - 1 - body).toDouble());

    // Three zigzags across the board, then out.
    case ArrowKind.ghost:
      final perp = piece.direction.perpendicular;
      // Alternate the first turn per arrow so two ghosts never trace the same
      // shape on the same board.
      var sign = piece.id.isEven ? 1.0 : -1.0;
      final forwardLeg = math.max(1, (toBorder / 3).floor());
      var cursor = head;

      for (var leg = 0; leg < 3; leg++) {
        if (!inBoard(cursor + perp * sign)) sign = -sign;
        for (var i = 0; i < 3; i++) {
          final next = cursor + perp * sign;
          if (!inBoard(next)) break;
          cursor = next;
          route.add(cursor);
        }
        for (var i = 0; i < forwardLeg; i++) {
          final next = cursor + dir;
          if (!inBoard(next)) break;
          cursor = next;
          route.add(cursor);
        }
        sign = -sign;
      }
      for (var i = 1; i <= exitRun + toBorder; i++) {
        route.add(cursor + dir * i.toDouble());
      }
      return FlightPath(route, (route.length - 1 - body).toDouble());
  }
}

/// The outline of the board's silhouette, as a closed walk of adjacent cells.
///
/// Every board is carved into a different shape, so the grid's rectangle is
/// mostly empty space on a circle or a star — a lap of *that* passed over
/// nothing at all. This walks the real edge instead, which means it crosses
/// the end cell of every row and every column of the shape.
///
/// A left-hand wall follower does it: stand on a boundary cell, keep trying to
/// turn left, and you hug the outside of any shape, concave corners included.
List<Offset> _silhouetteRing(Set<int> mask, int columns, int rows) {
  bool inside(int x, int y) {
    if (x < 0 || y < 0 || x >= columns || y >= rows) return false;
    return mask.isEmpty || mask.contains(y * columns + x);
  }

  // Start on the topmost, then leftmost, playable cell.
  var startX = -1;
  var startY = -1;
  for (var y = 0; y < rows && startY < 0; y++) {
    for (var x = 0; x < columns; x++) {
      if (inside(x, y)) {
        startX = x;
        startY = y;
        break;
      }
    }
  }
  if (startX < 0) return const [];

  // Clockwise: right, down, left, up.
  const dirs = [(1, 0), (0, 1), (-1, 0), (0, -1)];
  var facing = 0;
  var x = startX;
  var y = startY;
  final ring = <Offset>[Offset(x.toDouble(), y.toDouble())];
  final limit = (mask.isEmpty ? columns * rows : mask.length) * 8 + 8;

  for (var step = 0; step < limit; step++) {
    var moved = false;
    // Turn left first, then straight, then right, then back.
    for (final turn in const [3, 0, 1, 2]) {
      final next = (facing + turn) % 4;
      final nx = x + dirs[next].$1;
      final ny = y + dirs[next].$2;
      if (!inside(nx, ny)) continue;
      x = nx;
      y = ny;
      facing = next;
      moved = true;
      break;
    }
    if (!moved) break; // a lone cell with no neighbours
    if (x == startX && y == startY) break; // back where we started
    ring.add(Offset(x.toDouble(), y.toDouble()));
  }
  return ring;
}

/// Unit steps from [from] to [to], excluding [from]. Horizontal first.
Iterable<Offset> _walk(Offset from, Offset to) sync* {
  var cursor = from;
  while (cursor.dx != to.dx) {
    cursor += Offset(to.dx > cursor.dx ? 1 : -1, 0);
    yield cursor;
  }
  while (cursor.dy != to.dy) {
    cursor += Offset(0, to.dy > cursor.dy ? 1 : -1);
    yield cursor;
  }
}
