import 'dart:io';

import 'package:arowgame/main.dart';
import 'package:arowgame/services/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A missing sound asset is silent at runtime — no crash, no log, just an
/// arrow that fires without a noise. So the mapping is checked here instead.
void main() {
  ArrowPiece arrow(ArrowKind kind, {int length = 6}) => ArrowPiece(
    id: 0,
    cells: [for (var i = 0; i < length; i++) Offset(0, i.toDouble())],
    colorIndex: 0,
    kind: kind,
  );

  test('every arrow kind fires its own sound', () {
    expect(SoundService.sampleFor(arrow(ArrowKind.boost)), contains('black'));
    expect(
      SoundService.sampleFor(arrow(ArrowKind.rainbow)),
      contains('rainbow'),
    );
    expect(SoundService.sampleFor(arrow(ArrowKind.ghost)), contains('gost'));
    expect(SoundService.sampleFor(arrow(ArrowKind.bomb)), contains('bomb'));

    // No two specials share a sample.
    final specials = [
      for (final kind in ArrowKind.buyable) SoundService.sampleFor(arrow(kind)),
    ];
    expect(specials.toSet().length, ArrowKind.buyable.length);
  });

  test('plain arrows keep the big/small split', () {
    final small = SoundService.sampleFor(arrow(ArrowKind.normal, length: 3));
    final big = SoundService.sampleFor(arrow(ArrowKind.normal, length: 9));
    expect(small, contains('arrow_small'));
    expect(big, contains('arrow_big'));
    expect(small, isNot(big));
  });

  test('the miss and game-over cues are wired up', () {
    expect(SoundService.missSample, contains('chancemiss'));
    expect(SoundService.gameOverSample, contains('gameover'));
    expect(SoundService.missSample, isNot(SoundService.gameOverSample));

    // They are cues, not arrow sounds — no arrow may claim one of them.
    for (final kind in ArrowKind.values) {
      final fired = SoundService.sampleFor(arrow(kind));
      expect(fired, isNot(SoundService.missSample));
      expect(fired, isNot(SoundService.gameOverSample));
    }
  });

  test('every sample exists on disk and is declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final sample in SoundService.samples) {
      final path = 'assets/$sample';
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$path is missing from the repo',
      );
      expect(
        pubspec,
        contains('- $path'),
        reason: '$path is not declared in pubspec.yaml',
      );
      // A space in an asset path is a needless source of platform trouble.
      expect(sample, isNot(contains(' ')), reason: '$path has a space in it');
    }
  });
}
