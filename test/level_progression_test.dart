import 'package:flutter_test/flutter_test.dart';
import 'package:arowgame/main.dart';

void main() {
  test('every level builds fast, fills the board and stays solvable', () {
    var worst = 0;
    var worstFill = 100;
    // Share of arrows that can fire on turn one, per level.
    final openness = <int, double>{};
    for (var level = 1; level <= 60; level++) {
      for (var gen = 0; gen < 3; gen++) {
        final sw = Stopwatch()..start();
        final board = LevelFactory.generate(
          level: level,
          generation: gen,
          cleared: 0,
        );
        sw.stop();
        worst = sw.elapsedMilliseconds > worst ? sw.elapsedMilliseconds : worst;

        expect(board.pieces.length, LevelFactory.arrowCount(level));
        expect(
          LevelFactory.isSolvable(board.pieces, board.columns, board.rows),
          isTrue,
          reason: 'level $level gen $gen not solvable',
        );
        expect(
          sw.elapsedMilliseconds,
          lessThan(2500),
          reason: 'level $level gen $gen took ${sw.elapsedMilliseconds}ms',
        );

        final cells = board.pieces.fold<int>(0, (a, p) => a + p.cells.length);
        final fill = (cells / board.mask.length * 100).round();
        worstFill = fill < worstFill ? fill : worstFill;

        // How many arrows can fire at the very start: the opening is the
        // clearest single read on how hard a board feels.
        final openMoves = board.pieces
            .where(
              (p) => !LevelFactory.isBlocked(
                p,
                board.pieces,
                board.columns,
                board.rows,
              ),
            )
            .length;
        if (gen == 0) openness[level] = openMoves / board.pieces.length;

        if (gen == 0) {
          final lengths = board.pieces.map((p) => p.cells.length).toList()
            ..sort();
          final small = lengths.where((l) => l < 4).length;
          // ignore: avoid_print
          print(
            'L$level n=${board.pieces.length} '
            '${board.columns}x${board.rows} ${board.silhouette.label} '
            'fill=$fill% open=$openMoves small=$small '
            'lengths=${lengths.first}..${lengths.last} '
            '(${sw.elapsedMilliseconds}ms)',
          );
        }
      }
    }
    double meanOpenness(Iterable<int> levels) {
      final values = [for (final l in levels) openness[l]!];
      return values.reduce((a, b) => a + b) / values.length;
    }

    final early = meanOpenness([for (var l = 1; l <= 4; l++) l]);
    final late = meanOpenness([for (var l = 20; l <= 60; l++) l]);

    // ignore: avoid_print
    print(
      'worst generation time: ${worst}ms, thinnest board: $worstFill%, '
      'openness early=${early.toStringAsFixed(2)} '
      'late=${late.toStringAsFixed(2)}',
    );
    expect(worstFill, greaterThanOrEqualTo(70));

    // The difficulty curve, in one line: a beginner can tap almost any arrow,
    // and by level 20 they have to find the one move that works.
    expect(early, greaterThan(0.75), reason: 'early levels must be forgiving');
    expect(late, lessThan(0.35), reason: 'late levels must be tight');
    expect(late, lessThan(early - 0.4), reason: 'difficulty must actually ramp');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
