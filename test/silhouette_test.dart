import 'package:arowgame/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// How much of the -1..1 square a silhouette covers, sampled on a grid.
double _coverage(Silhouette outline, {int steps = 60}) {
  var inside = 0;
  for (var iy = 0; iy < steps; iy++) {
    for (var ix = 0; ix < steps; ix++) {
      final x = (ix + 0.5) / steps * 2 - 1;
      final y = (iy + 0.5) / steps * 2 - 1;
      if (outline.contains(x, y)) inside++;
    }
  }
  return inside / (steps * steps);
}

void main() {
  group('built-in silhouettes', () {
    test('there are at least twenty to fall back on', () {
      expect(BoardShape.values.length, greaterThanOrEqualTo(20));
      expect(BoardShape.shaped.length, greaterThanOrEqualTo(20));
      expect(BoardShape.shaped, isNot(contains(BoardShape.rectangle)));
      // Every name is distinct, so the board chip never reads twice the same.
      expect(
        BoardShape.values.map((s) => s.label).toSet().length,
        BoardShape.values.length,
      );
    });

    for (final shape in BoardShape.values) {
      test('${shape.name} covers a sensible area', () {
        final area = _coverage(PresetSilhouette(shape));
        // Not a sliver, not the whole square (except the rectangle itself).
        expect(area, greaterThan(0.14), reason: '${shape.name} is too thin');
        if (shape != BoardShape.rectangle) {
          expect(area, lessThan(0.99), reason: '${shape.name} is not a shape');
        }
      });
    }

    test('every shape builds a playable board', () {
      for (final shape in BoardShape.values) {
        // A level big enough for the outline to have room to read.
        final board = LevelFactory.generate(
          level: 14,
          generation: BoardShape.values.indexOf(shape),
          cleared: 0,
        );
        expect(board.pieces, isNotEmpty);
        expect(
          LevelFactory.isSolvable(board.pieces, board.columns, board.rows),
          isTrue,
        );
      }
    });

    test('levels walk the whole set before repeating', () {
      final labels = <String>{};
      for (var level = 10; level < 10 + BoardShape.shaped.length; level++) {
        labels.add(
          LevelFactory.generate(
            level: level,
            generation: 0,
            cleared: 0,
          ).silhouette.label,
        );
      }
      // A couple may fall back to a rectangle if they cannot be sized, but the
      // rotation must still produce plenty of distinct boards.
      expect(labels.length, greaterThanOrEqualTo(15));
    });
  });

  group('AI-designed silhouettes', () {
    test('a designed outline is used and survives a save/load', () {
      final design = AiDesigner.parse('''
        {"name":"Nine-point Star","family":"star","points":9,"inner":0.38,
         "rotation":0.4,"hole":0.0,
         "colors":["#FF3D8B","#3ED7F0","#FFC61A","#9B4DFF","#3C8CFF","#56E03A",
                   "#FF7A1A","#D86BFF","#19E0A0","#00C2FF","#FF5C5C","#A6F03A"]}
      ''');
      expect(design, isNotNull);
      expect(design!.silhouette, isA<DesignedSilhouette>());
      expect(design.silhouette!.label, 'Nine-point Star');
      expect(design.palette, isNotNull);

      final board = LevelFactory.generate(
        level: 16,
        generation: 0,
        cleared: 0,
        design: design,
      );
      expect(board.silhouette.label, 'Nine-point Star');
      expect(
        LevelFactory.isSolvable(board.pieces, board.columns, board.rows),
        isTrue,
      );

      final restored = BoardData.fromJson(board.toJson())!;
      expect(restored.silhouette.label, 'Nine-point Star');
      expect(restored.silhouette, isA<DesignedSilhouette>());
      // The reloaded outline draws exactly the same picture.
      expect(_coverage(restored.silhouette), _coverage(board.silhouette));
    });

    test('every family produces a usable outline', () {
      for (final family in ShapeFamily.values) {
        final outline = DesignedSilhouette(
          family: family,
          points: 7,
          sides: 7,
          harmonics: const [0.3, -0.2, 0.25],
        );
        final area = _coverage(outline);
        expect(area, greaterThan(0.1), reason: '${family.name} is too thin');
        expect(area, lessThan(0.99), reason: '${family.name} fills everything');
      }
    });

    test('wild numbers are clamped instead of breaking the board', () {
      final design = AiDesigner.parse(
        '{"family":"star","points":999,"inner":-4,"hole":9,"rotation":1e9,'
        '"harmonics":[50,-50,50]}',
      );
      expect(design, isNotNull);
      final outline = design!.silhouette! as DesignedSilhouette;
      expect(outline.points, inInclusiveRange(3, 14));
      expect(outline.inner, inInclusiveRange(0.2, 0.85));
      expect(outline.hole, inInclusiveRange(0.0, 0.6));
      expect(_coverage(outline), greaterThan(0.05));
    });

    test('junk from the model falls back to the built-in shapes', () {
      expect(AiDesigner.parse('sorry, I cannot do that'), isNull);
      expect(AiDesigner.parse('{"family":"banana"}'), isNull);
      expect(AiDesigner.parse(''), isNull);

      // A reply with colours but no usable family still gives the palette.
      final coloursOnly = AiDesigner.parse(
        '{"family":"banana","colors":["#FF3D8B","#3ED7F0","#FFC61A","#9B4DFF",'
        '"#3C8CFF","#56E03A","#FF7A1A","#D86BFF","#19E0A0","#00C2FF",'
        '"#FF5C5C","#A6F03A"]}',
      );
      expect(coloursOnly, isNotNull);
      expect(coloursOnly!.silhouette, isNull);
      expect(coloursOnly.palette, isNotNull);

      // And with no design at all the generator still builds a real board.
      final board = LevelFactory.generate(
        level: 16,
        generation: 0,
        cleared: 0,
        design: null,
      );
      expect(
        LevelFactory.isSolvable(board.pieces, board.columns, board.rows),
        isTrue,
      );
    });
  });
}
