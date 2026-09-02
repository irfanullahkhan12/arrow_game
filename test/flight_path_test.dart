import 'package:arowgame/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// A five-cell arrow pointing up from the middle of a 12×12 board.
ArrowPiece _arrow(ArrowKind kind) => ArrowPiece(
  id: 0,
  cells: const [
    Offset(5, 9),
    Offset(5, 8),
    Offset(5, 7),
    Offset(5, 6),
    Offset(5, 5),
  ],
  colorIndex: 0,
  kind: kind,
);

void main() {
  const columns = 12;
  const rows = 12;

  group('flight paths', () {
    for (final kind in ArrowKind.values) {
      test('${kind.name}: route is continuous and long enough', () {
        final piece = _arrow(kind);
        final path = buildFlightPath(
          piece,
          columns: columns,
          rows: rows,
          overshootCells: 6,
        );

        // It starts as the arrow itself, so the first frame is the board.
        expect(
          path.route.take(piece.cells.length).toList(),
          piece.cells,
          reason: '${kind.name} must start from the arrow on the board',
        );

        // Every step is exactly one cell — the painter measures distance
        // along this list, so a jump would make the arrow teleport.
        for (var i = 1; i < path.route.length; i++) {
          expect(
            (path.route[i] - path.route[i - 1]).distance,
            closeTo(1, 1e-9),
            reason: '${kind.name} jumps at index $i',
          );
        }

        // The tail has to be able to travel far enough for the head to reach
        // the end of the route without running off it.
        final body = (piece.cells.length - 1).toDouble();
        expect(path.travel, greaterThan(0));
        expect(path.travel + body, lessThanOrEqualTo(path.route.length - 1.0));

        // And far enough that the whole arrow clears the board.
        expect(path.travel, greaterThan(body));
      });
    }

    test('rainbow laps the real silhouette, not the grid rectangle', () {
      // A diamond: most of the 15x15 grid is outside it, which is exactly
      // where the old rectangle lap wasted its whole trip.
      const size = 15;
      final mask = <int>{};
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if ((x - 7).abs() + (y - 7).abs() <= 7) mask.add(y * size + x);
        }
      }

      final piece = ArrowPiece(
        id: 0,
        cells: const [Offset(7, 10), Offset(7, 9), Offset(7, 8)],
        colorIndex: 0,
        kind: ArrowKind.rainbow,
      );
      final path = buildFlightPath(
        piece,
        columns: size,
        rows: size,
        overshootCells: 6,
        mask: mask,
      );

      final onRoute = path.route
          .map((c) => c.dy.toInt() * size + c.dx.toInt())
          .toSet();

      // The end cell of every row of the shape is passed over — that is what
      // makes the rainbow arrow worth its price.
      for (var y = 0; y < size; y++) {
        final inRow = [
          for (var x = 0; x < size; x++)
            if (mask.contains(y * size + x)) x,
        ];
        if (inRow.isEmpty) continue;
        expect(
          onRoute,
          contains(y * size + inRow.first),
          reason: 'row \$y left end missed',
        );
        expect(
          onRoute,
          contains(y * size + inRow.last),
          reason: 'row \$y right end missed',
        );
      }

      // And it stays on the shape while lapping: the grid corners are empty
      // space, and flying over them is what the bug looked like.
      expect(onRoute, isNot(contains(0)));
      expect(onRoute, isNot(contains(size - 1)));
    });

    test('rainbow laps the whole boundary', () {
      final path = buildFlightPath(
        _arrow(ArrowKind.rainbow),
        columns: columns,
        rows: rows,
        overshootCells: 6,
      );
      // A lap of a 12×12 board is 44 cells; the straight route would be far
      // shorter than that.
      final straight = buildFlightPath(
        _arrow(ArrowKind.normal),
        columns: columns,
        rows: rows,
        overshootCells: 6,
      );
      expect(path.route.length, greaterThan(straight.route.length + 40));

      // It touches all four edges on the way round.
      final onBoard = path.route.where(
        (c) => c.dx >= 0 && c.dy >= 0 && c.dx < columns && c.dy < rows,
      );
      expect(onBoard.any((c) => c.dx == 0), isTrue);
      expect(onBoard.any((c) => c.dy == 0), isTrue);
      expect(onBoard.any((c) => c.dx == columns - 1), isTrue);
      expect(onBoard.any((c) => c.dy == rows - 1), isTrue);
    });

    test('ghost zigzags sideways before it leaves', () {
      final path = buildFlightPath(
        _arrow(ArrowKind.ghost),
        columns: columns,
        rows: rows,
        overshootCells: 6,
      );
      // The straight arrow never leaves its column; the ghost has to.
      final columnsUsed = path.route.map((c) => c.dx).toSet();
      expect(columnsUsed.length, greaterThan(3));
    });

    test('on a real shaped board the rainbow sweeps up real arrows', () {
      // Level 21 is a shaped board with 42 arrows — the case that was broken:
      // the lap went round the grid rectangle, which on a shape is empty.
      final board = LevelFactory.generate(
        level: 21,
        generation: 0,
        cleared: 0,
      );
      expect(board.mask.length, lessThan(board.columns * board.rows),
          reason: 'this level should not be a plain rectangle');

      final owner = <int, int>{};
      for (final p in board.pieces) {
        for (final c in p.cells) {
          owner[c.dy.toInt() * board.columns + c.dx.toInt()] = p.id;
        }
      }

      // Turn the arrow nearest the middle into a rainbow and fly it.
      final piece = board.pieces.first..kind = ArrowKind.rainbow;
      final path = buildFlightPath(
        piece,
        columns: board.columns,
        rows: board.rows,
        overshootCells: 6,
        mask: board.mask,
      );

      final swept = <int>{};
      for (var i = piece.cells.length; i < path.route.length; i++) {
        final cell = path.route[i];
        final id = owner[cell.dy.toInt() * board.columns + cell.dx.toInt()];
        if (id != null && id != piece.id) swept.add(id);
      }

      // A lap of the outline of a 42-arrow board has to run into a good many
      // of them. Before the fix this was routinely zero.
      expect(
        swept.length,
        greaterThan(board.pieces.length ~/ 4),
        reason: 'the lap only touched \${swept.length} of '
            '\${board.pieces.length} arrows',
      );
    });

    test('a special saved and reloaded keeps its kind', () {
      for (final kind in ArrowKind.values) {
        final restored = ArrowPiece.fromJson(_arrow(kind).toJson());
        expect(restored.kind, kind);
        expect(restored.special, kind != ArrowKind.normal);
      }
    });

    test('boards saved before the new specials still load', () {
      final legacy = {
        'id': 3,
        'c': [
          [1, 1],
          [1, 2],
          [1, 3],
        ],
        'k': 2,
        'r': false,
        'sp': true,
      };
      expect(ArrowPiece.fromJson(legacy).kind, ArrowKind.boost);
      expect(
        ArrowPiece.fromJson({...legacy, 'sp': false}).kind,
        ArrowKind.normal,
      );
    });
  });
}
