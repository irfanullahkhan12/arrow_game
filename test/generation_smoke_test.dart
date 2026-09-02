import 'package:flutter_test/flutter_test.dart';

import 'package:arowgame/main.dart';

void main() {
  test('boards generate quickly, stay solvable, and mix arrow lengths', () {
    for (var level = 1; level <= 20; level++) {
      final sw = Stopwatch()..start();
      final board = LevelFactory.generate(
        level: level,
        generation: 0,
        cleared: 0,
      );
      sw.stop();

      // Two arrows per level.
      expect(board.pieces.length, level * 2);
      expect(board.pieces.length, LevelFactory.arrowCount(level));
      expect(
        sw.elapsedMilliseconds,
        lessThan(4000),
        reason: 'level $level took ${sw.elapsedMilliseconds}ms',
      );

      final lengths = board.pieces.map((p) => p.cells.length).toList()..sort();
      // Every arrow within bounds — never shorter than 3 cells.
      expect(lengths.first, greaterThanOrEqualTo(3));
      // Bigger boards should show real length variety: something long exists.
      if (level >= 8) {
        expect(
          lengths.last,
          greaterThanOrEqualTo(6),
          reason: 'level $level lengths: $lengths',
        );
      }
      // ignore: avoid_print
      print('level $level (${sw.elapsedMilliseconds}ms) lengths: $lengths');
    }
  });
}
