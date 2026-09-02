import 'dart:convert';

import 'arrow_piece.dart';
import 'board_shape.dart';
import 'palette.dart';
import 'silhouette.dart';

/// Everything that defines one live board, serialisable so the app and the
/// home-screen widget play the exact same game.
class BoardData {
  BoardData({
    required this.level,
    required this.generation,
    required this.cleared,
    required this.columns,
    required this.rows,
    required this.silhouette,
    required this.mask,
    required this.pieces,
    required this.palette,
  });

  final int level; // 1-based
  final int generation;
  int cleared;
  final int columns;
  final int rows;

  /// The outline this board was carved out of — a built-in shape, or one the
  /// online designer drew for this level.
  final Silhouette silhouette;

  final Set<int> mask; // cell indices (y * columns + x) that are in play
  final List<ArrowPiece> pieces;
  final Palette palette;

  bool get won => pieces.every((p) => p.removed);

  String toJson() => jsonEncode({
    'v': 2,
    'level': level,
    'gen': generation,
    'cleared': cleared,
    'cols': columns,
    'rows': rows,
    'sil': silhouette.toJson(),
    // Kept so a board written by this build still opens in older code, which
    // only ever read a preset name.
    'shape': switch (silhouette) {
      PresetSilhouette(:final shape) => shape.name,
      _ => BoardShape.rectangle.name,
    },
    'mask': mask.toList(),
    'palette': palette.toHexList(),
    'pieces': [for (final p in pieces) p.toJson()],
  });

  static BoardData? fromJson(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final sil = json['sil'] as Map<String, dynamic>?;
      return BoardData(
        level: json['level'] as int,
        generation: json['gen'] as int,
        cleared: json['cleared'] as int,
        columns: json['cols'] as int,
        rows: json['rows'] as int,
        silhouette: sil != null
            ? Silhouette.fromJson(sil)
            : PresetSilhouette(
                BoardShape.fromName(json['shape'] as String?) ??
                    BoardShape.rectangle,
              ),
        mask: {...(json['mask'] as List).cast<int>()},
        pieces: [
          for (final p in json['pieces'] as List)
            ArrowPiece.fromJson(p as Map<String, dynamic>),
        ],
        palette: Palette.fromHexList(json['palette'] as List) ?? Palette.candy,
      );
    } catch (_) {
      return null;
    }
  }
}
