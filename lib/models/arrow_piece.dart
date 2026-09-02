import 'dart:ui';

import 'arrow_kind.dart';

// ─── Direction ───────────────────────────────────────────────────────────────

enum ArrowDirection { up, right, down, left }

extension ArrowDirectionX on ArrowDirection {
  Offset get step => switch (this) {
    ArrowDirection.up => const Offset(0, -1),
    ArrowDirection.right => const Offset(1, 0),
    ArrowDirection.down => const Offset(0, 1),
    ArrowDirection.left => const Offset(-1, 0),
  };

  /// One of the two directions at right angles to this one.
  Offset get perpendicular => switch (this) {
    ArrowDirection.up || ArrowDirection.down => const Offset(1, 0),
    ArrowDirection.left || ArrowDirection.right => const Offset(0, 1),
  };
}

// ─── Arrow piece ─────────────────────────────────────────────────────────────

class ArrowPiece {
  ArrowPiece({
    required this.id,
    required this.cells,
    required this.colorIndex,
    this.removed = false,
    this.kind = ArrowKind.normal,
  });

  final int id;
  final List<Offset> cells;
  final int colorIndex;
  bool removed;

  /// Which special this is, if any. Specials show up every few levels, and the
  /// player can also *make* one out of any arrow by spending a token from the
  /// rewards sheet (earned with coins or by watching an ad).
  ArrowKind kind;

  /// True for every arrow that breaks the rules — i.e. anything but a plain
  /// one. Specials always fire, blocked or not.
  bool get special => kind.isSpecial;

  Offset get head => cells.last;

  ArrowDirection get direction {
    final delta = cells.last - cells[cells.length - 2];
    if (delta.dx > 0) return ArrowDirection.right;
    if (delta.dx < 0) return ArrowDirection.left;
    if (delta.dy > 0) return ArrowDirection.down;
    return ArrowDirection.up;
  }

  ArrowPiece copy() => ArrowPiece(
    id: id,
    cells: List<Offset>.from(cells),
    colorIndex: colorIndex,
    removed: removed,
    kind: kind,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'c': [
      for (final cell in cells) [cell.dx.toInt(), cell.dy.toInt()],
    ],
    'k': colorIndex,
    'r': removed,
    // 'sp' is still written so a board saved by this build can still be read
    // by the old home-screen widget code path.
    'sp': special,
    'kd': kind.name,
  };

  static ArrowPiece fromJson(Map<String, dynamic> json) {
    final name = json['kd'] as String?;
    final kind = name != null
        ? ArrowKind.fromName(name)
        : (json['sp'] as bool? ?? false)
        ? ArrowKind.boost
        : ArrowKind.normal;
    return ArrowPiece(
      id: json['id'] as int,
      cells: [
        for (final cell in json['c'] as List)
          Offset((cell[0] as num).toDouble(), (cell[1] as num).toDouble()),
      ],
      colorIndex: json['k'] as int,
      removed: json['r'] as bool,
      kind: kind,
    );
  }
}
