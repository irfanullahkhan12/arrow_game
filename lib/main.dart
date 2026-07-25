import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  runApp(const ArrowEscapeApp());
}

class ArrowEscapeApp extends StatelessWidget {
  const ArrowEscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arrow Escape',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: GameTheme.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: GameTheme.bgTop,
        useMaterial3: true,
      ),
      home: const GamePage(),
    );
  }
}

// ─── Theme ───────────────────────────────────────────────────────────────────

/// Single source of truth for every colour in the app, so the whole game reads
/// as one soft, candy-coloured set.
class GameTheme {
  // Backdrop: blush → lilac → sky, all very light.
  static const bgTop = Color(0xFFFFF4FA);
  static const bgMid = Color(0xFFF6F1FF);
  static const bgBottom = Color(0xFFEAF7FF);

  // The play area sits on a white card; shape cells get a soft tint.
  static const boardFill = Color(0xFFFFFFFF);
  static const boardEdge = Color(0xFFF0E4FA);
  static const cellTint = Color(0xFFF7F2FC);

  // Text.
  static const ink = Color(0xFF5C4A80);
  static const inkSoft = Color(0xFF9C8FB8);

  // Accents.
  static const accent = Color(0xFFFF6FA5); // bubblegum pink
  static const accentDeep = Color(0xFFEE4F86);
  static const lilac = Color(0xFF9B7BF0);
  static const heart = Color(0xFFFF5C8A);

  static const cardShadow = Color(0x226A4C9C);
  static const softShadow = Color(0x14000000);
}

// ─── Direction ───────────────────────────────────────────────────────────────

enum ArrowDirection { up, right, down, left }

extension ArrowDirectionX on ArrowDirection {
  Offset get step => switch (this) {
    ArrowDirection.up => const Offset(0, -1),
    ArrowDirection.right => const Offset(1, 0),
    ArrowDirection.down => const Offset(0, 1),
    ArrowDirection.left => const Offset(-1, 0),
  };
}

// ─── Arrow piece ─────────────────────────────────────────────────────────────

class ArrowPiece {
  ArrowPiece({
    required this.id,
    required this.cells,
    required this.colorIndex,
    this.removed = false,
  });

  final int id;
  final List<Offset> cells;
  final int colorIndex;
  bool removed;

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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'c': [
      for (final cell in cells) [cell.dx.toInt(), cell.dy.toInt()],
    ],
    'k': colorIndex,
    'r': removed,
  };

  static ArrowPiece fromJson(Map<String, dynamic> json) => ArrowPiece(
    id: json['id'] as int,
    cells: [
      for (final cell in json['c'] as List)
        Offset((cell[0] as num).toDouble(), (cell[1] as num).toDouble()),
    ],
    colorIndex: json['k'] as int,
    removed: json['r'] as bool,
  );
}

// ─── Palette ──────────────────────────────────────────────────────────────────

/// A per-level set of arrow colours. Defaults to the hand-tuned candy set; the
/// designer generates fresh pastel palettes per level, and the online AI can
/// supply its own.
class Palette {
  const Palette(this.colors);

  final List<Color> colors;

  static const candy = Palette([
    Color(0xFFFF6FA5), // bubblegum pink
    Color(0xFF43CFC4), // turquoise
    Color(0xFFFFB03A), // mango
    Color(0xFF9B7BF0), // lavender
    Color(0xFF56B4F5), // sky
    Color(0xFF62CE72), // apple
    Color(0xFFFF8A5C), // coral
    Color(0xFFC77DFF), // orchid
    Color(0xFFEBBB1E), // butter gold
    Color(0xFF2FC4DE), // aqua
    Color(0xFFFF7B9C), // watermelon
    Color(0xFF8B7BEE), // grape
    Color(0xFF46C79B), // jade
    Color(0xFFFF9BC7), // cotton candy
    Color(0xFF97CE55), // lime
  ]);

  /// Seeded pastel palette: hues spread by the golden angle so neighbouring
  /// indices are always far apart on the wheel, saturation/lightness kept in
  /// the candy zone so it matches the theme.
  factory Palette.generate(int seed) {
    final rng = math.Random(seed);
    final baseHue = rng.nextDouble() * 360;
    return Palette([
      for (var i = 0; i < 12; i++)
        HSLColor.fromAHSL(
          1,
          (baseHue + i * 137.508) % 360,
          0.58 + rng.nextDouble() * 0.22,
          0.60 + rng.nextDouble() * 0.08,
        ).toColor(),
    ]);
  }

  int get length => colors.length;

  Color color(int i) => colors[i % colors.length];

  /// Darker edge of the "gummy" arrow — keeps neighbours separated.
  Color deep(int i) =>
      Color.lerp(color(i), const Color(0xFF3A2A55), 0.30)!;

  /// Highlight running along the top of each arrow.
  Color gloss(int i) => Color.lerp(color(i), Colors.white, 0.62)!;

  List<String> toHexList() => [
    for (final c in colors)
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
  ];

  static Palette? fromHexList(List<dynamic> hex) {
    final colors = <Color>[];
    for (final h in hex) {
      final s = h.toString().replaceAll('#', '');
      final v = int.tryParse(s, radix: 16);
      if (v == null || s.length != 6) return null;
      colors.add(Color(0xFF000000 | v));
    }
    return colors.length >= 4 ? Palette(colors) : null;
  }
}

// ─── Board shapes ────────────────────────────────────────────────────────────

/// The silhouette the playing field is carved into. Small levels stay
/// rectangular (a heart needs room to read as a heart); bigger levels rotate
/// through the whole set.
enum BoardShape {
  rectangle('Board'),
  diamond('Diamond'),
  circle('Circle'),
  heart('Heart'),
  cross('Plus');

  const BoardShape(this.label);

  final String label;

  static BoardShape? fromName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// Is normalized point (x, y) — both in [-1, 1] — inside the silhouette?
  bool contains(double x, double y) {
    switch (this) {
      case BoardShape.rectangle:
        return true;
      case BoardShape.diamond:
        return x.abs() + y.abs() <= 1.0;
      case BoardShape.circle:
        return x * x + y * y <= 1.0;
      case BoardShape.heart:
        // Classic implicit heart curve, y flipped to point down.
        final hx = x * 1.3;
        final hy = -y * 1.3 + 0.2;
        final a = hx * hx + hy * hy - 1;
        return a * a * a - hx * hx * hy * hy * hy <= 0;
      case BoardShape.cross:
        return x.abs() <= 0.34 || y.abs() <= 0.34;
    }
  }
}

// ─── Board styles ────────────────────────────────────────────────────────────

/// Offline "level designer": each board is carved under one of these styles,
/// which bias the direction the arrows like to flow in. No network, no API —
/// endless variety for free, and the carver + peeling passes still guarantee
/// every board is fully packed and solvable.
enum BoardStyle {
  freeform('Tangle'),
  waves('Waves'),
  pillars('Pillars'),
  spiral('Spiral'),
  stairs('Stairs');

  const BoardStyle(this.label);

  final String label;

  /// How much this style likes stepping [d] from cell ([x], [y]). Higher wins.
  /// Pure preference — the backtracking carver overrides it when it must.
  double score((int, int) d, int x, int y, int columns, int rows) {
    switch (this) {
      case BoardStyle.freeform:
        return 0;
      case BoardStyle.waves:
        if (d.$2 != 0) return 0;
        return (y.isEven ? d.$1 : -d.$1).toDouble();
      case BoardStyle.pillars:
        if (d.$1 != 0) return 0;
        return (x.isEven ? d.$2 : -d.$2).toDouble();
      case BoardStyle.spiral:
        final cx = x - (columns - 1) / 2.0;
        final cy = y - (rows - 1) / 2.0;
        return (-cy * d.$1 + cx * d.$2) / (cx.abs() + cy.abs() + 1);
      case BoardStyle.stairs:
        return ((x + y).isEven ? (d.$1 - d.$2) : (d.$2 - d.$1)).toDouble();
    }
  }
}

// ─── Board data ──────────────────────────────────────────────────────────────

/// Everything that defines one live board, serialisable so the app and the
/// home-screen widget play the exact same game.
class BoardData {
  BoardData({
    required this.level,
    required this.generation,
    required this.cleared,
    required this.columns,
    required this.rows,
    required this.shape,
    required this.mask,
    required this.pieces,
    required this.palette,
  });

  final int level; // 1-based; level N holds N arrows
  final int generation;
  int cleared;
  final int columns;
  final int rows;
  final BoardShape shape;
  final Set<int> mask; // cell indices (y * columns + x) that are in play
  final List<ArrowPiece> pieces;
  final Palette palette;

  bool get won => pieces.every((p) => p.removed);

  String toJson() => jsonEncode({
    'v': 1,
    'level': level,
    'gen': generation,
    'cleared': cleared,
    'cols': columns,
    'rows': rows,
    'shape': shape.name,
    'mask': mask.toList(),
    'palette': palette.toHexList(),
    'pieces': [for (final p in pieces) p.toJson()],
  });

  static BoardData? fromJson(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      return BoardData(
        level: json['level'] as int,
        generation: json['gen'] as int,
        cleared: json['cleared'] as int,
        columns: json['cols'] as int,
        rows: json['rows'] as int,
        shape: BoardShape.fromName(json['shape'] as String?) ??
            BoardShape.rectangle,
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

// ─── Level factory ───────────────────────────────────────────────────────────

/// Builds boards: level N gets exactly N arrows, the grid is sized to fit
/// them, the silhouette and flow style rotate per level, and every board is
/// provably fully-packed and solvable. Pure and static so the home-widget
/// background isolate can use it too.
class LevelFactory {
  static const minLen = 2;
  static const maxLen = 6;

  static const _steps = <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)];

  static int _key(Offset cell, int columns) =>
      cell.dy.toInt() * columns + cell.dx.toInt();

  /// The one entry point: a solvable, fully-packed board for [level].
  static BoardData generate({
    required int level,
    required int generation,
    required int cleared,
    AiDesign? design,
  }) {
    final n = math.max(1, level);
    final seed = 7000 + level * 1013 + generation * 17;
    final rng = math.Random(seed);

    // Silhouette: rectangles until the board is big enough for shapes to read.
    var shape = BoardShape.rectangle;
    if (n >= 8) {
      shape = design?.shape ??
          BoardShape.values[rng.nextInt(BoardShape.values.length)];
    }

    final style = BoardStyle.values[rng.nextInt(BoardStyle.values.length)];
    final palette =
        design?.palette ?? (level <= 2 ? Palette.candy : Palette.generate(seed));

    final mask = _buildMask(shape, n, rng) ?? _buildMask(BoardShape.rectangle, n, rng)!;

    for (var attempt = 0; attempt < 60; attempt++) {
      final attemptStyle = attempt < 35 ? style : BoardStyle.freeform;
      final cover = _carveFullCover(
        mask,
        n,
        math.Random(seed + attempt * 7919),
        attemptStyle,
      );
      if (cover == null) continue;

      for (var orient = 0; orient < 12; orient++) {
        final ordered = _orientByPeeling(
          cover,
          mask.columns,
          mask.rows,
          math.Random(seed + attempt * 31 + orient),
        );
        if (ordered == null) continue;

        final pieces = _assignColors(ordered, mask.columns, palette.length);
        if (_isSolvable(pieces, mask.columns, mask.rows)) {
          return BoardData(
            level: level,
            generation: generation,
            cleared: cleared,
            columns: mask.columns,
            rows: mask.rows,
            shape: shape,
            mask: mask.cells,
            pieces: pieces,
            palette: palette,
          );
        }
      }
    }

    // Guaranteed fallback: a 2-row strip of N vertical dominoes — full cover,
    // peelable top row first, always solvable.
    final pieces = <ArrowPiece>[
      for (var x = 0; x < n; x++)
        ArrowPiece(
          id: x,
          cells: [Offset(x.toDouble(), 1), Offset(x.toDouble(), 0)],
          colorIndex: x % palette.length,
        ),
    ];
    return BoardData(
      level: level,
      generation: generation,
      cleared: cleared,
      columns: n,
      rows: 2,
      shape: BoardShape.rectangle,
      mask: {for (var i = 0; i < n * 2; i++) i},
      pieces: pieces,
      palette: palette,
    );
  }

  // ── Mask building ─────────────────────────────────────────────────────────

  /// Scales the silhouette until its cell count fits N arrows of length
  /// [minLen]..[maxLen], preferring ~3.5 cells per arrow.
  static _Mask? _buildMask(BoardShape shape, int n, math.Random rng) {
    final targetArea = (n * 3.5).round().clamp(n * minLen, n * maxLen);

    if (shape == BoardShape.rectangle) {
      // Phone-ish aspect. Tiny levels get tiny boards.
      var rows = math.max(2, math.sqrt(targetArea / 0.72).round());
      var columns = math.max(n == 1 ? 1 : 2, (targetArea / rows).round());
      while (columns * rows > n * maxLen) {
        if (rows >= columns) {
          rows--;
        } else {
          columns--;
        }
      }
      while (columns * rows < n * minLen) {
        rows++;
      }
      return _Mask(columns, rows, {
        for (var i = 0; i < columns * rows; i++) i,
      });
    }

    // Grow the silhouette until enough cells fall inside it.
    _Mask? best;
    var bestScore = 1 << 30;
    for (var rows = 5; rows <= 40; rows++) {
      final columns = math.max(4, (rows * 0.95).round());
      final cells = <int>{};
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < columns; x++) {
          final nx = (x + 0.5) / columns * 2 - 1;
          final ny = (y + 0.5) / rows * 2 - 1;
          if (shape.contains(nx, ny)) cells.add(y * columns + x);
        }
      }
      final area = cells.length;
      if (area < n * minLen) continue;
      if (area > n * maxLen) break;
      final mask = _Mask(columns, rows, cells);
      if (!mask.isUsable(minLen)) continue;
      final score = (area - (n * 3.5).round()).abs();
      if (score < bestScore) {
        bestScore = score;
        best = mask;
      }
    }
    return best;
  }

  // ── Carving ───────────────────────────────────────────────────────────────

  /// Splits every cell of [mask] into exactly [n] simple paths with lengths in
  /// [minLen]..[maxLen]. Backtracking with pocket + count pruning.
  static List<List<Offset>>? _carveFullCover(
    _Mask mask,
    int n,
    math.Random random,
    BoardStyle style,
  ) {
    final w = mask.columns;
    final h = mask.rows;
    final total = w * h;

    // Styled boards read better with longer runs (a wave needs room to wave).
    final effectiveMax =
        style == BoardStyle.freeform ? maxLen : maxLen + 2;

    // Cells outside the mask count as covered from the start.
    final covered = List<bool>.filled(total, true);
    for (final i in mask.cells) {
      covered[i] = false;
    }
    var uncovered = mask.cells.length;

    final paths = <List<int>>[];
    var budget = 200000;

    bool pocketsFit() {
      final seen = List<bool>.filled(total, false);
      for (var start = 0; start < total; start++) {
        if (covered[start] || seen[start]) continue;
        var size = 0;
        final stack = <int>[start];
        seen[start] = true;
        while (stack.isNotEmpty) {
          final cell = stack.removeLast();
          size++;
          final cx = cell % w;
          final cy = cell ~/ w;
          for (final d in _steps) {
            final nx = cx + d.$1;
            final ny = cy + d.$2;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final next = ny * w + nx;
            if (covered[next] || seen[next]) continue;
            seen[next] = true;
            stack.add(next);
          }
        }
        if (size < minLen) return false;
      }
      return true;
    }

    // Exact-count pruning: remaining cells must be coverable by the remaining
    // number of arrows.
    bool countFits() {
      final remainingPaths = n - paths.length;
      if (remainingPaths < 0) return false;
      if (uncovered == 0) return remainingPaths == 0;
      if (remainingPaths == 0) return false;
      return uncovered >= remainingPaths * minLen &&
          uncovered <= remainingPaths * effectiveMax;
    }

    late bool Function() placeNext;

    bool grow(List<int> path) {
      if (budget-- <= 0) return false;

      bool tryStop() {
        if (path.length < minLen) return false;
        paths.add(List<int>.from(path));
        if (countFits() && pocketsFit() && placeNext()) return true;
        paths.removeLast();
        return false;
      }

      bool tryExtend() {
        if (path.length >= effectiveMax) return false;
        final last = path.last;
        final lx = last % w;
        final ly = last ~/ w;
        final dirs = List<(int, int)>.from(_steps)..shuffle(random);
        if (style != BoardStyle.freeform) {
          final scores = {
            for (final d in dirs)
              d: style.score(d, lx, ly, w, h) * 2 + random.nextDouble(),
          };
          dirs.sort((a, b) => scores[b]!.compareTo(scores[a]!));
        }
        for (final d in dirs) {
          final nx = lx + d.$1;
          final ny = ly + d.$2;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final next = ny * w + nx;
          if (covered[next]) continue;

          covered[next] = true;
          uncovered--;
          path.add(next);
          if (grow(path)) return true;
          path.removeLast();
          covered[next] = false;
          uncovered++;
        }
        return false;
      }

      final stopChance = style == BoardStyle.freeform ? 0.22 : 0.12;
      final stopFirst =
          path.length >= effectiveMax ||
          (path.length >= minLen && random.nextDouble() < stopChance);

      if (stopFirst) {
        return tryStop() || tryExtend();
      }
      return tryExtend() || tryStop();
    }

    placeNext = () {
      if (budget-- <= 0) return false;
      var start = -1;
      for (var i = 0; i < total; i++) {
        if (!covered[i]) {
          start = i;
          break;
        }
      }
      if (start < 0) return paths.length == n;
      if (paths.length >= n) return false;

      covered[start] = true;
      uncovered--;
      if (grow(<int>[start])) return true;
      covered[start] = false;
      uncovered++;
      return false;
    };

    if (!placeNext()) return null;

    return [
      for (final path in paths)
        [
          for (final i in path)
            Offset((i % w).toDouble(), (i ~/ w).toDouble()),
        ],
    ];
  }

  // ── Orientation (peeling) ─────────────────────────────────────────────────

  static List<List<Offset>>? _orientByPeeling(
    List<List<Offset>> cover,
    int columns,
    int rows,
    math.Random random,
  ) {
    final owner = <int, int>{};
    for (var i = 0; i < cover.length; i++) {
      for (final cell in cover[i]) {
        owner[_key(cell, columns)] = i;
      }
    }

    final gone = <int>{};
    final order = <List<Offset>>[];

    bool rayClear(List<Offset> cells, int self) {
      final head = cells.last;
      final stepDelta = head - cells[cells.length - 2];
      var cursor = head + stepDelta;
      while (cursor.dx >= 0 &&
          cursor.dy >= 0 &&
          cursor.dx < columns &&
          cursor.dy < rows) {
        final other = owner[_key(cursor, columns)];
        if (other != null && other != self && !gone.contains(other)) {
          return false;
        }
        cursor += stepDelta;
      }
      return true;
    }

    while (gone.length < cover.length) {
      final optionIds = <int>[];
      final optionCells = <List<Offset>>[];

      for (var i = 0; i < cover.length; i++) {
        if (gone.contains(i)) continue;
        final forward = cover[i];
        final backward = cover[i].reversed.toList();
        if (rayClear(forward, i)) {
          optionIds.add(i);
          optionCells.add(forward);
        }
        if (rayClear(backward, i)) {
          optionIds.add(i);
          optionCells.add(backward);
        }
      }

      if (optionIds.isEmpty) return null;

      final pick = random.nextInt(optionIds.length);
      order.add(optionCells[pick]);
      gone.add(optionIds[pick]);
    }

    return order;
  }

  // ── Colours ───────────────────────────────────────────────────────────────

  /// Touching arrows must not share a colour — on a packed board they would
  /// read as one shape.
  static List<ArrowPiece> _assignColors(
    List<List<Offset>> ordered,
    int columns,
    int paletteLength,
  ) {
    final count = ordered.length;

    final cellOwner = <int, int>{};
    for (var i = 0; i < count; i++) {
      for (final cell in ordered[i]) {
        cellOwner[_key(cell, columns)] = i;
      }
    }

    final neighbours = List.generate(count, (_) => <int>{});
    for (var i = 0; i < count; i++) {
      for (final cell in ordered[i]) {
        for (final d in _steps) {
          final other = cellOwner[_key(
            cell + Offset(d.$1.toDouble(), d.$2.toDouble()),
            columns,
          )];
          if (other != null && other != i) {
            neighbours[i].add(other);
            neighbours[other].add(i);
          }
        }
      }
    }

    final colorOf = List<int>.filled(count, -1);
    for (var i = 0; i < count; i++) {
      final used = <int>{};
      for (final nb in neighbours[i]) {
        if (colorOf[nb] >= 0) used.add(colorOf[nb]);
      }
      var chosen = i % paletteLength;
      for (var offset = 0; offset < paletteLength; offset++) {
        final candidate = (i * 7 + offset) % paletteLength;
        if (!used.contains(candidate)) {
          chosen = candidate;
          break;
        }
      }
      colorOf[i] = chosen;
    }

    return [
      for (var i = 0; i < count; i++)
        ArrowPiece(id: i, cells: ordered[i], colorIndex: colorOf[i]),
    ];
  }

  // ── Rules (shared by app + widget) ───────────────────────────────────────

  static bool isBlocked(
    ArrowPiece piece,
    List<ArrowPiece> pieces,
    int columns,
    int rows,
  ) {
    final occupied = <int>{};
    for (final other in pieces) {
      if (other.id == piece.id || other.removed) continue;
      for (final cell in other.cells) {
        occupied.add(_key(cell, columns));
      }
    }
    var cursor = piece.head + piece.direction.step;
    while (cursor.dx >= 0 &&
        cursor.dy >= 0 &&
        cursor.dx < columns &&
        cursor.dy < rows) {
      if (occupied.contains(_key(cursor, columns))) return true;
      cursor += piece.direction.step;
    }
    return false;
  }

  static bool _isSolvable(List<ArrowPiece> source, int columns, int rows) {
    final remaining = source.map((e) => e.copy()).toList();
    var removedSomething = true;
    while (remaining.isNotEmpty && removedSomething) {
      removedSomething = false;
      final removable = remaining
          .where((piece) => !isBlocked(piece, remaining, columns, rows))
          .toList();
      if (removable.isNotEmpty) {
        remaining.removeWhere((p) => removable.any((e) => e.id == p.id));
        removedSomething = true;
      }
    }
    return remaining.isEmpty;
  }
}

class _Mask {
  const _Mask(this.columns, this.rows, this.cells);

  final int columns;
  final int rows;
  final Set<int> cells;

  /// Connected, and no pocket smaller than a single arrow.
  bool isUsable(int minLen) {
    if (cells.isEmpty) return false;
    final seen = <int>{};
    for (final start in cells) {
      if (seen.contains(start)) continue;
      var size = 0;
      final stack = <int>[start];
      seen.add(start);
      while (stack.isNotEmpty) {
        final cell = stack.removeLast();
        size++;
        final cx = cell % columns;
        final cy = cell ~/ columns;
        for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + d.$1;
          final ny = cy + d.$2;
          if (nx < 0 || ny < 0 || nx >= columns || ny >= rows) continue;
          final n = ny * columns + nx;
          if (!cells.contains(n) || seen.contains(n)) continue;
          seen.add(n);
          stack.add(n);
        }
      }
      if (size < minLen) return false;
    }
    return true;
  }
}

// ─── AI designer (optional, online) ──────────────────────────────────────────

class AiDesign {
  const AiDesign({this.shape, this.palette});

  final BoardShape? shape;
  final Palette? palette;
}

/// Optional online designer. When an API key is baked in at build time
/// (`flutter build apk --dart-define=AI_API_KEY=sk-ant-...`) and the device is
/// online, the AI picks the board silhouette and colour palette for the next
/// level; the solver still builds the actual board so it is always valid.
/// With no key, or offline, or on any error, the built-in designer runs — the
/// game never needs the network.
class AiDesigner {
  static const _apiKey = String.fromEnvironment('AI_API_KEY');

  static Future<AiDesign?> design(int level) async {
    if (_apiKey.isEmpty) return null;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final request = await client
          .postUrl(Uri.parse('https://api.anthropic.com/v1/messages'))
          .timeout(const Duration(seconds: 4));
      request.headers
        ..set('content-type', 'application/json')
        ..set('x-api-key', _apiKey)
        ..set('anthropic-version', '2023-06-01');
      request.write(
        jsonEncode({
          'model': 'claude-haiku-4-5-20251001',
          'max_tokens': 300,
          'messages': [
            {
              'role': 'user',
              'content':
                  'Design level $level of a cute pastel arrow puzzle game for '
                  'children. Reply with ONLY JSON, no prose: {"shape": one of '
                  '["rectangle","diamond","circle","heart","cross"], "colors": '
                  'array of 12 distinct pastel hex colors like "#FF6FA5" that '
                  'look great together on a white board}.',
            },
          ],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final body = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) return null;

      final text =
          ((jsonDecode(body) as Map)['content'] as List).first['text']
              as String;
      final jsonStart = text.indexOf('{');
      final jsonEnd = text.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd <= jsonStart) return null;
      final design =
          jsonDecode(text.substring(jsonStart, jsonEnd + 1))
              as Map<String, dynamic>;

      return AiDesign(
        shape: BoardShape.fromName(design['shape'] as String?),
        palette: Palette.fromHexList(design['colors'] as List? ?? const []),
      );
    } catch (_) {
      return null; // offline / bad key / bad reply → local designer
    }
  }
}

// ─── Persistence + widget bridge ─────────────────────────────────────────────

class GameStore {
  static const _stateKey = 'board_state';
  static const _widgetProvider = 'ArrowWidgetProvider';

  static Future<BoardData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // the widget isolate may have written newer state
    final raw = prefs.getString(_stateKey);
    if (raw == null) return null;
    return BoardData.fromJson(raw);
  }

  static Future<void> save(BoardData board) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, board.toJson());
    await _pushWidget(board);
  }

  /// Renders the board to a PNG and hands it to the home-screen widget.
  static Future<void> _pushWidget(BoardData board) async {
    if (!Platform.isAndroid) return;
    try {
      final png = await renderBoardPng(board, width: 700);
      await HomeWidget.saveWidgetData(
        'board_png_b64',
        base64Encode(png),
      );
      await HomeWidget.saveWidgetData(
        'widget_status',
        'Level ${board.level}  ·  '
            '${board.pieces.where((p) => !p.removed).length} left',
      );
      await HomeWidget.updateWidget(name: _widgetProvider);
    } catch (_) {
      // Widget refresh must never break the game.
    }
  }
}

/// Draws a board into a PNG (used for the home-screen widget). Runs fine in
/// the widget's background isolate — no widget tree involved.
Future<Uint8List> renderBoardPng(BoardData board, {double width = 700}) async {
  final cell = width / board.columns;
  final size = Size(width, cell * board.rows);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(36)),
    Paint()..color = GameTheme.boardFill,
  );
  GamePainter(
    columns: board.columns,
    rows: board.rows,
    pieces: board.pieces,
    palette: board.palette,
    mask: board.mask,
    moving: const {},
    bumpPieceId: null,
    bumpBlockerId: null,
    bumpStep: Offset.zero,
    bumpCells: 0,
    bumpValue: 0,
  ).paint(canvas, size);

  final image = await recorder
      .endRecording()
      .toImage(size.width.round(), size.height.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

// ─── Widget background callback ──────────────────────────────────────────────

/// Runs in a background isolate when the user presses a button on the
/// home-screen widget — the game is playable without opening the app.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;

  var board = await GameStore.load();
  board ??= LevelFactory.generate(level: 1, generation: 0, cleared: 0);

  switch (uri.host) {
    case 'play':
      // Play one move: remove the first arrow with a clear exit.
      final free = board.pieces
          .where(
            (p) =>
                !p.removed &&
                !LevelFactory.isBlocked(
                  p,
                  board!.pieces,
                  board.columns,
                  board.rows,
                ),
          )
          .toList();
      if (free.isNotEmpty) {
        free.first.removed = true;
      }
      if (board.won) {
        board = LevelFactory.generate(
          level: board.level + 1,
          generation: board.generation + 1,
          cleared: board.cleared + 1,
        );
      }
    case 'new':
      board = LevelFactory.generate(
        level: board.level,
        generation: board.generation + 1,
        cleared: board.cleared,
      );
  }

  await GameStore.save(board);
}

// ─── Game page ───────────────────────────────────────────────────────────────

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _maxLives = 5;

  late BoardData _board;
  int _lives = _maxLives;
  AiDesign? _nextDesign; // prefetched by the online AI, if available

  // Move animation: each firing arrow owns its own controller, so several
  // arrows can fly at once and each one completes its full animation.
  final Map<int, AnimationController> _flights = {};

  // Bump-and-return when a blocked arrow is tapped: it lunges forward, thuds
  // into whatever is in its way, and settles back home.
  late final AnimationController _bumpController;
  late final Animation<double> _bumpAnim;
  int? _bumpPieceId;
  int? _bumpBlockerId;
  Offset _bumpStep = Offset.zero;
  double _bumpCells = 0;

  // Zoom
  final TransformationController _zoom = TransformationController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    )..addListener(() => setState(() {}));
    _bumpController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _bumpPieceId = null;
          _bumpBlockerId = null;
        });
      }
    });
    // Quick lunge out, a beat pressed against the blocker, slower drift back.
    _bumpAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 10),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 60,
      ),
    ]).animate(_bumpController);

    _board = LevelFactory.generate(level: 1, generation: 0, cleared: 0);
    _restoreState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _flights.values) {
      controller.dispose();
    }
    _bumpController.dispose();
    _zoom.dispose();
    super.dispose();
  }

  /// The widget may have played moves while the app was backgrounded — pick
  /// up its state whenever we come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _restoreState();
  }

  Future<void> _restoreState() async {
    final saved = await GameStore.load();
    if (!mounted || saved == null) return;
    setState(() {
      _board = saved;
      _resetTransients();
    });
    _prefetchDesign();
  }

  void _resetTransients() {
    _lives = _maxLives;
    for (final controller in _flights.values) {
      controller.dispose();
    }
    _flights.clear();
    _bumpController.reset();
    _bumpPieceId = null;
    _bumpBlockerId = null;
  }

  /// Ask the online AI (if configured) to style the NEXT level while this one
  /// is being played — zero wait when it arrives, silent fallback otherwise.
  Future<void> _prefetchDesign() async {
    _nextDesign = await AiDesigner.design(_board.level + 1);
  }

  void _newBoard({int? level, bool countClear = false}) {
    setState(() {
      _board = LevelFactory.generate(
        level: level ?? _board.level,
        generation: _board.generation + 1,
        cleared: _board.cleared + (countClear ? 1 : 0),
        design: level != null && level > _board.level ? _nextDesign : null,
      );
      _resetTransients();
    });
    GameStore.save(_board);
    _prefetchDesign();
  }

  // ── Sound ─────────────────────────────────────────────────────────────────

  /// Every fired arrow gets its OWN player, so rapid taps — even two fingers
  /// at once — each play a full sound that overlaps freely with the others.
  /// Big arrows get the deep shot, small arrows the light one.
  Future<void> _playFireSound(ArrowPiece piece) async {
    final big = piece.cells.length >= 4;
    final player = AudioPlayer();
    player.onPlayerComplete.listen((_) => player.dispose());
    try {
      // Same sample, but pitched apart so big and small read differently.
      await player.setPlaybackRate(big ? 0.85 : 1.15);
      await player.play(
        AssetSource(big ? 'sounds/arrow_big.mp3' : 'sounds/arrow_small.mp3'),
      );
    } catch (_) {
      player.dispose(); // sound must never break the game
    }
  }

  // ── Tap logic ─────────────────────────────────────────────────────────────

  /// Walks the exit ray of [piece], reporting the first arrow in the way (if
  /// any) and how many empty cells sit before it.
  ({ArrowPiece? blocker, int freeCells}) _lookAhead(ArrowPiece piece) {
    final owner = <int, ArrowPiece>{};
    for (final other in _board.pieces) {
      // Arrows already flying out no longer block anyone.
      if (other.removed || other.id == piece.id) continue;
      if (_flights.containsKey(other.id)) continue;
      for (final cell in other.cells) {
        owner[cell.dy.toInt() * _board.columns + cell.dx.toInt()] = other;
      }
    }

    final step = piece.direction.step;
    var cursor = piece.head + step;
    var free = 0;

    while (cursor.dx >= 0 &&
        cursor.dy >= 0 &&
        cursor.dx < _board.columns &&
        cursor.dy < _board.rows) {
      final other =
          owner[cursor.dy.toInt() * _board.columns + cursor.dx.toInt()];
      if (other != null) return (blocker: other, freeCells: free);
      free++;
      cursor += step;
    }
    return (blocker: null, freeCells: free);
  }

  Future<void> _tapPiece(ArrowPiece piece) async {
    if (_flights.containsKey(piece.id) || piece.removed) return;

    final ahead = _lookAhead(piece);
    if (ahead.blocker != null) {
      setState(() {
        _lives--;
        _bumpPieceId = piece.id;
        _bumpBlockerId = ahead.blocker!.id;
        _bumpStep = piece.direction.step;
        // Travel the empty run, plus a little extra so the tip visibly
        // presses against the blocker.
        _bumpCells = math.min(ahead.freeCells + 0.35, 2.2);
      });
      _bumpController.forward(from: 0);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.white,
            elevation: 6,
            duration: const Duration(milliseconds: 900),
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFFFD3E4), width: 1.5),
            ),
            content: const Row(
              children: [
                Text('🚧', style: TextStyle(fontSize: 18)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Blocked! Move the arrow in the way first.',
                    style: TextStyle(
                      color: GameTheme.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      if (_lives <= 0) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        _newBoard();
      }
      return;
    }

    _playFireSound(piece);

    // Each arrow flies on its own controller, so tapping several free arrows
    // in quick succession lets every one of them complete its full animation.
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() => setState(() {}));
    setState(() => _flights[piece.id] = controller);

    await controller.forward();
    controller.dispose();
    if (!mounted) return;

    setState(() {
      piece.removed = true;
      _flights.remove(piece.id);
    });
    GameStore.save(_board);

    if (_board.won && _flights.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (mounted) _showWinDialog();
    }
  }

  void _showWinDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: GameTheme.lilac.withValues(alpha: 0.18),
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFE3F0), Color(0xFFE9E2FF)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('🎉', style: TextStyle(fontSize: 38)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Level Clear!',
                style: TextStyle(
                  color: GameTheme.accentDeep,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Well done! Every arrow found its way out 💖',
                style: TextStyle(
                  color: GameTheme.inkSoft,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GameTheme.lilac,
                        side: const BorderSide(
                          color: Color(0xFFDDD1FA),
                          width: 1.6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _newBoard(countClear: true);
                      },
                      child: const Text('New Board'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: GameTheme.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _newBoard(level: _board.level + 1, countClear: true);
                      },
                      child: const Text('Next Level'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Zoom helpers ──────────────────────────────────────────────────────────

  void _zoomBy(double factor) {
    final current = _zoom.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, 4.0);
    setState(() {
      _zoom.value = Matrix4.identity()..scaleByDouble(target, target, 1, 1);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.bgTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        centerTitle: true,
        leadingWidth: 86,
        leading: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: GameTheme.cardShadow,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⭐', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  '${_board.cleared}',
                  style: const TextStyle(
                    color: GameTheme.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: GameTheme.cardShadow,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            'LEVEL ${_board.level}',
            style: const TextStyle(
              color: GameTheme.accentDeep,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 2.4,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _RoundIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'New board',
              onPressed: _newBoard,
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [GameTheme.bgTop, GameTheme.bgMid, GameTheme.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── HUD ──────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Text('👆', style: TextStyle(fontSize: 14)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Tap an arrow with a clear path',
                                style: TextStyle(
                                  color: GameTheme.ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ...List.generate(_maxLives, (i) {
                      final alive = i < _lives;
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 260),
                        scale: alive ? 1.0 : 0.8,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Icon(
                            alive
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: alive
                                ? GameTheme.heart
                                : GameTheme.heart.withValues(alpha: 0.28),
                            size: 20,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              // ── Board ────────────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const pad = 14.0;
                      final cell = math.min(
                        math.min(
                          (constraints.maxWidth - pad * 2) / _board.columns,
                          (constraints.maxHeight - pad * 2) / _board.rows,
                        ),
                        96.0, // tiny early levels shouldn't fill the screen
                      );
                      final boardSize = Size(
                        cell * _board.columns,
                        cell * _board.rows,
                      );

                      return Stack(
                        children: [
                          Center(
                            child: InteractiveViewer(
                              transformationController: _zoom,
                              minScale: 1,
                              maxScale: 4,
                              clipBehavior: Clip.none,
                              child: Container(
                                padding: const EdgeInsets.all(pad),
                                decoration: BoxDecoration(
                                  color: GameTheme.boardFill,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: GameTheme.boardEdge,
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: GameTheme.cardShadow,
                                      blurRadius: 24,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: SizedBox.fromSize(
                                  size: boardSize,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) {
                                      final piece = _pieceAt(
                                        details.localPosition,
                                        cell,
                                      );
                                      if (piece != null) _tapPiece(piece);
                                    },
                                    child: CustomPaint(
                                      size: boardSize,
                                      painter: GamePainter(
                                        columns: _board.columns,
                                        rows: _board.rows,
                                        pieces: _board.pieces,
                                        palette: _board.palette,
                                        mask: _board.mask,
                                        moving: {
                                          for (final entry in _flights.entries)
                                            entry.key: Curves.easeInOutQuart
                                                .transform(entry.value.value),
                                        },
                                        bumpPieceId: _bumpPieceId,
                                        bumpBlockerId: _bumpBlockerId,
                                        bumpStep: _bumpStep,
                                        bumpCells: _bumpCells,
                                        bumpValue: _bumpAnim.value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Zoom controls
                          Positioned(
                            right: 0,
                            bottom: 8,
                            child: Column(
                              children: [
                                _RoundIconButton(
                                  icon: Icons.add_rounded,
                                  tooltip: 'Zoom in',
                                  onPressed: () => _zoomBy(1.35),
                                ),
                                const SizedBox(height: 8),
                                _RoundIconButton(
                                  icon: Icons.remove_rounded,
                                  tooltip: 'Zoom out',
                                  onPressed: () => _zoomBy(1 / 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ArrowPiece? _pieceAt(Offset point, double cell) {
    final active = _board.pieces.where((e) => !e.removed).toList().reversed;
    for (final piece in active) {
      for (var i = 0; i < piece.cells.length - 1; i++) {
        final a = _centerOf(piece.cells[i], cell);
        final b = _centerOf(piece.cells[i + 1], cell);
        if (_distanceToSegment(point, a, b) <= cell * .42) return piece;
      }
    }
    return null;
  }

  Offset _centerOf(Offset cellPosition, double cell) =>
      Offset((cellPosition.dx + .5) * cell, (cellPosition.dy + .5) * cell);

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    final closest = a + ab * t;
    return (p - closest).distance;
  }
}

// ─── Small round icon button ─────────────────────────────────────────────────

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: GameTheme.cardShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: GameTheme.accent, size: 21),
        splashRadius: 22,
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class GamePainter extends CustomPainter {
  GamePainter({
    required this.columns,
    required this.rows,
    required this.pieces,
    required this.palette,
    required this.mask,
    required this.moving,
    required this.bumpPieceId,
    required this.bumpBlockerId,
    required this.bumpStep,
    required this.bumpCells,
    required this.bumpValue,
  });

  final int columns;
  final int rows;
  final List<ArrowPiece> pieces;
  final Palette palette;
  final Set<int> mask;

  /// Per-piece eased flight progress (0 → 1) for arrows currently flying out.
  final Map<int, double> moving;

  /// Blocked-tap feedback: [bumpPieceId] lunges [bumpCells] along [bumpStep],
  /// and [bumpBlockerId] gives a little in the same direction as it is struck.
  final int? bumpPieceId;
  final int? bumpBlockerId;
  final Offset bumpStep;
  final double bumpCells;
  final double bumpValue;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min(size.width / columns, size.height / rows);

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

  // ── Arrow drawing (glossy candy pipes on a light board) ───────────────

  void _drawArrow(
    Canvas canvas,
    ArrowPiece piece,
    double cell,
    bool isMoving,
    double progress,
  ) {
    final color = palette.color(piece.colorIndex);
    final deep = palette.deep(piece.colorIndex);
    final gloss = palette.gloss(piece.colorIndex);

    // Chunky, but narrow enough that two arrows in neighbouring cells never
    // touch — that gap is what keeps a packed board readable.
    final strokeW = math.max(3.0, cell * .30);
    final outlineW = strokeW * 1.42;

    Offset center(Offset p) => Offset((p.dx + .5) * cell, (p.dy + .5) * cell);

    final cellsToDraw = isMoving
        ? _movingSnakePoints(piece, progress)
        : List<Offset>.from(piece.cells);

    if (cellsToDraw.length < 2) return;

    // Blocked-tap nudge. The blocker gives only a fraction, so the collision
    // reads as "this one is in the way" rather than both arrows sliding.
    var nudge = Offset.zero;
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

    final path = Path()
      ..moveTo(center(cellsToDraw.first).dx, center(cellsToDraw.first).dy);
    for (var i = 1; i < cellsToDraw.length; i++) {
      final pt = center(cellsToDraw[i]);
      path.lineTo(pt.dx, pt.dy);
    }

    Paint strokePaint(Color c, double width, {double blur = 0}) {
      final paint = Paint()
        ..isAntiAlias = true
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (blur > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      }
      return paint;
    }

    // 1. Soft drop shadow so the arrow lifts off the white board.
    canvas.save();
    canvas.translate(0, strokeW * .30);
    canvas.drawPath(
      path,
      strokePaint(GameTheme.softShadow, outlineW, blur: strokeW * .45),
    );
    canvas.restore();

    // 2. Darker outline — separates neighbouring arrows.
    canvas.drawPath(path, strokePaint(deep, outlineW));

    // 3. Body.
    canvas.drawPath(path, strokePaint(color, strokeW));

    // 4. Gloss highlight along the top.
    canvas.save();
    canvas.translate(0, -strokeW * .20);
    canvas.drawPath(
      path,
      strokePaint(gloss.withValues(alpha: 0.75), strokeW * .26),
    );
    canvas.restore();

    // ── Arrowhead ──────────────────────────────────────────────────────
    final head = center(cellsToDraw.last);
    final previous = center(cellsToDraw[cellsToDraw.length - 2]);
    final vector = head - previous;
    if (vector.distance <= .001) {
      if (nudge != Offset.zero) canvas.restore();
      return;
    }

    final direction = vector / vector.distance;
    final perpendicular = Offset(-direction.dy, direction.dx);
    final arrowSize = cell * .38;
    final back = head - direction * arrowSize;

    final headPath = Path()
      ..moveTo(head.dx, head.dy)
      ..lineTo(
        (back + perpendicular * arrowSize * .66).dx,
        (back + perpendicular * arrowSize * .66).dy,
      )
      ..moveTo(head.dx, head.dy)
      ..lineTo(
        (back - perpendicular * arrowSize * .66).dx,
        (back - perpendicular * arrowSize * .66).dy,
      );

    canvas.save();
    canvas.translate(0, strokeW * .30);
    canvas.drawPath(
      headPath,
      strokePaint(GameTheme.softShadow, outlineW, blur: strokeW * .45),
    );
    canvas.restore();

    canvas.drawPath(headPath, strokePaint(deep, outlineW));
    canvas.drawPath(headPath, strokePaint(color, strokeW));

    // ── Head dot: a little white bead with a coloured ring ───────────────
    canvas.drawCircle(head, strokeW * .52, Paint()..color = deep);
    canvas.drawCircle(head, strokeW * .34, Paint()..color = Colors.white);

    if (nudge != Offset.zero) canvas.restore();
  }

  // ── Snake animation helpers ───────────────────────────────────────────

  List<Offset> _movingSnakePoints(ArrowPiece piece, double progress) {
    final route = List<Offset>.from(piece.cells);
    final direction = piece.direction.step;
    final head = piece.head;

    final stepsToOutside = switch (piece.direction) {
      ArrowDirection.up => head.dy.toInt() + 2,
      ArrowDirection.right => columns - head.dx.toInt() + 1,
      ArrowDirection.down => rows - head.dy.toInt() + 1,
      ArrowDirection.left => head.dx.toInt() + 2,
    };

    final bodyLength = (piece.cells.length - 1).toDouble();
    for (var i = 1; i <= stepsToOutside + piece.cells.length + 1; i++) {
      route.add(head + direction * i.toDouble());
    }

    final travelDistance = stepsToOutside + bodyLength;
    final tailDistance = travelDistance * progress.clamp(0.0, 1.0);
    final headDistance = tailDistance + bodyLength;

    return _slicePolyline(route, tailDistance, headDistance);
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
